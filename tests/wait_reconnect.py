import json,time
from pathlib import Path
root=Path(__file__).resolve().parent
def rows():
    return [json.loads(line) for line in (root/'mqtt-trace.jsonl').read_text().splitlines()]
def heartbeats():
    return [(r,json.loads(r['payload'])) for r in rows() if r['topic'].endswith('/heartbeat') and json.loads(r['payload']).get('agentVersion')=='native-0.1.2']
existing=heartbeats();assert existing,'Program heartbeat not available'
before=existing[-1][1];start=time.time();end=time.monotonic()+60
print('Waiting for a new MQTT session after',before['sessionId'],flush=True)
while time.monotonic()<end:
    found=[(r,p) for r,p in heartbeats() if r['receivedAt']>=start and p['bootId']==before['bootId'] and p['sessionId']!=before['sessionId']]
    if found:
        record,after=found[-1]
        data=[json.loads(r['payload']) for r in rows() if r['receivedAt']>=record['receivedAt'] and r['topic'].endswith('/data')]
        if data and after['points']=={'total':2,'good':2,'bad':0}:
            result={'passed':True,'test':'HMI broker save and reconnect','beforeSessionId':before['sessionId'],'afterSessionId':after['sessionId'],'bootId':after['bootId'],'activeConfigVersion':after['activeConfigVersion'],'heartbeat':after,'data':data[-1]}
            (root/'reconnect-results.json').write_text(json.dumps(result,indent=2))
            print(json.dumps(result,indent=2),flush=True);break
    time.sleep(0.5)
else:raise AssertionError('No healthy MQTT reconnection observed')
