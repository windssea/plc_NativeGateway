"""Condense the real UTC/NTP acceptance evidence; does not contact the controller."""
from pathlib import Path
import hashlib
import json
import re

root = Path(__file__).resolve().parents[1]
raw = root/'tests/time-locking-20261023'
def read(name): return json.loads((raw/name).read_text(encoding='utf-8'))
monitor = read('plc-monitor-results.json')
reboot = read('reboot.json')
ntp = read('plc-ntp-recovery.json')
restart = next(x['at'] for x in ntp if x.get('event') == 'container-restart')
after = [x for x in ntp if x['at'] > restart and 'clients' in x]
def requests(row):
    return sum(int(m.group(1)) for m in re.finditer(r'^\S+\s+(\d+)\s+\d+\s+\S+\s+\S+\s+\S+\s+\d+', row['clients'], re.M))
counts = [dict(at=x['at'], requests=requests(x)) for x in after]
assert counts and counts[-1]['requests'] >= 2, 'No repeated NTP requests after server restart'
assert monitor['plcPassed'] and reboot['passed']
result = dict(date='2026-10-23', plc='192.168.0.8', gatewayId='NG-HUB-2152-01',
    application='native-0.5.0', applicationRebuiltThisRound=False,
    engineerProjectSha256=hashlib.sha256((root/'NativeGateway.pcwex').read_bytes()).hexdigest(),
    timeConfiguration=dict(server='192.168.0.5', udpPort=123, pollSeconds=64, timezone='UTC+00:00',
        utcOffsetMinutes=0, container='nativegateway-ntp', source='common Hub-host clock; not independently traceable UTC'),
    controllerReboot=reboot, handback=read('handback.json'),
    ntpRecovery=dict(passed=True, restartedAt=restart, postRestartRequests=counts, raw=ntp),
    continuousObservation=monitor,
    hubStatus='Issues handed over; no claim of Hub stability. Experimental source and runtime retained; no Hub commit or push.',
    fullEightHourTestPassed=False,
    rawEvidence='tests/time-locking-20261023 (local workstation only)')
out=root/'tests/validation/continuous-time-20261023.json'
out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(passed=True,seconds=monitor['actualSeconds'],points=monitor['points'],
    clockRange=[monitor['clockMinOffsetSeconds'],monitor['clockMaxOffsetSeconds']],
    ntpRequestsAfterRestart=counts[-1]['requests'],cpu=monitor['cpuRange'],memory=monitor['actualMemoryRange']),ensure_ascii=True))
