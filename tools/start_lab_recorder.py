"""Launch the read-only lab MQTT recorder outside the terminal job on Windows."""
from pathlib import Path
import json
import os
import subprocess
import sys
import time

root=Path(__file__).resolve().parents[1]
out=root/'tests/hub-runtime'
old=out/'observer.json'
if old.exists():
    pid=json.loads(old.read_text(encoding='utf-8')).get('pid')
    rows=subprocess.run(['tasklist','/FI',f'PID eq {pid}','/NH','/FO','CSV'],capture_output=True,text=True).stdout
    if rows.lower().startswith('"python.exe"'):
        raise SystemExit('Recorder PID is already running; inspect it instead of launching a duplicate.')
env=os.environ.copy()
env['PYTHONPATH']=str(root/'tests/.venv/Lib/site-packages')
# The venv redirector spawns a second interpreter. Launch the base interpreter
# directly so a terminal cancellation does not leave only a stale wrapper PID.
executable=getattr(sys,'_base_executable',sys.executable)
with (out/'observer-process.log').open('ab') as log:
    p=subprocess.Popen([executable,'-u',str(root/'tests/hub_wire_observer.py')],cwd=root,env=env,
        stdout=log,stderr=subprocess.STDOUT,
        creationflags=subprocess.CREATE_NO_WINDOW|subprocess.CREATE_BREAKAWAY_FROM_JOB)
(out/'observer-launch.json').write_text(json.dumps(dict(pid=p.pid,startedAt=time.time(),readOnly=True),indent=2)+'\n')
print('Started read-only recorder PID',p.pid)
