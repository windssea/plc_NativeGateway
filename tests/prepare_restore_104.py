import json,time,sys
from pathlib import Path
sys.path.insert(0,r'D:\work\code\PLCnext-iot\src')
from plcnext_iot.contracts import validate_message
root=Path(__file__).resolve().parent
cfg=json.loads((root/'config-50x5.json').read_text());cfg.update(configVersion=104,messageId='soak-50x5-104',timestamp=int(time.time()*1000))
raw=json.dumps(cfg,separators=(',',':')).encode();assert not validate_message('configSet',raw,expected_gateway_id='PLC-ENG-01')
(root/'config-soak-104.json').write_bytes(raw)
print('v104: standard 50 devices / 250 points; hmi-proof stays deleted')
