import json,time
from pathlib import Path
root=Path(__file__).resolve().parent/'soak';archive=root/'segments'/'20261023-092301-pre-delete';archive.mkdir(parents=True,exist_ok=True)
for name in ['control.json','schedule.json','summary.json']:
 p=root/name
 if p.exists():(archive/name).write_bytes(p.read_bytes())
(archive/'interrupted.json').write_text(json.dumps({'endedAt':time.time(),'status':'interrupted','reason':'User approved HMI point/device deletion verification; restart full 8h after restoring 50x5.','fullEightHoursPassed':False},indent=2))
if (root/'control.json').exists():(root/'control.json').rename(archive/'original-control.json')
print(archive)
