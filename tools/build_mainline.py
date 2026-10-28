"""Reproduce the single mainline project from src/, without controller access.

The frozen functional archive supplies only engineering metadata, hardware/HMI
and task bindings. All 66 IEC POU bodies/interfaces and both NG type worksheets
come from the checked-in editable sources. Historical audit/P06 builders are not
part of this release entry point. Existing release archives are never replaced.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'projects/candidates/native-0.7.0-timesync-candidate.1/NativeGateway.pcwex'
BASE_SHA = 'b585662abf3d86a1d0445d59e9ed4354723edebafd1f0fcb4b81647a7fe80d41'
VERSION = 'native-0.8.0'
OUTPUT = ROOT / 'projects/releases' / VERSION / 'NativeGateway.pcwex'


def split(source):
    body = source.split('\n', 1)[1]
    end = list(re.finditer(r'\bEND_VAR\b', body))[-1].end()
    return body[:end] + '\n', re.sub(r'\s*END_(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s*$', '', body[end:]).strip() + '\n'


def build(output):
    if hashlib.sha256(BASE.read_bytes()).hexdigest() != BASE_SHA:
        raise ValueError('Frozen engineering base changed')
    with zipfile.ZipFile(BASE) as archive:
        files = {n: archive.read(n) for n in archive.namelist()}
    original = dict(files)
    names = sorted(n.split('/')[-2][:-4] for n in files if n.endswith('.pou/Code.st'))
    if set(names) != {p.stem for p in (ROOT / 'src').glob('*.st')}:
        raise ValueError('Editable POU set differs from the release engineering model')
    inputs = {}
    normalized_inputs = {}
    for name in names:
        path = ROOT / 'src' / (name + '.st')
        variables, code = split(path.read_text(encoding='utf-8-sig'))
        prefix = f'PROJECT/Logical%20Elements/{name}.pou/'
        files[prefix + 'Variables.var'] = variables.encode('utf-8')
        files[prefix + 'Code.st'] = code.encode('utf-8')
        inputs[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        normalized_inputs[path.relative_to(ROOT).as_posix()] = hashlib.sha256(
            path.read_text(encoding='utf-8-sig').encode('utf-8')).hexdigest()
    for name in ('NG_Types.dt', 'NG_CaptureTypes.dt'):
        path = ROOT / 'src' / name
        # The frozen vendor type worksheets use CRLF. Keep archive bytes
        # deterministic when Git checks editable sources out with LF.
        files['PROJECT/Logical%20Elements/' + name] = path.read_text(
            encoding='utf-8').replace('\n', '\r\n').encode('utf-8')
        inputs[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
        normalized_inputs[path.relative_to(ROOT).as_posix()] = hashlib.sha256(
            path.read_text(encoding='utf-8-sig').encode('utf-8')).hexdigest()
    main = files['PROJECT/Logical%20Elements/Main.pou/Code.st'].decode()
    variables = files['PROJECT/Logical%20Elements/Main.pou/Variables.var'].decode()
    if re.findall(r'"agentVersion":"([^"]+)"', main) != [VERSION]:
        raise ValueError('Mainline heartbeat version must equal the archive version')
    if 'TimeMode : BOOL := TRUE;' not in variables:
        raise ValueError('Mainline requires automatic Hub logical time')
    if files['PROJECT/Logical%20Elements/NG_Types.dt'] != original['PROJECT/Logical%20Elements/NG_Types.dt']:
        raise ValueError('Persistent configuration layout changed')
    output.parent.mkdir(parents=True, exist_ok=True)
    # A fixed ZIP timestamp/order makes identical source inputs byte reproducible.
    with output.open('xb') as stream, zipfile.ZipFile(stream, 'w', zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(files):
            info = zipfile.ZipInfo(name, (2026, 10, 28, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, files[name])
    changed = [n for n in files if files[n] != original[n]]
    report = dict(version=VERSION, output=str(output), sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                  baseSha256=BASE_SHA, pouCount=len(names), inputs=inputs,
                  normalizedInputs=normalized_inputs, changedArchiveMembers=changed,
                  hardwareHmiTasksUnchanged=all(files[n] == original[n] for n in files
                      if not n.startswith('PROJECT/Logical%20Elements/')),
                  timeProfile='Hub logical time; existing development drift bound 1000ppm',
                  durableConfigurationLayoutUnchanged=True, controllerAccess=False)
    output.with_suffix('.build.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k not in ('inputs','normalizedInputs','changedArchiveMembers')}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    build(parser.parse_args().output.resolve())
