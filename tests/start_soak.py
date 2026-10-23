import json,time,datetime,sys
from pathlib import Path
root=Path(__file__).resolve().parent;out=root/'soak';deadline=time.time()+180
version=int(sys.argv[1]) if len(sys.argv)>1 else 101
assert not (out/'control.json').exists(),'Soak already configured; preserve its original start/end'
while time.time()<deadline:
 try:
  s=json.loads((out/'summary.json').read_text());h=s.get('heartbeat') or {};r=s.get('controllerResources') or {}
  ready=(s['coveredPoints']==250 and s['pointsSeenLast20s']==250 and s['maxCurrentPointAgeSeconds']<12 and h.get('activeConfigVersion')==version and h['points']['good']==250 and h['queue']['batches']==0 and h['queue']['droppedBatches']==0 and s['heartbeatAgeSeconds']<10 and s['controllerResourcesAgeSeconds']<20 and isinstance(r.get('actualMemoryPercent'),(int,float)) and r['actualMemoryPercent']<90 and r['cpuPercent']<85)
  if ready:
   now=time.time();control={'startAt':now,'durationSeconds':28800,'configVersion':version,'deviceCount':50,'pointsPerDevice':5,'pollIntervalMs':5000,'reportIntervalMs':5000,'broker':'127.0.0.1:1883','configFile':f'config-soak-{version}.json','expectedFile':'expected-50x5.json' if version==104 else 'expected-soak-101.json','preflightSummary':s}
   temp=out/'control.tmp';temp.write_text(json.dumps(control,indent=2));temp.replace(out/'control.json')
   result={'startAt':now,'endAt':now+28800,'startLocal':datetime.datetime.fromtimestamp(now).isoformat(timespec='seconds'),'endLocal':datetime.datetime.fromtimestamp(now+28800).isoformat(timespec='seconds'),'durationHours':8,'initialResources':r}
   (out/'schedule.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));break
 except (OSError,ValueError,KeyError,TypeError):pass
 time.sleep(1)
else:raise AssertionError('Preconditions for 8-hour soak not met; timer not started')
