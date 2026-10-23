import csv,json,time,hashlib
from pathlib import Path
root=Path(__file__).resolve().parent
checks={name:json.loads((root/name).read_text()) for name in ['capacity-results-v2.json','frequency-results-v2.json','reboot-results-v2.json','backpressure-results-v2.json','reboot-50x5-results.json']}
with (root/'online-validation-20261023.csv').open(encoding='utf-8-sig',newline='') as f:logs=list(csv.reader(f))
counts={}
for row in logs:counts[row[2]]=counts.get(row[2],0)+1
result={'recordedAt':time.time(),'projectSha256':hashlib.sha256((root.parent/'NativeGateway.pcwex').read_bytes()).hexdigest(),'compile':{'errors':0,'warnings':0,'verifiedInEngineer':True},'hmiUrl':'https://192.168.0.8/ehmi/hmiapp.html','hmi':{'deviceList':'verified with pages 1/7 and 7/7','pointList':'verified with live values','addDeviceAndPoint':'v7 hmi-proof/point-1, 235.0 GOOD','delete':'implemented; final destructive UI confirmation awaiting user approval'},'logs':{'recordsAfterClear':len(logs),'codes':counts,'newStringErrors':counts.get('MSG_ONL0156',0),'explanation':'MSG_ONL0048 are prior failed build attempts; MSG_ONL0050 are explicit controller reboot tests.'},'checks':{name:{k:v for k,v in item.items() if k not in ['samples','heartbeat']} for name,item in checks.items()},'soakSchedule':json.loads((root/'soak/schedule.json').read_text()),'automationId':'nativegateway-8','soakResult':'running, not yet complete'}
(root/'preflight-results-v2.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
assert result['logs']['newStringErrors']==0
assert all(r['passed'] for r in checks.values())
print(json.dumps({'checksPassed':len(checks),'logs':result['logs'],'soak':result['soakSchedule']},ensure_ascii=False))
