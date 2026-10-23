"""Real Hub-owned changes, immutable releases, PLC receipts and persisted data."""
import json,time,uuid,sys,urllib.parse,math
from datetime import datetime
from copy import deepcopy
from hub_api import HubApi,OUT,save
api=HubApi().login(); state=json.loads((OUT/'fixture.json').read_text());parent=state['parentId']
assert state['prefix']=='ng-2152-20261023' and state['gatewayId']=='NG-HUB-2152-01'
phase=sys.argv[1]
def wait_release(release):
    save('release-'+phase+'.json',release)
    for _ in range(80):
        actual=api.api('GET',f'/api/device/{parent}/iot-config/releases/{release["id"]}')
        if actual['status'] in ['APPLIED','REJECTED','FAILED','TIMEOUT']:
            save('release-'+phase+'-result.json',actual)
            assert actual['status']=='APPLIED',actual
            print('APPLIED',actual['configVersion'],flush=True);return actual
        time.sleep(2)
    raise AssertionError('Missing Hub APPLIED')
def publish(ids):
    q=urllib.parse.urlencode([('deviceIds',x) for x in ids]+[('gatewayOnly','false')])
    preview=api.api('GET',f'/api/device/{parent}/iot-config/device-releases/preview?'+q)
    save('preview-'+phase+'.json',preview);assert not preview.get('issues'),preview
    return wait_release(api.api('POST',f'/api/device/{parent}/iot-config/device-releases',
          dict(expectedRevision=preview['draftRevision'],requestId='ng-'+uuid.uuid4().hex,deviceIds=ids,gatewayOnly=False)))
def update(unit,mutate):
    detail=api.api('GET','/api/device/'+state['children'][str(unit)])
    assert detail['deviceCode'].startswith(state['prefix'])
    save(f'child-{unit:03}-before-'+phase+'.json',detail)
    keys=['id','deviceName','deviceCode','typeCode','modelId','parentId','managementStatus','dataCollection','connection','iot','variables']
    body={k:deepcopy(detail[k]) for k in keys}
    body['expectedRevision']=api.api('GET',f'/api/device/{parent}/iot-gateway')['draftRevision']
    mutate(body);save('request-'+phase+'.json',body)
    api.api('PUT','/api/device',body)
    save(f'child-{unit:03}-after-'+phase+'.json',api.api('GET','/api/device/'+detail['id']))
    return publish([detail['id']])
def verify_data(release,counts):
    version=release['configVersion'];deadline=time.time()+45
    while time.time()<deadline:
        allrows={}
        for unit,count in counts.items():
            rows=api.api('GET','/api/device/data/'+state['children'][str(unit)]+'/latest')
            allrows[str(unit)]=[r for r in rows if r['configVersion']==version]
        if all(len(allrows[str(u)])==n and all(r['qualityCode']=='GOOD' and time.time()-datetime.fromisoformat(r['sampledAt'].replace('Z','+00:00')).timestamp()<20 for r in allrows[str(u)]) for u,n in counts.items()):break
        time.sleep(2)
    for unit,rows in allrows.items():
        u=int(unit);expect=dict(voltage=230+u/10,current=(123+u)*.1,frequency=(5000+u)*.01,power=1234+u,energy=100000+u)
        assert len(rows)==counts[u],(unit,len(rows),counts)
        for r in rows:
            assert r['qualityCode']=='GOOD' and math.isclose(r['value'],expect[r['variableName']],abs_tol=.0001),r
            assert r['sourceGatewayId']==state['gatewayId']
            assert time.time()-datetime.fromisoformat(r['sampledAt'].replace('Z','+00:00')).timestamp()<20,r
    save('data-'+phase+'.json',allrows)
    print('Hub stored expected GOOD points',sum(map(len,allrows.values())),flush=True)
    return allrows
if phase=='period':
    def mutate(body):
        for var in body['variables']:
            var['iot']['pollIntervalMs']=2000;var['iot']['reportIntervalMs']=2000
    release=update(1,mutate);verify_data(release,{1:5,2:5})
elif phase=='delete-point':
    def mutate(body):body['variables']=[v for v in body['variables'] if v['varName']!='energy']
    release=update(1,mutate);verify_data(release,{1:4,2:5})
elif phase=='delete-device':
    child=state['children']['2'];detail=api.api('GET','/api/device/'+child)
    assert detail['deviceCode'].startswith(state['prefix'])
    save('child-002-before-delete.json',detail)
    release=wait_release(api.api('DELETE','/api/device/'+child))
    verify_data(release,{1:4})
    for _ in range(10):
        detail=api.api('GET','/api/device/'+child)
        if detail is None or detail.get('deleted')==1:break
        time.sleep(1)
    save('child-002-after-delete.json',detail)
    assert detail is None or detail.get('deleted')==1,detail
    state.setdefault('deletedChildren',{})['2']=state['children'].pop('2')
    state.setdefault('replacementCodes',{})['2']=state['prefix']+'-meter-002-restored'
    save('fixture.json',state)
elif phase=='verify-period':
    verify_data(json.loads((OUT/'release-period-result.json').read_text()),{1:5,2:5})
elif phase=='resume-delete-point':
    release=json.loads((OUT/'release-delete-point.json').read_text())
    current=api.api('GET',f'/api/device/{parent}/iot-config/releases/{release["id"]}')
    if current['status']!='APPLIED':api.api('POST',f'/api/device/{parent}/iot-config/releases/{release["id"]}/retry')
    release=wait_release(release);verify_data(release,{1:4,2:5})
elif phase=='restore-point':
    def mutate(body):
        original=json.loads((OUT/'child-001-before-delete-point.json').read_text())
        missing=next(v for v in original['variables'] if v['varName']=='energy')
        missing.pop('id',None);missing['iot']['pointId']='energy'
        body['variables'].append(missing)
        for var in body['variables']:
            var['iot']['pollIntervalMs']=5000;var['iot']['reportIntervalMs']=5000
    release=update(1,mutate);verify_data(release,{1:5})
else:raise SystemExit('phase required')
save('gateway-after-'+phase+'.json',api.api('GET',f'/api/device/{parent}/iot-gateway'))
