"""Read-only compatibility audit against the Hub's current Java contract validator.

Reads source/jars and saved wire records. Does not use MQTT, database, RSC or PLC APIs.
Compilation and extracted dependencies stay under this workspace's tmp directory.
"""
from pathlib import Path
from collections import Counter
from datetime import datetime
from copy import deepcopy
import hashlib
import json
import os
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HUB = ROOT.parent / 'PLCnext-Hub-Backend'
IOT = ROOT.parent / 'PLCnext-iot'
WORK = ROOT / 'tmp/hub-compatibility'
RESULTS = ROOT / 'tests/hub-compatibility'
for directory in (WORK / 'lib', WORK / 'classes', RESULTS):
    directory.mkdir(parents=True, exist_ok=True)


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    contracts = HUB / 'hub-device/src/main/java/com/phoenix/plcnext/hub/device/iot/contract'
    resources = HUB / 'hub-device/src/main/resources'
    jdk = Path.home() / '.jdks/ms-21.0.12.1/bin'
    jar = HUB / 'hub-admin/target/hub-admin-1.0.0-SNAPSHOT.jar'
    prefixes = ('jackson-', 'json-schema-validator-', 'itu-', 'slf4j-api-', 'snakeyaml-', 'commons-lang3-')
    with zipfile.ZipFile(jar) as archive:
        for entry in archive.infolist():
            name = Path(entry.filename).name
            if entry.filename.startswith('BOOT-INF/lib/') and name.endswith('.jar') and name.startswith(prefixes):
                target = WORK / 'lib' / name
                if not target.exists() or target.stat().st_size != entry.file_size:
                    target.write_bytes(archive.read(entry))
    harness = WORK / 'HubContractAudit.java'
    harness.write_text('''import java.nio.file.*;
import com.fasterxml.jackson.databind.*;
import com.phoenix.plcnext.hub.device.iot.contract.*;
public class HubContractAudit {
 public static void main(String[] args) throws Exception {
  var mapper = new ObjectMapper(); var validator = new DefaultIoTContractValidator();
  var results = mapper.createArrayNode();
  for(var c: mapper.readTree(Files.readAllBytes(Path.of(args[0])))) {
   var v = validator.validate(MessageKind.fromWireName(c.path("kind").asText()),
       c.path("payload").asText().getBytes(java.nio.charset.StandardCharsets.UTF_8), c.path("gatewayId").asText());
   var r = results.addObject();r.put("id",c.path("id").asText()).put("valid",v.valid());
   r.set("issues",mapper.valueToTree(v.issues()));
  }
  Files.writeString(Path.of(args[1]), mapper.writerWithDefaultPrettyPrinter().writeValueAsString(results));
 }
}
''', encoding='utf-8')
    classpath = str(WORK / 'lib/*')
    source_names = ['MessageKind', 'IoTIssue', 'IoTValidation', 'IoTContractValidator',
                    'IoTSemanticValidator', 'DefaultIoTContractValidator']
    subprocess.run([str(jdk / 'javac.exe'), '-encoding', 'UTF-8', '-cp', classpath, '-d', str(WORK / 'classes'),
                    *[str(contracts / (name+'.java')) for name in source_names], str(harness)], check=True)
    cases = []
    manifest = read(ROOT / 'docs/examples/manifest.json')
    for filename, kind in manifest.items():
        cases.append(dict(id='doc/'+filename, kind=kind, gatewayId='PLC-DEMO-01',
                          payload=(ROOT / 'docs/examples' / filename).read_text(encoding='utf-8')))
    control = read(ROOT / 'tests/soak/control.json')
    start = control['startAt']
    kinds = {'heartbeat':'heartbeat', 'data':'data', 'config/ack':'configAck', 'config/patch/ack':'configPatchAck',
             'config/get':'configGet', 'status':'status', 'data/ack':'dataAck', 'config/set':'configSet', 'config/patch':'configPatch'}
    counts, latest, parse_errors = Counter(), {}, 0
    for path in sorted((ROOT / 'tests/soak').glob('wire-*.jsonl')):
        # An actively written final line may be incomplete. Never modify the recorder's file.
        with path.open(encoding='utf-8') as stream:
            for line in stream:
                try:
                    value = json.loads(line)
                    if value['receivedAt'] < start:
                        continue
                    suffix = value['topic'].split('/',4)[-1]
                    if suffix in kinds:
                        counts[suffix] += 1
                        latest[suffix] = value
                except (ValueError, KeyError):
                    parse_errors += 1
    for suffix, record in latest.items():
        cases.append(dict(id='wire/latest/'+suffix, kind=kinds[suffix], gatewayId='PLC-ENG-01', payload=record['payload']))
    ack = read(ROOT / 'docs/examples/config-ack-demo.json')
    patch_ack = read(ROOT / 'docs/examples/config-patch-ack-demo.json')
    for kind, source, code, proposed in [('configAck', ack, 'BAD_CONFIGURATION', 'APPLY_FAILED'),
                                         ('configPatchAck', patch_ack, 'BAD_CONFIGURATION', 'APPLY_FAILED'),
                                         ('configPatchAck', patch_ack, 'RETAINED_PATCH', 'OPERATION_CONFLICT')]:
        value = deepcopy(source)
        value.update(status='REJECTED', errors=[dict(code=code, path='/', message='Configuration rejected; inspect HMI diagnostics.')])
        if kind == 'configPatchAck':
            value['appliedConfigVersion'] = None
        cases.append(dict(id='negative/current/'+kind+'/'+code, kind=kind, gatewayId='PLC-DEMO-01', payload=json.dumps(value)))
        value['errors'][0]['code'] = proposed
        cases.append(dict(id='candidate/mapped/'+kind+'/'+code, kind=kind, gatewayId='PLC-DEMO-01', payload=json.dumps(value)))
    input_path, output_path = WORK / 'cases.json', WORK / 'java-results.json'
    input_path.write_text(json.dumps(cases), encoding='utf-8')
    runtime_cp = os.pathsep.join([str(WORK/'classes'), classpath, str(resources)])
    subprocess.run([str(jdk/'java.exe'), '-cp', runtime_cp, 'HubContractAudit', str(input_path), str(output_path)], check=True)
    result_cases = read(output_path)
    expectations = []
    for case in result_cases:
        expected = not case['id'].startswith('negative/current/')
        expectations.append(case['valid'] == expected)
    schema_a = IOT / 'contracts/v1/protocol.schema.json'
    schema_b = resources / 'iot/contracts/v1/protocol.schema.json'
    topics_a, topics_b = IOT/'contracts/v1/topics.json', resources/'iot/contracts/v1/topics.json'
    heartbeat = latest.get('heartbeat')
    heartbeat_payload = json.loads(heartbeat['payload']) if heartbeat else None
    current_summary = read(ROOT/'tests/soak/summary.json')
    # These checks document source-derived blockers; they are not database integration tests.
    result = dict(checkedAt=datetime.now().astimezone().isoformat(timespec='seconds'), mode='offline-read-only',
                  validator='Current Hub Java DefaultIoTContractValidator + IoTSemanticValidator, compiled from source',
                  schemas=dict(iot=sha(schema_a), hub=sha(schema_b), equal=sha(schema_a)==sha(schema_b)),
                  topics=dict(iot=sha(topics_a), hub=sha(topics_b), equal=sha(topics_a)==sha(topics_b)),
                  sourceHashes={name+'.java':sha(contracts/(name+'.java')) for name in source_names},
                  activeWindow=dict(startAt=start, configVersion=control['configVersion'], recordsByTopic=dict(counts),
                                    skippedMalformedOrPartialLines=parse_errors),
                  cases=result_cases, expectationsPassed=all(expectations),
                  sourceDerivedBlockers=dict(
                      heartbeatAheadOfRecorderSeconds=(heartbeat_payload['timestamp']/1000-heartbeat['receivedAt']) if heartbeat else None,
                      heartbeatRejectedByHubIfHubClockEqualsRecorder=bool(heartbeat and heartbeat_payload['timestamp']/1000>heartbeat['receivedAt']),
                      hubControlFreshnessSeconds=90, hubAllowsFutureControlTimestamp=False,
                      locallyIssuedVersion=current_summary['heartbeat']['activeConfigVersion'],
                      locallyIssuedMessageId=json.loads(latest['config/get']['payload']).get('activeMessageId') if 'config/get' in latest else None,
                      unknownReleaseCausesTelemetry='RETRY without STORED ACK',
                      nativeDataIdContainsGatewayId=False,
                      collisionExample=dict(gatewayA='GW-A', gatewayB='GW-B',
                           bootTimeMs=1792718607000, generation=14, sequence=1,
                           identicalMessageId='data-eng-1792718607000-14-1'),
                      note='Timestamp/history/identity observations follow inspected Hub source; no DB or live Hub acceptance was exercised.'),
                  plcStateUnchanged=True,
                  limitations=['Representative latest wire payload per topic checked, not every raw packet by Java.',
                               'Negative cases reconstruct current ST ACK envelopes; they were not injected into the PLC.',
                               'No live Hub registration, database write, broker publish or PLC download.'])
    target = RESULTS / 'audit.json'
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'file':str(target), 'cases':len(result_cases), 'expectationsPassed':result['expectationsPassed'],
                      'schemaEqual':result['schemas']['equal'], 'observedRecords':dict(counts),
                      'controlTimestampAheadSeconds':result['sourceDerivedBlockers']['heartbeatAheadOfRecorderSeconds'],
                      'failingCurrentCases':[c['id'] for c in result_cases if not c['valid']]}, ensure_ascii=False))
    raise SystemExit(0 if all(expectations) else 1)


if __name__ == '__main__':
    main()
