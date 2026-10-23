import json,time
from hub_api import HubApi,OUT,save
state=json.loads((OUT/'fixture.json').read_text()); release=json.loads((OUT/'release-bootstrap.json').read_text())
api=HubApi().login(); path=f'/api/device/{state["parentId"]}/iot-config/releases/{release["id"]}'
current=api.api('GET',path)
if current['status']!='APPLIED':
    save('retry-after-receive-fix.json',api.api('POST',path+'/retry'))
for _ in range(50):
    current=api.api('GET',path)
    print(json.dumps({k:current.get(k) for k in ['id','status','errors','configVersion']}),flush=True)
    if current['status'] in ['APPLIED','REJECTED','FAILED','TIMEOUT']:
        save('release-bootstrap-result.json',current);break
    time.sleep(2)
