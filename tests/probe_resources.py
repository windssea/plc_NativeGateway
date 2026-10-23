import sys,enum
# Local compatibility adapter for the vendor's Python 3.9 client on Python 3.12.
if not hasattr(enum,'_decompose'):
    def decompose(cls,value):
        members=[m for m in cls if m.value and m.value & value == m.value]
        remaining=value
        for m in members:remaining &= ~m.value
        return members,remaining
    enum._decompose=decompose
sys.path.insert(0,r'D:\work\code\JPlcnextRsc')
from PyPlcnextRsc import Device
from PyPlcnextRsc.Arp.Device.Interface.Services import IDeviceStatusService
with Device('192.168.0.8') as d:
    s=IDeviceStatusService(d)
    print(s)
    print(s.GetItems(['Status.Cpu.0.Load.Percent','Status.Memory.Usage.Percent','Status.ProgramMemoryIEC.Usage.Percent','Status.DataMemoryIEC.Usage.Percent']))
