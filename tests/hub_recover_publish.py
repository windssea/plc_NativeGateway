"""Recover an ambiguous HTTP timeout using the exact saved Hub requestId."""
import json,time,sys
from hub_api import HubApi,OUT,save
phase=sys.argv[1];state=json.loads((OUT/'fixture.json').read_text());request=json.loads((OUT/('publish-request-'+phase+'.json')).read_text())
api=HubApi().login();path=f'/api/device/{state["parentId"]}/iot-config/releases';deadline=time.time()+210
while time.time()<deadline:
    rows=api.api('GET',path);matches=[x for x in rows if x.get('requestId')==request['requestId']]
    if matches:
        assert len(matches)==1;release=matches[0];save('release-'+phase+'.json',release)
        current=api.api('GET',path+'/'+release['id'])
        print(json.dumps({k:current.get(k) for k in ['id','configVersion','status','errors']}),flush=True)
        if current['status'] in ['APPLIED','REJECTED','FAILED','TIMEOUT']:
            save('release-'+phase+'-result.json',current);assert current['status']=='APPLIED',current;break
    else:print('Saved requestId not committed yet; no duplicate publish issued.',flush=True)
    time.sleep(3)
else:raise AssertionError('Ambiguous publish still unresolved; inspect server before retrying')
