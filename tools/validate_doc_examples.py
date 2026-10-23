"""Offline fixture/schema validation. No network I/O, no PLC changes."""
from pathlib import Path
from dataclasses import asdict
import sys
import json
from datetime import datetime

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root.parent / 'PLCnext-iot/src'))
from plcnext_iot.contracts import validate_message

directory = root / 'docs/examples'
manifest = json.loads((directory / 'manifest.json').read_text(encoding='utf-8'))
results = {}
for filename, kind in manifest.items():
    issues = validate_message(kind, (directory / filename).read_bytes(), expected_gateway_id='PLC-DEMO-01')
    results[filename] = {'kind': kind, 'passed': not issues, 'issues': [asdict(i) for i in issues]}

full = json.loads((directory / 'config-set-demo.json').read_text(encoding='utf-8'))
devices = {d['deviceId']: d for d in full['config']['devices']}
version, message = full['configVersion'], full['messageId']
chain = []
for suffix in ['add', 'replace', 'remove', 'remove-point', 'gateway']:
    value = json.loads((directory / ('config-patch-' + suffix + '-demo.json')).read_text(encoding='utf-8'))
    assert value['baseConfigVersion'] == version and value['baseMessageId'] == message
    for op in value['operations']:
        key = op['deviceId']
        if op['op'] == 'add':
            assert key not in devices
            devices[key] = op['device']
        elif op['op'] == 'replace':
            assert key in devices
            devices[key] = op['device']
        else:
            assert key in devices and 'device' not in op
            del devices[key]
    version, message = value['configVersion'], value['messageId']
    chain.append({'version': version, 'devices': len(devices), 'points': sum(len(d['points']) for d in devices.values())})
assert version == 6 and list(devices) == ['meter-01']
assert [p['pointId'] for p in devices['meter-01']['points']] == ['voltage']
result = {'checkedAt': datetime.now().isoformat(timespec='seconds'), 'mode': 'offline-only',
          'passed': all(r['passed'] for r in results.values()), 'results': results, 'versionChain': chain,
          'note': 'Schema/semantic fixtures and version-chain checks; not a PLC integration test.'}
(directory / 'validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
raise SystemExit(0 if result['passed'] else 1)
