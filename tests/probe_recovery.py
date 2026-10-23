"""Prove local v6 restore and a consistent live queue after the final download."""
import json,time,sys
import probe_hmi_rsc as sdk
from hub_api import OUT,save
final64='--final64' in sys.argv
before=json.loads((OUT/('before-final64-download.json' if final64 else 'before-final-download.json')).read_text())
release=json.loads((OUT/('release-gateway-64-result.json' if final64 else 'release-capacity-50-result.json')).read_text())
with sdk.Device('192.168.0.8') as device:
    service=sdk.IDataAccessService(device)
    fields=['HMI.GatewayId','HMI.ManagementMode','HMI.ActiveVersion','HMI.DeviceCount','HMI.TotalPoints',
            'HMI.ActiveMessageId','HMI.ReceivedConfigs','HMI.Persistence','HMI.QueueCount','HMI.Dropped',
            'MainInstance.BootId','MainInstance.Durable.BootCounter','MainInstance.Mqtt.SessionCount']
    rows=service.Read(['Arp.Plc.Eclr/'+f for f in fields]);value={f:r.Value.GetValue() for f,r in zip(fields,rows)}
    assert value['MainInstance.BootId']!=before['heartbeat']['payload']['bootId']
    assert value['HMI.ActiveVersion']==str(release['configVersion']) and value['HMI.ActiveMessageId']==release['messageId']
    assert value['HMI.DeviceCount']=='50' and value['HMI.TotalPoints']=='250' and value['HMI.ReceivedConfigs']==0
    rows=service.Read([f'Arp.Plc.Eclr/MainInstance.Outbox[{i}].MessageId' for i in range(1,17)])
    ids=[r.Value.GetValue() for r in rows];assert len([x for x in ids if x])==int(value['HMI.QueueCount'])
    save('recovery-proof-final64.json' if final64 else 'recovery-proof.json',dict(at=time.time(),values=value,outboxMessageIds=ids,localRestoreWithoutNewConfig=True))
    print('PASS: persisted version',release['configVersion'],'restored 50/250 without new config; boot changed; queue count consistent.',flush=True)
