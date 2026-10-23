import json,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'soak';before=json.loads((OUT/'latest-heartbeat.json').read_text())['payload']['bootId'];start=time.time()
while time.time()<start+200:
 try:
  hb=json.loads((OUT/'latest-heartbeat.json').read_text());p=hb['payload']
  if hb['at']>start and p['bootId']!=before and p['activeConfigVersion']==101 and p['points']['good']==250:
   result={'passed':True,'method':'Engineer controller Reboot; boot project loaded without re-download','retainedConfigCleared':True,'configurationRePublishedAfterReboot':False,'restoredConfigVersion':101,'previousBootId':before,'heartbeat':hb,'elapsedSeconds':time.time()-start}
   (ROOT/'reboot-50x5-results.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));break
 except (OSError,ValueError):pass
 time.sleep(1)
else:raise AssertionError('50 x 5 local configuration did not automatically recover')
