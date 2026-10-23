import json,time,sys
from pathlib import Path
root=Path(__file__).resolve().parent;version=int(sys.argv[1]);expected=json.loads((root/('expected-50x5.json' if version==104 else 'expected-soak-101.json')).read_text())
if version==102:expected.pop('hmi-proof/point-1')
if version==103:expected={k:v for k,v in expected.items() if not k.startswith('hmi-proof/')}
good={};unexpected=set();wrong=[]
for path in sorted((root/'soak').glob('wire-*.jsonl')):
 for line in path.open(encoding='utf-8'):
  row=json.loads(line)
  if not row['topic'].endswith('/data'):continue
  p=json.loads(row['payload'])
  if p.get('configVersion')!=version:continue
  for v in p['values']:
   key=v['deviceId']+'/'+v['pointId']
   if key not in expected:unexpected.add(key)
   elif v['quality']=='GOOD':
    if abs(v['value']-expected[key]['value'])<=expected[key]['tolerance']:good[key]=v
    else:wrong.append(v)
result={'configVersion':version,'expected':len(expected),'goodPoints':len(good),'unexpectedPoints':sorted(unexpected),'wrongValues':wrong,'passed':set(good)==set(expected) and not unexpected and not wrong}
(root/f'deleted-pointset-v{version}.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));assert result['passed'],result
