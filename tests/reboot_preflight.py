import json,time
from pathlib import Path
ROOT=Path(__file__).resolve().parent;OUT=ROOT/'soak';before='eng-1792717766000-10';start=time.time();end=start+160
while time.time()<end:
 try:
  hb=json.loads((OUT/'latest-heartbeat.json').read_text());p=hb['payload']
  if hb['at']>start and p['bootId']!=before and p['activeConfigVersion']==8 and p['points']['good']==3:
   result={'passed':True,'method':'Engineer Reboot (Ctrl+Alt+F6); stored boot project loaded','retainedConfigVersion':6,'restoredConfigVersion':8,'previousBootId':before,'heartbeat':hb,'elapsedSeconds':time.time()-start}
   (ROOT/'reboot-results-v2.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));break
 except (OSError,ValueError):pass
 time.sleep(1)
else:raise AssertionError('v8 with 3 GOOD points did not recover after controller reboot')
