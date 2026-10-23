"""Verify the PLC-side Hub-managed guard through the existing HMI command path."""
import time,json
import probe_hmi_rsc as sdk
from hub_api import OUT,save
with sdk.Device('192.168.0.8') as device:
    service=sdk.IDataAccessService(device)
    def read(field):return service.ReadSingle('Arp.Plc.Eclr/HMI.'+field).Value.GetValue()
    before={f:read(f) for f in ['GatewayId','ActiveVersion','TotalPoints','ManagementMode']}
    assert before['ManagementMode']=='HUB_MANAGED' and before['GatewayId']=='NG-HUB-2152-01'
    results=[]
    for cmd in ['GW_SaveDevice','GW_SavePoint','GW_RemoveDevice','GW_RemovePoint','GW_Apply']:
        assert int(service.WriteSingle(sdk.WriteItem('Arp.Plc.Eclr/'+cmd,sdk.RscVariant.of(True))))==0
        time.sleep(.2)
        after={f:read(f) for f in before}
        status=read('Status');assert after==before and status.startswith('HUB_MANAGED:'),(cmd,after,status)
        results.append(dict(command=cmd,status=status,unchanged=True))
    save('hmi-hub-guard.json',dict(at=time.time(),before=before,results=results))
    print('PASS: PLC blocked local device, point and Apply commands in Hub mode.')
