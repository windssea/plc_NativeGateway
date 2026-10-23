"""Freeze a bounded final-software observation window without stopping service."""
import json,time,math,statistics,hashlib,collections
from pathlib import Path
from hub_api import OUT,save
root=OUT.parents[1]
first=json.loads((OUT/'plc-acquisition-final-64.json').read_text())
last=json.loads((OUT/'plc-acquisition-final-64-second.json').read_text())
start,end=first['at'],last['at'];boot=last['bootId'];version=last['configVersion']
release=json.loads((OUT/'release-gateway-64-result.json').read_text())
expected={}
for device in release['config']['devices']:
    u=device['connection']['unitId'];values=dict(voltage=230+u/10,current=(123+u)*.1,frequency=(5000+u)*.01,power=1234+u,energy=100000+u)
    for point in device['points']:expected[(device['deviceId'],point['pointId'])]=values[point['name']]
assert len(expected)==250
data={};acks={};heartbeats=[];conflicts=[];wrong=[]
for line in (OUT/'wire.jsonl').open(encoding='utf8'):
    r=json.loads(line)
    if not r['topic'].startswith('iot/v1/gateway/NG-HUB-2152-01/') or not r['payload']:continue
    p=json.loads(r['payload']);at=r['receivedAt']
    if r['topic'].endswith('/data') and p['bootId']==boot and p['configVersion']==version:
        mid=p['messageId'];old=data.get(mid)
        if old and old['raw']!=r['payload']:conflicts.append(mid)
        if old is None:data[mid]=dict(at=at,payload=p,raw=r['payload'],bytes=len(r['payload'].encode()))
    elif r['topic'].endswith('/data/ack') and p['status']=='STORED':acks.setdefault(p['messageId'],at)
    elif r['topic'].endswith('/heartbeat') and start<=at<=end:heartbeats.append(dict(at=at,payload=p))
window={m:r for m,r in data.items() if start<=r['at']<=end};coverage=set();count=0;gaps=collections.defaultdict(list)
for mid,r in window.items():
    for v in r['payload']['values']:
        key=v['deviceId'],v['pointId'];coverage.add(key);count+=1;gaps[key].append((r['at'],v['timestamp']))
        if key not in expected or v['quality']!='GOOD' or v['value'] is None or not math.isclose(v['value'],expected[key],abs_tol=.0001):wrong.append(v)
intervals=[]
for samples in gaps.values():
    samples=sorted(set(samples));intervals += [b[0]-a[0] for a,b in zip(samples,samples[1:]) if b[1]>a[1]]
resources=[json.loads(l) for l in (OUT/'controller-resources.jsonl').open()]
resources=[r for r in resources if start<=r['receivedAt']<=end]
def extent(key):
    values=[r[key] for r in resources if r.get(key) is not None]
    return dict(min=min(values),max=max(values),mean=statistics.mean(values)) if values else None
latencies=sorted(acks[m]-r['at'] for m,r in window.items() if m in acks)
api1=json.loads((OUT/'verification-final-64.json').read_text());api2=json.loads((OUT/'verification-final-64-second.json').read_text())
observer=json.loads((OUT/'observer.json').read_text())
summary=dict(result='CORE_CLOSED_LOOP_AND_SHORT_FINAL_WINDOW_PASSED',software='native-0.3.1',configVersion=version,
    projectSha256=hashlib.sha256((root/'NativeGateway.pcwex').read_bytes()).hexdigest(),
    window=dict(start=start,end=end,durationSeconds=end-start,resourceSamples=len(resources)),bootId=boot,
    devices=50,points=250,wireCoveredPoints=len(coverage),uniqueBatches=len(window),values=count,
    storedBatches=sum(m in acks for m in window),unconfirmedAtAnalysis=[m for m in window if m not in acks],
    conflictingIds=sorted(set(conflicts)),incorrectValues=wrong,schemaErrors=observer['errors'],
    batchPointCounts=dict(collections.Counter(len(r['payload']['values']) for r in window.values())),
    largestDataBytes=max(r['bytes'] for r in window.values()),
    pointArrivalGapSeconds=dict(max=max(intervals),median=statistics.median(intervals)) if intervals else None,
    businessAckSeconds=dict(min=min(latencies),median=statistics.median(latencies),p95=latencies[math.ceil(.95*len(latencies))-1],max=max(latencies)) if latencies else None,
    heartbeatMessages=len(heartbeats),heartbeatBoots=sorted({h['payload']['bootId'] for h in heartbeats}),
    heartbeatSessions=sorted({h['payload']['sessionId'] for h in heartbeats}),
    heartbeatSampledQueuePeak=max(h['payload']['queue']['batches'] for h in heartbeats),droppedPeak=max(h['payload']['queue']['droppedBatches'] for h in heartbeats),
    cpuPercent=extent('cpuPercent'),actualMemoryPercent=extent('actualMemoryPercent'),iecProgramPercent=extent('iecProgramPercent'),iecDataPercent=extent('iecDataPercent'),
    plcSampleMaxAgeMs=[first['maxSampleAgeMs'],last['maxSampleAgeMs']],apiSampleAges=[api1['sampleAgeSeconds'],api2['sampleAgeSeconds']],
    eightHourTestPassed=False,knownIssues=['Hub concurrent draft/telemetry deadlock observed during preparation; backend locking unchanged',
        'Telemetry Outbox remains RAM-only','Full-schema MQTT LWT unavailable with library 80-byte field','Physical power-cut durability not tested'])
assert not wrong and not conflicts and not observer['errors'] and len(coverage)==250
assert summary['storedBatches']==summary['uniqueBatches'] and summary['droppedPeak']==0
assert len(summary['heartbeatBoots'])==len(summary['heartbeatSessions'])==1
assert all(not a['missing'] and not a['wrong'] and a['currentPoints']==250 for a in [api1,api2])
save('ACCEPTANCE-RESULTS.json',summary)
print(json.dumps({k:v for k,v in summary.items() if k not in ['incorrectValues','schemaErrors','conflictingIds','unconfirmedAtAnalysis','knownIssues']},ensure_ascii=True),flush=True)
