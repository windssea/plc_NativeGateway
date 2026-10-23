"""Change the ordinary Hub batch policy and publish only that gateway patch."""
import json,time,uuid
from hub_api import HubApi,OUT,save
state=json.loads((OUT/'fixture.json').read_text());api=HubApi().login();parent=state['parentId'];phase='gateway-64'
previous=json.loads((OUT/'release-capacity-50-result.json').read_text());assert previous['status']=='APPLIED'
request=dict(brokerId=state['brokerId'],gatewayId=state['gatewayId'],enabled=True,
             expectedRevision=previous['sourceRevision'],report=dict(batchIntervalMs=1000,maxBatchPoints=64))
save('gateway-policy-request.json',request)
result=api.api('PUT',f'/api/device/{parent}/iot-gateway',request);save('gateway-policy-draft.json',result)
preview=api.api('GET',f'/api/device/{parent}/iot-config/device-releases/preview?gatewayOnly=true')
save('preview-'+phase+'.json',preview);assert not preview.get('issues'),preview
request=dict(expectedRevision=preview['draftRevision'],requestId='ng-'+uuid.uuid4().hex,deviceIds=[],gatewayOnly=True)
save('publish-request-'+phase+'.json',request)
release=api.api('POST',f'/api/device/{parent}/iot-config/device-releases',request);save('release-'+phase+'.json',release)
print(json.dumps({k:release.get(k) for k in ['id','configVersion','status','commandKind','operations','gateway']}),flush=True)
for _ in range(80):
    actual=api.api('GET',f'/api/device/{parent}/iot-config/releases/{release["id"]}')
    if actual['status'] in ['APPLIED','REJECTED','FAILED','TIMEOUT']:
        save('release-'+phase+'-result.json',actual);assert actual['status']=='APPLIED',actual;print('APPLIED gateway batch limit 64',actual['configVersion'],flush=True);break
    time.sleep(2)
else:raise AssertionError('Missing batch policy APPLIED')
