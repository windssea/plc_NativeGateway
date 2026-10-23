"""Explicit maintenance stop/start of this task's NativeGateway test controller."""
import sys,time
import probe_hmi_rsc as sdk
from PyPlcnextRsc.Arp.Plc.Domain.Services import IPlcManagerService,PlcStartKind,IPlcInfoService,PlcInfoId
from hub_api import OUT,save
operation=sys.argv[1]
assert operation in ['stop','warm-start']
with sdk.Device('192.168.0.8') as device:
    gds=sdk.IDataAccessService(device)
    identity=gds.ReadSingle('Arp.Plc.Eclr/HMI.GatewayId').Value.GetValue()
    assert identity=='NG-HUB-2152-01',identity
    manager=IPlcManagerService(device);before=str(manager.GetPlcState())
    if operation=='stop':manager.Stop(False)
    else:manager.Start(PlcStartKind.Warm,False)
    after=str(manager.GetPlcState())
    save('maintenance-'+operation+'.json',dict(at=time.time(),controller='192.168.0.8',gateway=identity,before=before,after=after))
    print(operation,before,'=>',after)
