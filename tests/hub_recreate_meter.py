"""Stage the replacement test draft while PLC telemetry is stopped and drained."""
import json,time,sys,subprocess
from hub_api import HubApi,OUT,save
def run(*args):subprocess.run([sys.executable,*args],check=True)
run('tests/plc_maintenance_control.py','stop')
try:
    api=HubApi().login();deadline=time.time()+90
    while True:
        d=api.api('GET','/api/device/iot-diagnostics')
        if all(d['queues'][k]['depth']==0 and d['queues'][k]['active']==0 for k in ['DATA','CONTROL','STATE']):break
        if time.time()>deadline:raise AssertionError('Hub lanes did not drain; do not overlap configuration preparation')
        time.sleep(1)
    save('diagnostics-before-recreate.json',d)
    run('tests/hub_fixture.py','50')
finally:
    run('tests/plc_maintenance_control.py','warm-start')
print('Replacement Unit 2 prepared; warm restore started.',flush=True)
