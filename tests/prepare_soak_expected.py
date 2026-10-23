import json
from pathlib import Path
root=Path(__file__).resolve().parent
expected=json.loads((root/'expected-50x5.json').read_text())
for point in ['voltage','current','frequency','power','energy']:
 expected['hmi-proof/'+('point-1' if point=='voltage' else point)]=expected.pop('soak-meter-050/'+point)
(root/'expected-soak-101.json').write_text(json.dumps(expected,indent=2))
assert len(expected)==250
print('Expected 250 points: soak-meter-001..049, hmi-proof (Unit 50)')
