"""Overlay audit-v2 only on the frozen, verified candidate; no PLC/network I/O."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'projects/candidates/native-0.7.0-timesync-candidate.1/NativeGateway.pcwex'
BASE_SHA = 'b585662abf3d86a1d0445d59e9ed4354723edebafd1f0fcb4b81647a7fe80d41'
VERSION = 'native-0.7.1-audit-candidate.2'
POUS = ('NG_AuditCapture', 'NG_AuditDecision', 'NG_PollSlot', 'NG_SourceStateCore',
        'NG_CaptureCore', 'NG_ReportPolicy')


def split(source):
    body = source.split('\n', 1)[1]
    end = list(re.finditer(r'\bEND_VAR\b', body))[-1].end()
    return body[:end] + '\n', re.sub(r'\s*END_(FUNCTION_BLOCK|PROGRAM)\s*$', '', body[end:]).strip() + '\n'


def build(destination, harness=False):
    if destination.exists():
        raise FileExistsError(destination)
    assert hashlib.sha256(BASE.read_bytes()).hexdigest() == BASE_SHA
    with zipfile.ZipFile(BASE) as archive:
        files = {n: archive.read(n) for n in archive.namelist()}
    before = dict(files)
    for name in POUS:
        variables, code = split((ROOT / 'src' / (name + '.st')).read_text(encoding='utf-8-sig'))
        for member, text in [('Variables.var', variables), ('Code.st', code)]:
            files[f'PROJECT/Logical%20Elements/{name}.pou/{member}'] = text.encode('utf-8')
    files['PROJECT/Logical%20Elements/NG_CaptureTypes.dt'] = (ROOT / 'src/NG_CaptureTypes.dt').read_bytes()
    prefix = 'PROJECT/Logical%20Elements/Main.pou/'
    if harness:
        variables, code = split((ROOT / 'tests/audit_facts_test.st').read_text(encoding='utf-8'))
        files[prefix + 'Variables.var'] = variables.encode()
        files[prefix + 'Code.st'] = code.encode()
        # The assertion program reaches only these helpers. Remove unused
        # gateway/SDK POUs and their registrations instead of suppressing warnings.
        keep = {'Main', 'NG_CaptureCore', 'NG_AuditCapture', 'NG_AuditDecision',
                'NG_ReportPolicy', 'NG_PollSlot', 'NG_GapLog', 'NG_SafeAdd'}
        ns = 'http://schemas.microsoft.com/developer/msbuild/2003'
        ET.register_namespace('', ns)
        project = ET.fromstring(files['PROJECT/PROJECT.proj'])
        for group in project.findall('{'+ns+'}ItemGroup'):
            for item in list(group):
                match = re.match(r'Logical Elements\\([^\\]+)\.pou(?:\\|$)', item.get('Include', ''))
                if match and match[1] not in keep:
                    group.remove(item)
        files['PROJECT/PROJECT.proj'] = ET.tostring(project, encoding='utf-8', xml_declaration=True)
        for name in list(files):
            match = re.match(r'PROJECT/Logical%20Elements/([^/]+)\.pou/', name)
            if match and match[1] not in keep:
                del files[name]
    else:
        text = files[prefix + 'Code.st'].decode('utf-8-sig')
        anchor = 'CaptureBuffer.PlatformTime:=TimeMode; CaptureBuffer.TimeValid:=NativeClock.TimeValid; CaptureBuffer.ClockRevision:=NativeClock.ClockRevision;'
        assert text.count(anchor) == 1
        assert text.count('"agentVersion":"native-0.7.0-p05p06"') == 1
        text = text.replace(anchor, anchor + '\nCaptureBuffer.DecisionSnapshotMonoMs:=NowMs;')
        budget = 'SIZEOF(CaptureSourceEnabled)+SIZEOF(CaptureLivenessStart)+SIZEOF(PipelinePhase);'
        assert text.count(budget) == 1
        text = text.replace(budget, budget[:-1] + '+UDINT#2048; (* audit-v2 FB-instance growth bound *)')
        text = text.replace('"agentVersion":"native-0.7.0-p05p06"', '"agentVersion":"' + VERSION + '"')
        files[prefix + 'Code.st'] = text.encode()
    changed = sorted(k for k in set(files) | set(before) if files.get(k) != before.get(k))
    allowed = {f'PROJECT/Logical%20Elements/{name}.pou/{part}' for name in POUS + ('Main',)
               for part in ('Variables.var', 'Code.st')} | {'PROJECT/Logical%20Elements/NG_CaptureTypes.dt'}
    if harness:
        allowed |= {'PROJECT/PROJECT.proj'} | {k for k in before if k not in files}
    assert set(changed) <= allowed and set(files) <= set(before)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    result = dict(base=str(BASE), baseSha256=BASE_SHA, output=str(destination),
                  sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
                  artifactVersion=VERSION, auditFactSchema=2, harness=harness,
                  changedMembers=changed, taskHardwareHmiAndDurableTypesUnchanged=True,
                  rootAliasUnchanged=True, uploaded=False, compiled=False, executed=False)
    destination.with_suffix('.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--harness', action='store_true')
    args = parser.parse_args()
    print(json.dumps(build(args.output.resolve(), args.harness), ensure_ascii=False))
