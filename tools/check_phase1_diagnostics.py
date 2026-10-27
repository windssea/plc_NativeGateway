"""Offline packaging, host tests and archived P05/P06 evidence consistency.

Never connects to a device/DB or executes IEC. Native/DB results are separately
recorded observations; a performance failure must stay a failure here.
"""
import ast
import hashlib
import io
import json
from pathlib import Path
import re
import sys
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from test_phase1_audit_export import ExportTests


def main():
    out=ROOT/'tests/validation/p05-p06'
    log=io.StringIO()
    result=unittest.TextTestRunner(stream=log,verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ExportTests))
    (out/'host-exporter-tests.txt').write_text(log.getvalue(),encoding='utf-8')
    assert result.wasSuccessful(),log.getvalue()
    hashes={}
    with zipfile.ZipFile(ROOT/'NativeGateway.pcwex') as z:
        for p in sorted((ROOT/'src').glob('*')):
            hashes[p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
            prefix='PROJECT/Logical%20Elements/'
            if p.suffix=='.dt':assert z.read(prefix+p.name)==p.read_bytes()
            elif p.suffix=='.st':
                source=p.read_text(encoding='utf-8-sig')
                match=re.match(r'(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s+\w+(?:\s*:\s*[^\n]+)?\s*\n',source)
                rest=source[match.end():]
                end=list(re.finditer(r'\bEND_VAR\b',rest))[-1].end()
                assert z.read(prefix+p.stem+'.pou/Variables.var').decode()==rest[:end]
                code=re.sub(r'\s*END_(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s*$','',rest[end:]).strip()+'\n'
                assert z.read(prefix+p.stem+'.pou/Code.st').decode()==code
    packages={}
    compiled=json.loads((out/'compiled-inputs.json').read_text(encoding='utf-8'))
    for name in ['NativeGateway.p05-diagnostics-test-v2.pcwex','NativeGateway.p06-parallel-test-v4.pcwex']:
        p=ROOT/'tmp/p05-p06'/name
        with zipfile.ZipFile(p) as z:
            project=z.read('PROJECT/PROJECT.proj').decode()
            assert not re.search(r'Logical Elements\\(?:NG_Mqtt|NG_Store|NG_Modbus)\.pou',project)
        packages[name]=hashlib.sha256(p.read_bytes()).hexdigest()
        assert packages[name]==compiled['archives'][name]['sha256']
    for name in ['NativeGateway.p05-p06-full-v4.pcwex','NativeGateway.p06-performance-v4.pcwex']:
        p=ROOT/'tmp/p05-p06'/name
        packages[name]=hashlib.sha256(p.read_bytes()).hexdigest()
        assert packages[name]==compiled['archives'][name]['sha256']
        assert compiled['archives'][name]['errors']==compiled['archives'][name]['warnings']==0
    assert hashlib.sha256((ROOT/'NativeGateway.pcwex').read_bytes()).hexdigest()==packages['NativeGateway.p05-p06-full-v4.pcwex']
    for p in list((ROOT/'tools').glob('*phase1*.py'))+[ROOT/'tests/test_phase1_audit_export.py']:
        ast.parse(p.read_text(encoding='utf-8-sig'))
    canonical=ROOT/'docs/阶段0-三方接口与验收定稿.md'
    assert hashlib.sha256(canonical.read_bytes()).hexdigest()=='7d7425b4ebe2e17cbc9fb283a59bd0f59be1ba48d24dda078977dde9d421b91f'
    profile=json.loads((ROOT.parent/'PLCnext-Hub-Backend/tools/phase1/resource-profile.json').read_text())
    assert profile['plc']['maxRecords']==28800 and profile['plc']['subsystemRamBytes']==4194304
    assert profile['plc']['p05Development']['hostExporterTestsPassed']==result.testsRun
    assert result.testsRun==23 and profile['plc']['p05Development']['nativeCompilationPassed']
    def saved(name):return json.loads((out/name).read_text(encoding='utf-8-sig'))
    diagnostic=saved('plc-diagnostics-test.json');pipeline=saved('plc-parallel-v4-test.json')
    assert diagnostic['Done'] and diagnostic['Passed']==16 and diagnostic['FailedChecks']==0
    assert pipeline['Done'] and pipeline['Passed']==41 and pipeline['FailedChecks']==0
    assert all(diagnostic[f'Checks[{i}]'] for i in range(1,17))
    assert all(pipeline[f'Checks[{i}]'] for i in range(1,42))
    assert pipeline['longPayloadHashMatches'] and pipeline['longPayloadBytes']==15244 and pipeline['longPayloadValueCount']==64
    assert hashlib.sha256(pipeline['LongPayload'].encode()).hexdigest()==pipeline['LongDigest']
    layout=saved('compiled-production-v4.json');perf=saved('performance-result.json')
    assert layout['valueSizes']['NG_CaptureEvent']==72 and layout['valueSizes']['NG_Buffer']==3057128
    assert layout['captureHelperUpperBound']==61848<=layout['helperAndScratchReserved']
    assert layout['mqttStateUpperBound']==9432<=layout['mqttStateReserved']
    assert perf['productionAccountedBytes']==profile['plc']['p05Measured']['accountedSubsystemBytes']==4170829
    assert perf['performanceVariantAccountedBytes']==4170891<=profile['plc']['subsystemRamBytes']
    first=saved('perf-hold-recovery-1.json');last=saved('perf-hold-recovery-2.json')
    rate=(last['CaptureBuffer.StoredConfirmedEventsTotal']-first['CaptureBuffer.StoredConfirmedEventsTotal'])/((last['NowMs']-first['NowMs'])/1000)
    assert abs(rate-perf['confirmedLocalReleaseEventsPerSecond'])<1e-10 and rate<90
    assert not perf['performancePassed'] and not profile['plc']['p06Measured']['performancePassed']
    assert not perf['addedWorkOneMsProven'] and not perf['normalThirtyMinuteLoadProven'] and not perf['opaqueSdkHeapHighWaterProven']
    events=batches=0
    for boot in (32,33):
        cohort=saved(f'cohort-boot{boot}.json');db=saved(f'hub-receipts-boot{boot}.json');end=saved(f'perf-boot{boot}-final.json')
        assert cohort['bootId']==db['bootId']==end['BootId']
        assert cohort['cohortComplete'] and db['cohortComplete'] and not cohort['globalAccountingComplete']
        assert cohort['previousRamRestartLoss']=='UNKNOWN' and not cohort['performancePassed']
        assert not db['temporaryDatabaseCreated'] and not db['databaseWrites']
        assert cohort['stored']==db['committedSamplesVerified']==end['CaptureBuffer.StoredConfirmedEventsTotal']
        assert cohort['batches']==db['receiptHashesVerified']
        assert not end['Active.enabled'] and end['CaptureBuffer.OwnedCount']==end['CaptureBuffer.IngressCount']==0
        assert end['CaptureBuffer.AuditDropped']==end['CaptureBuffer.AssociationDropped']==0
        events+=cohort['stored'];batches+=cohort['batches']
    assert events==83500 and batches==1311
    assert saved('perf-boot33-final.json')['P06MaxUs']==23515 and saved('perf-boot33-final.json')['P06OverPeriod']==1
    restored=saved('restoration-result.json');env=saved('environment-restored.json')
    assert restored['originalRuntimeRestored'] and restored['restoredBoot'].endswith('-34')
    assert restored['realStoredBatchesObserved']==27 and restored['acquisitionEnabled'] and restored['mqttConnected']
    assert env['backendInstanceCount']==1 and env['backendPid']==[34208] and env['resourceRecorderCount']==0
    assert not env['databaseCreated'] and not env['serviceRestarted']
    for name,expected in [('protocol.schema.json','d65c133d44a02072972361a4c601ca3b22bf0ab1125f6d63d48ca47b65a830e9'),
                          ('topics.json','f80f367dd34def81ba86a0a2eb370869bf99de1f25ceadfc986ca004da308d51')]:
        backend=ROOT.parent/'PLCnext-Hub-Backend/hub-device/src/main/resources/iot/contracts/v1'/name
        assert backend.read_bytes()==(ROOT.parent/'PLCnext-iot/contracts/v1'/name).read_bytes()
        assert hashlib.sha256(backend.read_bytes()).hexdigest()==expected
    documents=[ROOT/'README.md',ROOT/'tests/README.md',ROOT/'docs/阶段1-P05-P06开发进度与待验-20261024.md',
        ROOT/'docs/阶段1-三方实施任务与顺序.md',ROOT/'docs/Hub-IoT-PLC协同实施计划.md',
        ROOT/'docs/后台服务检查-2026-10-24.md',
        ROOT.parent/'PLCnext-Hub-Backend/docs/architecture/hub-iot-phase0.md',
        ROOT.parent/'PLCnext-iot/doc/三方阶段0接口定稿.md']
    for path in documents:
        text=path.read_text(encoding='utf-8-sig')
        assert text.count('```')%2==0,path
        for target in re.findall(r'(?<!!)\[[^\]]*\]\(([^)]+)\)',text):
            if '://' in target or target.startswith('#'):continue
            assert (path.parent/target.split('#')[0]).exists(),(path,target)
    report=dict(evidenceLevel='OFFLINE_PACKAGING_AND_HOST_EXPORTER_TESTS',hostTestsRun=result.testsRun,
        hostTestsPassed=True,sourceMatchesRootArchive=True,sourceHashes=hashes,isolatedPackages=packages,
        nativeCompilation='ARCHIVED_ENGINEER_REBUILD_PASSED',nativeDiagnosticAssertions=16,nativePipelineAssertions=41,
        nativeAssertionScope='ARCHIVED_REAL_PLC_RESULTS_NOT_EXECUTED_BY_THIS_OFFLINE_CHECK',
        realStoredEvents=events,realStoredBatches=batches,existingDevDatabaseVerified=True,
        documentsChecked=len(documents),canonicalUnchanged=True,
        accountedFixedBytes=4170829,memoryBudgetMeasured=True,opaqueSdkHeapMeasured=False,
        scanBudgetMeasured=True,releaseRateMeasured=True,performancePassed=False,
        confirmedLocalReleaseEventsPerSecond=rate,maxTaskUs=23515,overPeriodScans=1,
        deviceDownload=True,originalRuntimeRestored=True,restoredBoot=restored['restoredBoot'],noDatabaseCreated=True)
    (out/'offline-check.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('sourceHashes','isolatedPackages')}))


if __name__=='__main__':main()
