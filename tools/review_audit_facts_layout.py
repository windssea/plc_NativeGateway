"""Review public offline package layout receipts and source-FB growth; no I/O to PLC."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def package(path):
    data = read(path)
    data = data.get('result', data)
    assert data['package_complete'] and data['runtime_binding_validation_passed']
    assert not data['controller_connected'] and not data['controller_downloaded']
    layout = Path(data['type_layout_receipt']['output_directory'])
    for name, expected in [('TypeInformation.json', 'type_information_sha256'),
                           ('runtime-types-report.json', 'report_sha256')]:
        assert hashlib.sha256((layout / name).read_bytes()).hexdigest() == data['type_layout_receipt'][expected]
    source = Path(data['project_path'])
    assert hashlib.sha256(source.read_bytes()).hexdigest() == data['project_sha256']
    return data, read(layout / 'TypeInformation.json'), read(layout / 'runtime-types-report.json')


def review(before, after):
    baseline, oldtypes, oldreport = package(before)
    candidate, types, report = package(after)
    assert baseline['project_sha256'] == 'b585662abf3d86a1d0445d59e9ed4354723edebafd1f0fcb4b81647a7fe80d41'
    oldtypes = {t['Name']: t for t in oldtypes['Types']}
    types = {t['Name']: t for t in types['Types']}
    for name, size in [('NG_CaptureEvent', 72), ('NG_AuditEvent', 80), ('NG_SourceCursor', 48)]:
        assert types[name]['RuntimeSize'] == oldtypes[name]['RuntimeSize'] == size
    expected_offsets = {'NG_CaptureEvent': {'PollSkippedBefore': 68},
                        'NG_SourceCursor': {'PollSkippedPending': 44},
                        'NG_AuditEvent': {'Decision': 72, 'Reason': 73, 'DecisionFlags': 74,
                                          'DecisionRevisionDelta': 75, 'DecisionDelayLo': 76,
                                          'DecisionDelayHi': 78, 'ReportSkipped': 79}}
    for name, fields in expected_offsets.items():
        offsets = {f['Name']: f['FieldOffset'] for f in types[name]['Fields']}
        assert all(offsets[field] == offset for field, offset in fields.items())
    fb = set()
    with zipfile.ZipFile(candidate['project_path']) as archive:
        for name in archive.namelist():
            if name.endswith('/Metadata.meta'):
                meta = ET.fromstring(archive.read(name))
                if meta.findtext('ContentType') in ('FunctionBlock', 'Program'):
                    fb.add(name.split('/')[-2][:-4])
    cil = {t['name']: t for t in report['cil_layout']}
    counts = Counter()
    def walk(name, path=()):
        assert name not in path, 'Cyclic source FB ownership'
        counts[name] += 1
        for field in cil[name]['fields']:
            if not field['is_static'] and field['type'] in fb:
                walk(field['type'], path + (name,))
    walk('Main')
    old = {t['name']: t for t in oldreport['native_layout']}
    current = {t['name']: t for t in report['native_layout']}
    growth = [dict(name=n, instances=count, before=old[n]['size'], after=current[n]['size'],
                   growth=count*(current[n]['size']-old[n]['size']))
              for n, count in counts.items() if old[n]['size'] != current[n]['size']]
    non_buffer = sum(item['growth'] for item in growth if item['name'] != 'Main')
    buffer_growth = types['NG_Buffer']['RuntimeSize'] - oldtypes['NG_Buffer']['RuntimeSize']
    assert current['Main']['size'] - old['Main']['size'] == buffer_growth
    assert 0 <= non_buffer <= 2048
    budget = 4191151 + buffer_growth + 2048
    assert budget <= 4194304
    return dict(scope='PUBLIC_OFFLINE_NATIVE_LAYOUT_AND_EXPLICIT_CAPTURE_BUDGET',
                sourceProjectSha256=candidate['project_sha256'], packageJobId=candidate['package_job_id'],
                sizes={n: types[n]['RuntimeSize'] for n in expected_offsets}, offsets=expected_offsets,
                sourceFbCounts=dict(counts), sourceFbGrowth=growth, nonBufferFbGrowth=non_buffer,
                extraReserved=2048, bufferGrowth=buffer_growth, baselineBudget=4191151,
                newExplicitBudget=budget, explicitMargin=4194304-budget,
                layoutSource=candidate['type_layout_receipt']['output_directory'],
                mainClassSizeIsNotFourMiBBudget=True, privateSdkHeapProven=False,
                controllerConnected=False, plcProgramExecuted=False, performanceAccepted=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = review(args.baseline, args.candidate)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('sourceFbCounts','sourceFbGrowth')}, ensure_ascii=False))
