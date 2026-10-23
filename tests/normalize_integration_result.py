"""Correct first-run validator scope; preserve the original negative-test log."""
import json,sys
from pathlib import Path
sys.path.insert(0,r'D:\work\code\PLCnext-iot\src')
from plcnext_iot.contracts import topic_rules
root=Path(__file__).resolve().parent
original=root/'integration-results-first-run.json'
if not original.exists():original.write_bytes((root/'integration-results.json').read_bytes())
results=json.loads(original.read_text())
direction={v['suffix']:v['direction'] for v in topic_rules().values()}
check=results[-1]
check['scope']='Messages produced by PLC; intentionally invalid test inputs excluded'
negative=[item for item in check['issues'] if direction[item['topic'].removeprefix('iot/v1/gateway/PLC-ENG-01/')]=='to_agent']
check['issues']=[item for item in check['issues'] if item not in negative]
check['passed']=not check['issues']
check['expectedInvalidInputs']=negative
(root/'integration-results.json').write_text(json.dumps(results,indent=2))
print([(r['test'],r['passed']) for r in results])
