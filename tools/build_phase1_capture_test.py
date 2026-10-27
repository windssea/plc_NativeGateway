"""Build an offline, pure IEC capture harness. Never connects to a PLC.

The generated project has no gateway, MQTT, store, socket or physical I/O calls.
Use Engineer to compile/run it only in an explicitly selected test runtime.
"""
from pathlib import Path
import argparse
import re
import zipfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def build(destination: Path, source_path=None, keep_set=None):
    source = (source_path or ROOT / 'tests/phase1_capture_test.st').read_text(encoding='utf-8')
    body = re.sub(r'^PROGRAM Main\s*', '', source)
    end = list(re.finditer(r'\bEND_VAR\b', body))[-1].end()
    variables, code = body[:end], body[end:]
    code = re.sub(r'\s*END_PROGRAM\s*$', '', code).strip() + '\n'
    with zipfile.ZipFile(ROOT / 'NativeGateway.pcwex') as z:
        files = {n: z.read(n) for n in z.namelist()}
    # Keep only reachable helpers; the harness has no communication blocks.
    keep = keep_set or {'Main','NG_Capture','NG_GapLog','NG_ConfigSlot','NG_PollSlot','NG_QualityCode',
            'NG_SafeAdd','NG_SameConfig','NG_SourceResult','NG_SourceState'}
    keep = set(keep) | {'NG_SourceStateCore','NG_CaptureCore','NG_AuditCapture','NG_AuditDecision','NG_AuditAssociation'}
    if 'NG_SourceResult' in keep:
        keep.add('NG_SourceResultCore')
    ns='http://schemas.microsoft.com/developer/msbuild/2003'
    ET.register_namespace('', ns)
    project=ET.fromstring(files['PROJECT/PROJECT.proj'])
    for group in project.findall('{'+ns+'}ItemGroup'):
        for item in list(group):
            match=re.match(r'Logical Elements\\([^\\]+)\.pou(?:\\|$)',item.get('Include',''))
            if match and match[1] not in keep:
                group.remove(item)
    files['PROJECT/PROJECT.proj']=ET.tostring(project,encoding='utf-8',xml_declaration=True)
    # Keep the archive payload in sync with its registrations. The independent
    # cold compiler intentionally rejects orphan POU source members.
    for name in list(files):
        match=re.match(r'PROJECT/Logical%20Elements/([^/]+)\.pou/',name)
        if match and match[1] not in keep:
            del files[name]
    prefix = 'PROJECT/Logical%20Elements/Main.pou/'
    files[prefix + 'Variables.var'] = variables.encode('utf-8')
    files[prefix + 'Code.st'] = code.encode('utf-8')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in files.items():
            z.writestr(name, data)
    print(destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    build(parser.parse_args().output.resolve())
