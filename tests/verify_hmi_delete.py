import json,sys,time
from pathlib import Path
root=Path(__file__).resolve().parent;out=root/'soak';version=int(sys.argv[1]);devices=int(sys.argv[2]);points=int(sys.argv[3]);start=time.time();deadline=start+65
while time.time()<deadline:
 try:
  hb=json.loads((out/'latest-heartbeat.json').read_text());p=hb['payload']
  if hb['at']>start and p['activeConfigVersion']==version and len(p['devices'])==devices and p['points']=={'total':points,'good':points,'bad':0}:
   result={'passed':True,'configVersion':version,'devices':devices,'points':points,'heartbeat':hb,'elapsedSeconds':time.time()-start}
   (root/f'hmi-delete-v{version}-results.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='heartbeat'}));break
 except (OSError,ValueError,KeyError):pass
 time.sleep(.5)
else:raise AssertionError(f'HMI delete {version}: expected {devices} devices {points} GOOD points')
