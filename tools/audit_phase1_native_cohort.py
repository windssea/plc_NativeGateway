"""Offline full-boot cohort proof from independent RSC copies and real wire ACK.

Does not query DB or treat an agent eligibility output as an oracle. The current
profile must begin at activation and end paused/drained, without capacity loss.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path

QUALITY={1:'UNKNOWN',2:'GOOD',3:'STALE',4:'BAD_CONNECTION',5:'BAD_TIMEOUT',6:'BAD_PROTOCOL',7:'BAD_DECODE'}


def audit(trace,wire,final,output):
    journal=[json.loads(line) for line in trace.read_text(encoding='utf-8').splitlines()]
    assert journal[-1]['kind']=='end' and journal[-1]['exportCompleted'],'Incomplete recorder'
    assert not any(r['kind']=='failure' for r in journal),'Recorder failed'
    boot=journal[-1]['bootId']; configs={}; captured={}; associations=[]
    for row in journal:
        if row['kind']=='dictionary':configs[tuple(row['configKey'])]=row['config']
        elif row['kind']=='capture':
            assert row['bootId']==boot
            seq=row['event']['Event.SampleSeq']
            assert seq not in captured,'Duplicate source identity'
            captured[seq]=row
        elif row['kind']=='association':
            assert row['bootId']==boot
            associations.append(row['association'])
    end=json.loads(final.read_text(encoding='utf-8-sig'))
    assert end['BootId']==boot and not end['Active.enabled']
    assert end['CaptureBuffer.OwnedCount']==end['CaptureBuffer.IngressCount']==0
    assert end['CaptureBuffer.AuditDropped']==end['CaptureBuffer.AssociationDropped']==0
    assert end['CaptureBuffer.EvidenceComplete'] and not end['CaptureBuffer.CaptureStopped']
    count=end['CaptureBuffer.CapturedEventsTotal']
    assert set(captured)==set(range(1,count+1)) and journal[-1]['capture']==count,'Missing source prefix/tail'
    groups=collections.defaultdict(list)
    for seq,row in sorted(captured.items()):
        event=row['event'];cfg=configs[tuple(row['configKey'])]
        groups[(tuple(row['configKey']),event['Event.SamplingGeneration'],event['Event.ClockRevision'])].append((seq,event,cfg))
    expected=set(); filtered=set(); missed=0
    for rows in groups.values():
        first=rows[0][1]
        assert first['Event.Kind']==2 and first['Event.Quality']==1,'Activation origin unavailable'
        due=first['Event.CompletedMonoMs'];baseline=None
        for seq,event,cfg in rows:
            p=event['Event.PointIndex'];base=f'Config.Points[{p}].'
            mode=cfg[base+'reportMode'];interval=cfg[base+'reportIntervalMs']
            assert mode in ('cyclic','change','change_or_cyclic') and interval>0
            quality=event['Event.Quality'];value=event['Event.Value']
            present=bool(event['Event.Flags']&1) and bool(event['Event.Flags']&10)
            assert present,'This no-loss cohort requires a frozen compatible timestamp'
            chosen=baseline is None or quality!=baseline[0]
            if baseline is not None and mode!='cyclic' and quality==baseline[0]==2:
                if cfg[base+'dataType']=='bool':chosen=chosen or (value==0)!=(baseline[1]==0)
                else:chosen=chosen or abs(value-baseline[1])>cfg[base+'deadband']
            if event['Event.Kind']==1 and mode!='change' and event['Event.NominalDueMonoMs']>=due:
                slots=(event['Event.NominalDueMonoMs']-due)//interval+1
                missed+=slots-1;due+=slots*interval;chosen=True
            if chosen:
                expected.add(seq);baseline=quality,value
                assert event['Decision']==2,'Independent selection differs from RAM admission'
            else:
                filtered.add(seq)
                assert event['Decision']==1,'Independent filtering differs'
    rawwire=json.loads(wire.read_text(encoding='utf-8'))
    assert not rawwire['truncated'],'Wire recorder truncated'
    batches={};acks=set()
    for row in rawwire['rows']:
        assert hashlib.sha256(row['payload'].encode()).hexdigest()==row['sha256']
        body=json.loads(row['payload'])
        if row['topic'].endswith('/data') and body.get('bootId')==boot:
            assert not row['retained']
            mid=body['messageId']
            if mid in batches:assert batches[mid]['payload']==row['payload'],'Payload changed on retry'
            batches[mid]=row
        elif row['topic'].endswith('/data/ack') and body['messageId'].startswith('d-'+boot+'-'):
            assert not row['retained']
            if body['status']=='STORED':acks.add(body['messageId'])
    stored=set();mapping=[];ids=set()
    assert [r['Ordinal'] for r in associations]==list(range(1,len(associations)+1))
    for assoc in associations:
        mid=assoc['MessageId'];assert mid not in ids;ids.add(mid)
        assert mid in batches and mid in acks,'Missing real DATA or STORED'
        row=batches[mid];body=json.loads(row['payload'])
        assert assoc['Digest']==row['sha256'] and assoc['Count']==len(body['values'])
        assert len(assoc['sampleSeqs'])==assoc['Count'] and len(row['payload'].encode())<=16380
        for index,seq in enumerate(assoc['sampleSeqs']):
            assert seq in expected and seq not in stored,'Foreign or repeated source identity'
            event=captured[seq]['event'];cfg=configs[tuple(captured[seq]['configKey'])]
            p=event['Event.PointIndex'];value=body['values'][index]
            assert body['configVersion']==cfg['Config.Version']
            assert value['deviceId']==cfg['deviceId'] and value['pointId']==cfg[f'Config.Points[{p}].pointId']
            assert value['quality']==QUALITY[event['Event.Quality']]
            assert value['timestamp']==event['Event.CapturedUtcMs']
            expected_value=event['Event.Value'] if event['Event.Quality']==2 else None
            if expected_value is not None and cfg[f'Config.Points[{p}].dataType']=='bool':expected_value=expected_value!=0
            assert value['value']==expected_value,'Original sample value changed'
            stored.add(seq)
            mapping.append(dict(sampleSeq=seq,messageId=mid,valueOrdinal=index,payloadHash=row['sha256']))
    assert ids==set(batches)==acks and stored==expected,'Incomplete eligible/STORED multiset'
    assert end['CaptureBuffer.EligibleEventsTotal']==len(expected)==end['CaptureBuffer.StoredConfirmedEventsTotal']
    assert end['CaptureBuffer.PolicyFilteredEventsTotal']==len(filtered)
    assert end['CaptureBuffer.MissedReportSlotsTotal']==missed
    for name in ['TimeInvalidEventsTotal','CaptureOverflowEventsTotal','UndecidedLostEventsTotal',
                 'KnownUnsentEventsTotal','IsolatedEventsTotal','UncertainDeliveryEventsTotal','EnqueueRejectedAttemptsTotal']:
        assert end['CaptureBuffer.'+name]==0,name
    report=dict(evidenceLevel='INDEPENDENT_RAW_SOURCE_POLICY_ASSOCIATION_WIRE_STORED_LOCAL_RELEASE',
        bootId=boot,captured=count,eligible=len(expected),filtered=len(filtered),stored=len(stored),
        batches=len(ids),cohortComplete=True,globalAccountingComplete=False,
        previousRamRestartLoss='UNKNOWN',timeMode='SYSTEM_RTC_COMPAT_UNVERIFIED',
        databaseReceiptsVerified=False,performancePassed=False)
    output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    output.with_suffix('.mapping.json').write_text(json.dumps(mapping,separators=(',',':')),encoding='utf-8')
    print(json.dumps(report))


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    for name in ['trace','wire','final','output']:ap.add_argument(name,type=Path)
    args=ap.parse_args();audit(args.trace,args.wire,args.final,args.output)
