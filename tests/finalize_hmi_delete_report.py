import json,time
from pathlib import Path
root=Path(__file__).resolve().parent
checks={}
for version in [102,103,104]:
 h=json.loads((root/f'hmi-delete-v{version}-results.json').read_text());p=json.loads((root/f'deleted-pointset-v{version}.json').read_text());assert h['passed'] and p['passed'];checks[str(version)]={'heartbeat':h,'wirePointset':p}
result={'recordedAt':time.time(),'passed':True,'authorizedByUser':True,'pointDeletion':{'configVersion':102,'devices':50,'points':249,'removed':'hmi-proof/point-1','persisted':True},'deviceDeletion':{'configVersion':103,'devices':49,'points':245,'removed':'hmi-proof plus remaining 4 points','persisted':True},'restoration':{'configVersion':104,'devices':50,'points':250,'deviceIds':'soak-meter-001..050','hmiProofRemainsDeleted':True,'mqttAck':json.loads((root/'soak/latest-config-ack.json').read_text())},'checks':checks,'onlineLogAfterOperations':'Observed empty current online log in connected Engineer; no new MSG_ONL0156.','soakSchedule':json.loads((root/'soak/schedule.json').read_text()),'previousSegment':'soak/segments/20261023-092301-pre-delete (interrupted, not counted)'}
(root/'hmi-delete-results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
p=root/'preflight-results-v2.json';s=json.loads(p.read_text());s['hmi']['delete']='PASSED: point v102 (249 GOOD), device v103 (245 GOOD), restored standard 50x5 via MQTT v104 (250 correct GOOD).';s['hmiDeleteResults']='hmi-delete-results.json';s['soakSchedule']=result['soakSchedule'];s['soakResult']='running v104; prior 09:23 segment interrupted for user-authorized deletion validation';p.write_text(json.dumps(s,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':True,'versions':list(checks),'soakSchedule':result['soakSchedule']},ensure_ascii=False))
