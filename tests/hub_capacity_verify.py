"""Verify Hub's actual 50-device release, database projections and wire ACKs."""
import json,time,math,sys
from datetime import datetime
from hub_api import HubApi,OUT,save
state=json.loads((OUT/'fixture.json').read_text());api=HubApi().login()
phase=sys.argv[1] if len(sys.argv)>1 else 'capacity-50'
release_file='release-gateway-64-result.json' if phase.startswith('final-64') else 'release-capacity-50-result.json'
release=json.loads((OUT/release_file).read_text());assert release['status']=='APPLIED'
heartbeat=json.loads((OUT/'latest-NG-HUB-2152-01-heartbeat.json').read_text())
version=release['configVersion'];assert heartbeat['payload']['activeConfigVersion']==version
if phase.startswith('final-64'):assert heartbeat['payload']['agentVersion']=='native-0.3.1'
gateway=dict(source='Hub APPLIED release plus live heartbeat',releaseId=release['id'],heartbeat=heartbeat)
assert len(state['children'])==50
started=time.time();results={};missing=[];wrong=[];ages=[]
for unit,child in state['children'].items():
    u=int(unit);rows=api.api('GET','/api/device/data/'+child+'/latest')
    current=[r for r in rows if r['configVersion']==version];results[unit]=current
    expected=dict(voltage=230+u/10,current=(123+u)*.1,frequency=(5000+u)*.01,power=1234+u,energy=100000+u)
    if len(current)!=5:missing.append(dict(unit=u,count=len(current)))
    for row in current:
        if row['qualityCode']!='GOOD' or row['value'] is None or not math.isclose(row['value'],expected[row['variableName']],abs_tol=.0001):wrong.append(row)
        if phase!='capacity-50' and not row['sourceMessageId'].startswith('d-'+heartbeat['payload']['bootId']+'-'):wrong.append(dict(reason='old boot projection',row=row))
        ages.append(time.time()-datetime.fromisoformat(row['sampledAt'].replace('Z','+00:00')).timestamp())
save('data-'+phase+'.json',results)
diagnostics=api.api('GET','/api/device/iot-diagnostics');save('diagnostics-'+phase+'.json',diagnostics)
summary=dict(at=time.time(),queryDurationSeconds=time.time()-started,configVersion=version,devices=len(results),
             currentPoints=sum(map(len,results.values())),missing=missing,wrong=wrong,
             sampleAgeSeconds=dict(min=min(ages) if ages else None,max=max(ages) if ages else None),gateway=gateway)
save('verification-'+phase+'.json',summary);print(json.dumps(summary),flush=True)
assert not missing and not wrong,summary
