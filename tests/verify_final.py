"""Read-only final wire validation against the reference project's validator."""
import json,sys,time
from collections import Counter
from pathlib import Path
sys.path.insert(0,r'D:\work\code\PLCnext-iot\src')
from plcnext_iot.contracts import validate_message,topic_rules
root=Path(__file__).resolve().parent
prefix='iot/v1/gateway/PLC-ENG-01/'
rules=topic_rules();kinds={v['suffix']:k for k,v in rules.items()}
allrows=[json.loads(line) for line in (root/'mqtt-trace.jsonl').read_text().splitlines()]
heartbeats=[r for r in allrows if r['topic']==prefix+'heartbeat' and json.loads(r['payload']).get('agentVersion')=='native-0.1.2']
assert heartbeats,'Final program has not published its heartbeat yet'
latest=json.loads(heartbeats[-1]['payload']);boot=latest['bootId']
first=next(r for r in allrows if boot in r['payload'])['receivedAt']
rows=[r for r in allrows if r['receivedAt']>=first]
issues=[];counts=Counter()
for row in rows:
    suffix=row['topic'].removeprefix(prefix)
    if suffix not in kinds or rules[kinds[suffix]]['direction']!='from_agent':continue
    counts[suffix]+=1
    errors=validate_message(kinds[suffix],row['payload'].encode(),expected_gateway_id='PLC-ENG-01')
    if errors:issues.append({'topic':row['topic'],'issues':[vars(e) for e in errors]})
data=[json.loads(r['payload']) for r in rows if r['topic']==prefix+'data']
good=[]
for message in data:
    if message['configVersion']!=6:continue
    values={v['pointId']:v for v in message['values']}
    if all(p in values and values[p]['quality']=='GOOD' and abs(values[p]['value']-v)<1e-6 for p,v in [('voltage',230.5),('current',12.3)]):good.append(message)
assert good,'No final v6 good samples'
assert not issues,issues
assert latest['activeConfigVersion']==6 and latest['points']=={'total':2,'good':2,'bad':0},latest
acked={json.loads(r['payload'])['messageId'] for r in rows if r['topic']==prefix+'data/ack' and json.loads(r['payload']).get('status')=='STORED'}
result={'verifiedAt':time.time(),'passed':True,'agentVersion':latest['agentVersion'],'bootId':boot,'configVersion':6,'outboundMessagesValidated':sum(counts.values()),'outboundCounts':dict(counts),'contractIssues':issues,'goodBatches':len(good),'storedGoodBatches':sum(m['messageId'] in acked for m in good),'latestHeartbeat':latest,'latestGoodData':good[-1],'persistence':'v6 recovered after final native program download'}
(root/'final-results.json').write_text(json.dumps(result,indent=2,ensure_ascii=False))
print(json.dumps(result,indent=2,ensure_ascii=False))
