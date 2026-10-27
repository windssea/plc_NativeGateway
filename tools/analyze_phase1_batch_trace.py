"""Correlate diagnostic PLC lifecycle, passive MQTT and bounded Hub traces by identity.

Monotonic clocks are compared only within their own host. No cross-host clock
subtraction, generated ACKs or optimistic local release counts are used.
"""
import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import statistics


def journal(path):
    return [json.loads(s) for s in path.read_text(encoding='utf-8').splitlines() if s.strip()]


def stats(values):
    values=sorted(values)
    if not values:return None
    return dict(count=len(values),min=values[0],median=statistics.median(values),
                mean=statistics.mean(values),p95=values[math.ceil(len(values)*.95)-1],max=values[-1])


def analyze(plc, hub, wire, boot, complete=False):
    events=journal(plc); hubs=journal(hub)
    lifecycle={}; sdk=collections.defaultdict(list)
    ordinals=[]
    for row in events:
        if row['kind']!='batchLifecycle':continue
        assert row['bootId']==boot
        e=row['event'];ordinals.append(e['Ordinal']);key=(e['Id'],e['Generation'],e['Slot'])
        if e['Kind']==1:
            assert key not in lifecycle,'Duplicate local release trace'
            lifecycle[key]=e
        elif e['Kind']==2:sdk[key].append(e)
        else:raise AssertionError('Unknown lifecycle event kind')
    assert ordinals==list(range(1,len(ordinals)+1)),'PLC trace gap'
    hubrows={};instances=set()
    for row in hubs:
        if row['kind']!='hubDiagnostics':continue
        s=row['snapshot'];instances.add(s['instanceId'])
        for t in s['batchTraces']:
            if t.get('bootId')==boot:hubrows[t['messageId']]=t
    assert len(instances)==1,'Hub instance changed'
    w=json.loads(wire.read_text(encoding='utf-8'));assert not w['truncated']
    data={};acks={}
    for r in w['rows']:
        v=json.loads(r['payload']);m=v.get('messageId')
        if r['topic'].endswith('/data') and v.get('bootId')==boot:
            assert hashlib.sha256(r['payload'].encode()).hexdigest()==r['sha256']
            data.setdefault(m,[]).append((r,v))
        elif r['topic'].endswith('/ack') and v.get('status')=='STORED':acks.setdefault(m,[]).append(r)
    rows=[];missing=[]
    for key,e in lifecycle.items():
        m=e['Id'];h=hubrows.get(m);d=data.get(m);a=acks.get(m);tx=sdk.get(key)
        if not h or not d or not a or not tx or not h['handlerFinished'] or not h['ackFinished']:
            missing.append(m);continue
        assert h['outcome']=='STORED' and not h['ackFailed']
        assert int(h['values'])==e['Count']==len(d[0][1]['values'])
        assert int(h['payloadBytes'])==e['Bytes']==len(d[0][0]['payload'].encode())
        order=['BuildBeginUs','JsonDoneUs','BuildDoneUs','SendHashDoneUs','FirstSubmitUs','AckRxUs','AckParsedUs','AckHashDoneUs','ReleaseUs']
        times=[e[k] for k in order]
        assert all(times) and times==sorted(times),(m,dict(zip(order,times)))
        end=next((t for t in tx if t['Attempts']==e['Attempts']),None)
        assert end is not None and end['SdkDoneUs']>=e['LastSubmitUs']
        sample=dict(messageId=m,values=e['Count'],bytes=e['Bytes'],attempts=e['Attempts'])
        for name,left,right in [('jsonElapsedMs','BuildBeginUs','JsonDoneUs'),('buildHashElapsedMs','JsonDoneUs','BuildDoneUs'),
                                ('readyToSubmitMs','BuildDoneUs','FirstSubmitUs'),('submitToAckRxMs','FirstSubmitUs','AckRxUs'),
                                ('ackParseMs','AckRxUs','AckParsedUs'),('ackToReleaseMs','AckParsedUs','ReleaseUs'),
                                ('batchLifecycleMs','BuildBeginUs','ReleaseUs')]:sample[name]=(e[right]-e[left])/1000
        sample['submitToSdkDoneMs']=(end['SdkDoneUs']-e['LastSubmitUs'])/1000
        for field in ['BuilderOtherUs','BuilderHashUs','SendHashUs','AckHashUs','DeliveryOtherUs']:sample[field]=e[field]
        sample['hubNanos']={k:int(v) for k,v in h['timingsNanos'].items()}
        sample['wireDataToStoredMs']=min(r['observedUtcMs'] for r in a)-d[0][0]['observedUtcMs']
        rows.append(sample)
    if complete:
        assert events[-1]['kind']=='end' and events[-1]['exportCompleted']
        assert hubs[-1]['kind']=='end' and hubs[-1]['exportCompleted']
        assert not missing and len(rows)==len(data)>0,(len(rows),len(data),missing)
    full=[r for r in rows if r['values']==64]
    fields=[k for k in (full[0] if full else {}) if k.endswith(('Ms','Us'))]
    return dict(bootId=boot,diagnosticOnly=True,P06Accepted=False,complete=complete,
                plcReleaseRows=len(lifecycle),wireUniqueBatches=len(data),joinedBatches=len(rows),
                joinedValues=sum(r['values'] for r in rows),missingBatches=missing,full64Batches=len(full),
                full64Statistics={k:stats([r[k] for r in full]) for k in fields},
                full64HubMilliseconds={k:stats([r['hubNanos'][k]/1e6 for r in full if k in r['hubNanos']])
                    for k in sorted(set(k for r in full for k in r['hubNanos']))},batches=rows)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['plc','hub','wire','output']:p.add_argument(name,type=Path)
    p.add_argument('--boot',required=True);p.add_argument('--complete',action='store_true');a=p.parse_args()
    r=analyze(a.plc,a.hub,a.wire,a.boot,a.complete);a.output.write_text(json.dumps(r,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in r.items() if k!='batches'}))
