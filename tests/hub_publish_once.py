"""Publish the dedicated fixture through Hub and wait for its real APPLIED receipt."""
import json,time,uuid,urllib.parse,sys
from hub_api import HubApi,OUT,save
state=json.loads((OUT/'fixture.json').read_text(encoding='utf-8'))
assert state['gatewayId']=='NG-HUB-2152-01' and state['prefix']=='ng-2152-20261023'
api=HubApi().login();parent=state['parentId']
phase=sys.argv[1] if len(sys.argv)>1 else 'bootstrap'
gateway=api.api('GET',f'/api/device/{parent}/iot-gateway');save('gateway-before-'+phase+'.json',gateway)
assert not gateway.get('configDrift'), 'Hub reports config drift; do not bypass its guard'
ids=list(state['children'].values())
query=urllib.parse.urlencode([('deviceIds',v) for v in ids]+[('gatewayOnly','false')])
preview=api.api('GET',f'/api/device/{parent}/iot-config/device-releases/preview?'+query)
save('preview-'+phase+'.json',preview)
assert not preview.get('issues'),preview.get('issues')
request=dict(expectedRevision=preview['draftRevision'],requestId='ng-'+uuid.uuid4().hex,deviceIds=ids,gatewayOnly=False)
save('publish-request-'+phase+'.json',request)
release=api.api('POST',f'/api/device/{parent}/iot-config/device-releases',request)
save('release-'+phase+'.json',release)
print(json.dumps({'phase':phase,'release':release},ensure_ascii=False),flush=True)
end=time.time()+150
while time.time()<end:
    actual=api.api('GET',f'/api/device/{parent}/iot-config/releases/{release["id"]}')
    if actual.get('status') in ('APPLIED','REJECTED','FAILED','TIMEOUT'):
        save('release-'+phase+'-result.json',actual)
        print(json.dumps({'phase':phase,'status':actual.get('status'),'configVersion':actual.get('configVersion'),'errors':actual.get('errors')},ensure_ascii=False),flush=True)
        assert actual['status']=='APPLIED',actual
        break
    time.sleep(2)
else:raise AssertionError('Hub release did not receive APPLIED in 150 seconds')
