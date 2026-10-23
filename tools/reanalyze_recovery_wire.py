"""Recompute derived wire timing, preserving all raw capture evidence."""
from pathlib import Path
import json,threading,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tests'))
p=ROOT/'tests/recovery_suite.py';ns={'__file__':str(p),'__name__':'offline_recovery_analysis'}
exec(p.read_text(encoding='utf-8').split('phase=sys.argv')[0],ns)
out=ROOT/'tests/hmi-recovery-20261023/verified'
for phase in ['blackout','reboot']:
    ns['BASE']=json.loads((out/(phase+'-baseline.json')).read_text(encoding='utf-8'))
    result=json.loads((out/(phase+'-result.json')).read_text(encoding='utf-8'))
    wire=ns['Wire'].__new__(ns['Wire']);wire.lock=threading.Lock();wire.events=[json.loads(l) for l in (out/(phase+'-wire.jsonl')).read_text(encoding='utf-8').splitlines()]
    updated=wire.result(result['startAt']);assert not updated['schemaErrors'] and not updated['incorrectValues'] and updated['goodStoredPointCoverage']==250
    old=result['wire'];result['wire']=updated
    result['analysisNote']='First STORED timing is restricted to message IDs in the captured post-start data batches, excluding unrelated late ACKs.'
    (out/(phase+'-initial-derived-result.json')).write_text(json.dumps(dict(wire=old),ensure_ascii=False,indent=2),encoding='utf-8')
    (out/(phase+'-result.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(phase,dict(firstDataSeconds=updated['firstDataAt']-result['startAt'],firstStoredSeconds=updated['firstStoredAt']-result['startAt'],stored=updated['storedBatches']))
