"""Use the vendor's published GDS service for explicit HMI-tag maintenance."""
import sys,enum,json
_enum_setitem=enum._EnumDict.__setitem__
def _legacy_enum_member(self,key,value):
    if key=='_create_pseudo_member_':dict.__setitem__(self,key,value)
    else:_enum_setitem(self,key,value)
enum._EnumDict.__setitem__=_legacy_enum_member
if not hasattr(enum,'_decompose'):
    def decompose(cls,value):
        members=[m for m in cls if m.value and m.value & value == m.value]
        remaining=value
        for m in members:remaining &= ~m.value
        return members,remaining
    enum._decompose=decompose
sys.path.insert(0,r'D:\work\code\JPlcnextRsc')
from PyPlcnextRsc import Device
from PyPlcnextRsc.Arp.Plc.Gds.Services import IDataAccessService,WriteItem
from PyPlcnextRsc.common.serviceDefinition.all_needed import RscVariant
with Device('192.168.0.8') as device:
    service=IDataAccessService(device)
    if '--enroll-hub' in sys.argv:
        current=service.ReadSingle('Arp.Plc.Eclr/HMI.GatewayId')
        assert 'PLC-ENG-01' in str(current) or 'NG-HUB-2152-01' in str(current), 'Unexpected gateway identity'
        # Continuous NTP uses real UTC. The earlier manual local-wall-clock
        # fixture used 480 and must not be reapplied after UTC migration.
        for field,value in [('BrokerGatewayId','NG-HUB-2152-01'),('ManagementMode','HUB_MANAGED'),('UtcOffsetMinutes','0'),('ClientId','NG-HUB-2152-01-native')]:
            result=service.WriteSingle(WriteItem('Arp.Plc.Eclr/HMI.'+field,RscVariant.of(value)))
            assert int(result)==0,(field,str(result))
        result=service.WriteSingle(WriteItem('Arp.Plc.Eclr/GW_SaveBroker',RscVariant.of(True)))
        assert int(result)==0,str(result)
        print('Hub enrollment submitted via existing HMI transaction path.')
    names=['Arp.Plc.Eclr/HMI.'+f for f in ['Status','Connection','ConfigResult','Persistence','UtcOffsetMinutes','ResourceStatus','ManagementMode','GatewayId','ActiveVersion','QueueCount','ProtocolStatus','ReceivedConfigs','PublishedBatches','ConfirmedBatches','InvalidAcks']]
    names += [arg for arg in sys.argv[1:] if arg.startswith('Arp.Plc.Eclr/')]
    for name in names:
        value=service.ReadSingle(name)
        print(name,repr(value))
