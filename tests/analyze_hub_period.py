"""Measure the real v2 point periods before the later maintenance pauses."""
import json,statistics,collections
from hub_api import OUT,save
state=json.loads((OUT/'fixture.json').read_text());series=collections.defaultdict(set)
for line in (OUT/'wire.jsonl').open(encoding='utf8'):
    row=json.loads(line)
    if not row['topic'].endswith('/NG-HUB-2152-01/data'):continue
    p=json.loads(row['payload'])
    if p['configVersion']!=2:continue
    for v in p['values']:
        if v['quality']=='GOOD':series[(v['deviceId'],v['pointId'])].add(v['timestamp'])
result=[]
for (device,point),timestamps in series.items():
    times=sorted(timestamps);gaps=[b-a for a,b in zip(times,times[1:]) if b-a<15000]
    result.append(dict(deviceId=device,pointId=point,samples=len(times),medianGapMs=statistics.median(gaps) if gaps else None,
                       minGapMs=min(gaps) if gaps else None,maxGapMs=max(gaps) if gaps else None))
save('period-wire-measurements.json',result)
print(json.dumps(result))
