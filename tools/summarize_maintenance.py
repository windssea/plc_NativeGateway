"""Read lab evidence, validate real STORED coverage, optionally verify Hub latest values."""
from pathlib import Path
import argparse
from datetime import datetime
import hashlib
import json
import math
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'tests/mode-maintenance-20261023'
sys.path.insert(0, str(ROOT.parent / 'PLCnext-iot/src'))
sys.path.insert(0, str(ROOT / 'tests'))
from plcnext_iot.contracts import topic_rules, validate_message


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check-hub', action='store_true', help='Read the real Hub API; no writes')
    args = parser.parse_args()
    state = json.loads((OUT / 'state.json').read_text(encoding='utf-8'))
    version = state['appliedRelease']['configVersion']
    baseline = state['config']
    boot = state['verified']['final']['MainInstance.BootId']
    expected = {}
    for device in baseline['devices']:
        u = device['unitId']
        numbers = dict(voltage=230 + u / 10, current=(123 + u) * .1,
                       frequency=(5000 + u) * .01, power=1234 + u, energy=100000 + u)
        for index in range(device['PointStart'] - 1, device['PointStart'] - 1 + device['PointCount']):
            point = baseline['points'][index]
            expected[device['deviceId'], point['pointId']] = numbers[point['name']]
    kinds = {v['suffix']: k for k, v in topic_rules().items()}
    schema = []
    wrong = []
    batches = {}
    acknowledged = set()
    coverage = set()
    deadline = time.monotonic() + 120
    cutoff = state['baseline']['at']
    count = 0
    with (ROOT / 'tests/hub-runtime/wire.jsonl').open(encoding='utf-8') as stream:
        while time.monotonic() < deadline:
            for line in stream:
                event = json.loads(line)
                if event['receivedAt'] < cutoff or not event['topic'].startswith('iot/v1/gateway/NG-HUB-2152-01/') or not event['payload']:
                    continue
                suffix = event['topic'].split('/', 4)[-1]
                payload = json.loads(event['payload'])
                count += 1
                if suffix in kinds:
                    issues = validate_message(kinds[suffix], event['payload'].encode(), expected_gateway_id='NG-HUB-2152-01')
                    if issues:
                        schema.append(dict(suffix=suffix, issues=[str(i) for i in issues]))
                if suffix == 'data' and payload['configVersion'] == version and payload['bootId'] == boot:
                    batches[payload['messageId']] = payload
                    for value in payload['values']:
                        key = value['deviceId'], value['pointId']
                        if value['quality'] == 'GOOD' and (key not in expected or value['value'] is None or
                                not math.isclose(value['value'], expected[key], abs_tol=.0001)):
                            wrong.append(value)
                elif suffix == 'data/ack' and payload['status'] == 'STORED':
                    acknowledged.add(payload['messageId'])
            coverage = {(v['deviceId'], v['pointId']) for mid in batches.keys() & acknowledged
                        for v in batches[mid]['values'] if v['quality'] == 'GOOD'}
            if coverage == set(expected):
                break
            time.sleep(1)
    assert not schema and not wrong and coverage == set(expected), (len(schema), len(wrong), len(coverage))
    hub_summary = None
    if args.check_hub:
        from hub_api import HubApi
        fixture = json.loads((ROOT / 'tests/hub-runtime/fixture.json').read_text(encoding='utf-8'))
        api = HubApi(read_timeout=180).login()
        rows_by_unit = {}
        ages = []
        historical = 0
        started = time.monotonic()
        for unit, child in fixture['children'].items():
            raw = api.api('GET', '/api/device/data/' + child + '/latest')
            rows = [r for r in raw if r['configVersion'] == version]
            historical += len(raw) - len(rows)
            assert len(rows) == 5, (unit, len(rows))
            u = int(unit)
            numbers = dict(voltage=230 + u / 10, current=(123 + u) * .1,
                           frequency=(5000 + u) * .01, power=1234 + u, energy=100000 + u)
            for r in rows:
                assert r['qualityCode'] == 'GOOD' and math.isclose(r['value'], numbers[r['variableName']], abs_tol=.0001), r
                assert r['sourceGatewayId'] == 'NG-HUB-2152-01' and r['sourceMessageId'].startswith('d-' + boot + '-'), r
                age = time.time() - datetime.fromisoformat(r['sampledAt'].replace('Z', '+00:00')).timestamp()
                assert 0 <= age <= 60, (unit, age)
                ages.append(age)
            rows_by_unit[unit] = rows
        (OUT / 'hub-latest-values.json').write_text(json.dumps(rows_by_unit, ensure_ascii=False, indent=2), encoding='utf-8')
        hub_summary = dict(devices=len(rows_by_unit), points=len(ages), version=version, bootId=boot,
                           historicalRowsExcluded=historical, minAgeSeconds=round(min(ages), 2),
                           maxAgeSeconds=round(max(ages), 2), querySeconds=round(time.monotonic() - started, 2), passed=True)
    end = time.time()
    resources = []
    for line in (ROOT / 'tests/hub-runtime/controller-resources.jsonl').open(encoding='utf-8'):
        row = json.loads(line)
        if cutoff <= row['receivedAt'] <= end:
            resources.append(row)
    resource_summary = {}
    for field in ['cpuPercent', 'actualMemoryPercent', 'iecProgramPercent', 'iecDataPercent']:
        values = [r[field] for r in resources if r.get(field) is not None]
        resource_summary[field] = dict(min=min(values), max=max(values), first=values[0], last=values[-1])
    phases = ['baseline', 'enter', 'edit', 'publish-conflict', 'check-reboot', 'replay-conflict',
              'handback', 'retry', 'restore-policy', 'final-ui', 'verify']
    for phase in phases:
        assert json.loads((OUT / (phase + '.json')).read_text(encoding='utf-8'))['passed'], phase
    isolation = json.loads((OUT / 'telemetry-isolation.json').read_text(encoding='utf-8'))
    assert isolation['passed']
    result = dict(software='native-0.5.0', gatewayId='NG-HUB-2152-01',
                  projectSha256=hashlib.sha256((ROOT / 'NativeGateway.pcwex').read_bytes()).hexdigest(),
                  at=end, observationSeconds=round(end - cutoff, 2), phasesPassed=phases,
                  baselineVersion=baseline['Version'], finalVersion=version,
                  pointsRetained=250, maintenanceTelemetryIsolation=isolation,
                  protocolMessagesChecked=count, schemaErrors=len(schema), incorrectValues=len(wrong),
                  realHubStoredBatches=len(batches.keys() & acknowledged), realHubStoredGoodPoints=len(coverage),
                  hubLatest=hub_summary, resources=dict(samples=len(resources), **resource_summary),
                  finalController=state['verified']['final'],
                  finalUi=state['finalUi'],
                  notes=['This is a maintenance/reboot acceptance, not an eight-hour stability pass.',
                         'Hub future-timestamp filtering and database lock delays were observed; evidence retained. PLC clock synchronized through Engineer.',
                         'The optional clear branch was not activated in this non-destructive acceptance.'],
                  passed=True)
    (OUT / 'RESULTS.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
