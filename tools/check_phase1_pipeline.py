"""Offline source/archive/evidence gates for P03/P04. No device/DB access."""
import ast
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import zipfile
from build_phase1_pipeline_test import KEEP

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'tests/validation/p03-p04'
sha=lambda data:hashlib.sha256(data).hexdigest()
read=lambda name:json.loads((OUT/name).read_text(encoding='utf-8-sig'))

def parts(source):
    match=re.match(r'(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s+(\w+)(?:\s*:\s*([^\n]+))?\s*\n',source)
    rest=source[match.end():]
    end=list(re.finditer(r'\bEND_VAR\b',rest))[-1].end()
    return rest[:end],re.sub(r'\s*END_(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s*$','',rest[end:]).strip()+'\n'

def main(archived=False):
    canonical=ROOT/'docs/阶段0-三方接口与验收定稿.md'
    assert sha(canonical.read_bytes())=='7d7425b4ebe2e17cbc9fb283a59bd0f59be1ba48d24dda078977dde9d421b91f'
    full=ROOT/'tmp/p03-p04/NativeGateway.p03-p04-final-v7.pcwex'
    archive=full if archived else ROOT/'NativeGateway.pcwex'
    harness=ROOT/'tmp/p03-p04/NativeGateway.p03-p04-test-v7.pcwex'
    assert archive.read_bytes()==full.read_bytes()
    hashes={}
    with zipfile.ZipFile(archive) as z,zipfile.ZipFile(harness) as test:
        for path in sorted((ROOT/'src').glob('*')):
            if path.suffix=='.dt':
                name='PROJECT/Logical%20Elements/'+path.name
                if not archived: assert z.read(name)==path.read_bytes(),path.name
                if path.name=='NG_CaptureTypes.dt': assert test.read(name)==z.read(name)
            elif path.suffix=='.st':
                prefix='PROJECT/Logical%20Elements/'+path.stem+'.pou/'
                if archived and prefix+'Code.st' not in z.namelist(): continue
                if archived:
                    variables=z.read(prefix+'Variables.var').decode()
                    code=z.read(prefix+'Code.st').decode()
                else: variables,code=parts(path.read_text(encoding='utf-8-sig'))
                for name,content in [('Variables.var',variables),('Code.st',code)]:
                    assert z.read(prefix+name).decode()==content,(path.name,name)
                    if path.stem in KEEP-{'Main'}: assert test.read(prefix+name)==z.read(prefix+name)
            if not archived: hashes[str(path.relative_to(ROOT))]=sha(path.read_bytes())
        fixture=ROOT/'tests/phase1_pipeline_test.st'
        if not archived:
            for name,content in zip(['Variables.var','Code.st'],parts(fixture.read_text(encoding='utf-8'))):
                assert test.read('PROJECT/Logical%20Elements/Main.pou/'+name).decode()==content
        project=test.read('PROJECT/PROJECT.proj').decode()
        assert not re.search(r'Logical Elements\\(?:NG_Mqtt|NG_Store|NG_Modbus)\.pou',project)
        if not archived: hashes[str(fixture.relative_to(ROOT))]=sha(fixture.read_bytes())
    old_types=subprocess.check_output(['git','show','HEAD:src/NG_Types.dt'],cwd=ROOT)
    assert old_types.replace(b'\r\n',b'\n')==(ROOT/'src/NG_Types.dt').read_bytes().replace(b'\r\n',b'\n')
    assertions=read('plc-final-test-result.json')
    assert assertions['Done'] and assertions['Passed']==41 and assertions['FailedChecks']==0
    assert all(assertions[f'Checks[{i}]'] for i in range(1,42))
    assert assertions['longPayloadHashMatches'] and assertions['longPayloadValueCount']==64
    assert assertions['longPayloadBytes']==15244 and len(assertions['LongPayload'].encode())==15244
    assert sha(assertions['LongPayload'].encode())==assertions['LongDigest']
    assert assertions['BudgetBytes']==4106893 and assertions['BufferBytes']==2993192
    assert assertions['RecordBytes']==72 and assertions['BudgetBytes']<4194304
    layout=read('compiled-layout-bounds.json')
    assert layout['valueSizes']['NG_Buffer']==assertions['BufferBytes']
    assert layout['captureHelperUpperBound']==45376<65536
    assert layout['mqttStateUpperBound']==9432<16384
    profile=json.loads((ROOT.parent/'PLCnext-Hub-Backend/tools/phase1/resource-profile.json').read_text())
    assert profile['plc']['maxRecords']==28800 and 28800>=profile['minimumRecordCapacity']
    assert profile['plc']['p03Measured']['accountedSubsystemBytes']==assertions['BudgetBytes']
    assert profile['minimumConfirmedLocalReleaseEventsPerSecond']==90
    assert not profile['plc']['p03Measured']['requiredReleaseRatePassed']
    candidate=read('plc-candidate-drained.json')
    assert candidate['pausedForRestore'] and not candidate['Active.enabled']
    assert candidate['CaptureBuffer.CapturedEventsTotal']==candidate['CaptureBuffer.EligibleEventsTotal']==candidate['CaptureBuffer.StoredConfirmedEventsTotal']==2500
    for field in ['OwnedCount','IngressCount','CaptureOverflowEventsTotal','UndecidedLostEventsTotal',
                  'KnownUnsentEventsTotal','TimeInvalidEventsTotal','IsolatedEventsTotal','UncertainDeliveryEventsTotal',
                  'MissedPollCyclesTotal','MissedReportSlotsTotal','EnqueueRejectedAttemptsTotal','GapRecordsTotal']:
        assert candidate['CaptureBuffer.'+field]==0,field
    assert candidate['QueueCount']==0 and not candidate['CaptureBuffer.CaptureStopped'] and not candidate['CaptureBuffer.CounterOverflow']
    wire=read('native-real-wire.json')
    assert not wire['truncated']
    batches={};acknowledgements={}
    for row in wire['rows']:
        assert sha(row['payload'].encode())==row['sha256'] and not row['retained']
        body=json.loads(row['payload'])
        if row['topic'].endswith('/data'):
            key=body['messageId']
            if key in batches: assert batches[key]==row['payload']
            batches[key]=row['payload']
            values=body['values']
            assert 1<=len(values)<=64 and len(row['payload'].encode())<=16380
            assert len({(v['deviceId'],v['pointId']) for v in values})==len(values)
            assert body['bootId']==candidate['BootId'] and body['configVersion']==13
        else:
            acknowledgements[body['messageId']]=body
    assert len(batches)==len(acknowledgements)==40
    assert all(acknowledgements[key]['status']=='STORED' for key in batches)
    assert sum(len(json.loads(payload)['values']) for payload in batches.values())==2500
    before=read('plc-before.json'); after=read('plc-restored-ready.json')
    assert before['samplingConfigSha256']==after['samplingConfigSha256']
    assert after['Active.enabled'] and after['Active.Version']==13 and after['Active.PointCount']==250
    assert after['HMI.Connection']=='CONNECTED' and after['HMI.ConfirmedBatches']>0 and after['HMI.InvalidAcks']==0
    restored=read('restored-real-stored-ack.json')
    restored_ack=json.loads(restored['payload'])
    assert not restored['retained'] and restored_ack['status']=='STORED'
    assert restored_ack['messageId'].startswith('d-'+after['BootId']+'-') and sha(restored['payload'].encode())==restored['sha256']
    environment=read('environment.json')
    assert environment['backendInstanceCount']==1 and environment['backendPid']==[34208]
    assert environment['frontendPid']==[4088] and environment['resourceRecorderCount']==0
    assert environment['backendJarSha256']=='34f1a01e324f1911e0cb2527e96130eefc7bed67a5ac13a31d6b626fefd25cd1'
    contracts={}
    for name in ['protocol.schema.json','topics.json']:
        backend=ROOT.parent/'PLCnext-Hub-Backend/hub-device/src/main/resources/iot/contracts/v1'/name
        iot=ROOT.parent/'PLCnext-iot/contracts/v1'/name
        assert backend.read_bytes()==iot.read_bytes()
        contracts[name]=sha(backend.read_bytes())
    assert contracts=={'protocol.schema.json':'d65c133d44a02072972361a4c601ca3b22bf0ab1125f6d63d48ca47b65a830e9',
                      'topics.json':'f80f367dd34def81ba86a0a2eb370869bf99de1f25ceadfc986ca004da308d51'}
    documents=[ROOT/'README.md',ROOT/'tests/README.md',ROOT/'docs/阶段1-P03-P04实现与验证-20261024.md',
        ROOT/'docs/阶段1-三方实施任务与顺序.md',ROOT/'docs/Hub-IoT-PLC协同实施计划.md',ROOT/'docs/后台服务检查-2026-10-24.md',
        ROOT.parent/'PLCnext-Hub-Backend/docs/architecture/hub-iot-phase0.md',ROOT.parent/'PLCnext-iot/doc/三方阶段0接口定稿.md']
    links=0
    for path in documents:
        text=path.read_text(encoding='utf-8-sig')
        assert text.count('```')%2==0,path
        for target in re.findall(r'(?<!!)\[[^\]]*\]\(([^)]+)\)',text):
            if '://' in target or target.startswith('#'):continue
            assert (path.parent/target.split('#')[0]).exists(),(path,target)
            links+=1
    for path in [ROOT/'tools'/name for name in ['build_phase1_pipeline_test.py','build_phase1_capture_test.py',
            'phase1_plc_probe.py','phase1_pipeline_plc_probe.py','phase1_wire_observer.py','check_phase1_pipeline.py']]:
        ast.parse(path.read_text(encoding='utf-8-sig')); hashes[str(path.relative_to(ROOT))]=sha(path.read_bytes())
    result=dict(evidenceLevel='OFFLINE_SOURCE_AND_ARCHIVED_EVIDENCE_GATES',canonicalSha256=sha(canonical.read_bytes()),
        sourceHashes=hashes,archives={path.name:sha(path.read_bytes()) for path in [archive,full,harness]},
        archivedEvidenceOnly=archived,rootArchiveMatchesCompiledInput=not archived,testHelpersMatchProduction=True,persistentTypesUnchanged=True,
        sharedContracts=contracts,plcAssertions=41,realDataBatches=40,realStoredValues=2500,
        restoredBoot=after['BootId'],documentsChecked=len(documents),localLinksChecked=links,
        noP06PerformanceReleaseClaim=True)
    (OUT/('archived-evidence-check.json' if archived else 'static-source-check.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({key:value for key,value in result.items() if key not in ['sourceHashes','archives']},ensure_ascii=False))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archived',action='store_true',help='Verify P03/P04 archived input and evidence after newer source development')
    main(parser.parse_args().archived)
