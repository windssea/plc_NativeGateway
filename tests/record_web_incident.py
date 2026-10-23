import json,datetime
from pathlib import Path
root=Path(__file__).resolve().parent/'soak'
row={'kind':'hmi-access-interruption','observedStartLocal':'2026-10-23T09:33:19+08:00','recoveredByLocal':'2026-10-23T09:34:50+08:00','observations':['HMI showed busy overlay','Browser reload ERR_CONNECTION_REFUSED','TCP 443 timed out, 80 and 41100 reachable','Navigation via HTTP 80 redirected to HTTPS and HMI recovered','TCP 443 then reachable again'],'plcDataAndResourcesContinuous':True,'plcRebooted':False,'droppedBatches':0,'cause':'not yet established','hmiAvailableAtRecovery':True}
with (root/'incidents.jsonl').open('a',encoding='utf-8') as f:f.write(json.dumps(row,ensure_ascii=False)+'\n')
