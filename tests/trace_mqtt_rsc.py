"""Read-only native MQTT diagnostics during a real Hub release retry."""
import time,json
import probe_hmi_rsc as sdk
from hub_api import HubApi,OUT,save
state=json.loads((OUT/'fixture.json').read_text())
release=json.loads((OUT/'release-bootstrap.json').read_text())
api=HubApi().login()
actual=api.api('GET',f'/api/device/{state["parentId"]}/iot-config/releases/{release["id"]}')
save('release-before-retry.json',actual)
print('release state',actual['status'],flush=True)
fields=['HMI.ProtocolStatus','MainInstance.Mqtt.ErrorText','MainInstance.Mqtt.ReceiveStatus.udtDiag.strDiagMsg',
        'MainInstance.Mqtt.ReceiveStatus.udtDiag.wDiagCode','MainInstance.Mqtt.ReceiveStatus.udtDiag.wAddDiagCode',
        'MainInstance.Mqtt.PublishStatus.udtDiag.strDiagMsg','MainInstance.Mqtt.CheckStatus.udtDiag.strDiagMsg',
        'MainInstance.Mqtt.NewMessage','MainInstance.Mqtt.ConsumeReq','MainInstance.Mqtt.ReceiveStatus.xDone']
with sdk.Device('192.168.0.8') as device, (OUT/'mqtt-rsc-trace.jsonl').open('a',encoding='utf8') as out:
    service=sdk.IDataAccessService(device)
    deadline=time.time()+70; previous=None; sent=False; start=time.time()
    while time.time()<deadline:
        values={f:str(service.ReadSingle('Arp.Plc.Eclr/'+f)) for f in fields}
        if values!=previous:
            row=dict(at=time.time(),values=values);out.write(json.dumps(row)+'\n');out.flush()
            print(json.dumps(row),flush=True);previous=values
        if not sent and time.time()>start+2:
            result=api.api('POST',f'/api/device/{state["parentId"]}/iot-config/releases/{release["id"]}/retry')
            save('release-retry.json',result);sent=True;print('Hub retry requested',flush=True)
        time.sleep(.05)
