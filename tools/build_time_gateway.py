"""Overlay time integration on a separate current gateway archive; never upload.

Only existing POU bodies/interfaces and the volatile capture types are replaced.
Legacy inputs need missing time FBs added by public MCP after import; the reviewed
root candidate already contains them. The durable types, task timing, hardware
and HMI mappings remain byte-identical. Outputs still require compilation/review.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT=Path(__file__).resolve().parents[1]
POUS=('Main','NG_Mqtt','NG_CaptureCore','NG_ReportPolicy','NG_BatchBuilder')


def split(source):
    rest=source.split('\n',1)[1];end=list(re.finditer(r'\bEND_VAR\b',rest))[-1].end()
    return rest[:end]+'\n',re.sub(r'\s*END_(PROGRAM|FUNCTION_BLOCK)\s*$','',rest[end:]).strip()+'\n'


def assertion_fbs():
    source=(ROOT/'tests/NG_TimeResponseTest.st').read_text(encoding='utf-8')
    variables,code=split(source)
    variables=variables.replace('    Doc : NG_Document;\n','').replace('    Bytes : NG_Bytes;\n','')
    variables='VAR_IN_OUT\n    Doc : NG_Document;\n    Bytes : NG_Bytes;\nEND_VAR\n'+variables
    wire=dict(pou_name='NG_TimeResponseChecks',variables=variables,code=code)
    source=(ROOT/'tests/platform_time_test.st').read_text(encoding='utf-8')
    variables,code=split(source)
    for name,typ in [('Done','BOOL'),('Passed','UINT'),('FailedChecks','UINT')]:
        variables=variables.replace(f'    {name} : {typ};\n','')
    variables=variables.replace('WireTests : NG_TimeResponseTest;','WireTests : NG_TimeResponseChecks;')
    variables='VAR_OUTPUT\n    Done : BOOL;\n    Passed : UINT;\n    FailedChecks : UINT;\n    WirePassed : UINT;\n    WireFailed : UINT;\nEND_VAR\nVAR_IN_OUT\n    Doc : NG_Document;\n    Bytes : NG_Bytes;\nEND_VAR\n'+variables
    code=code.replace('WireTests();','WireTests(Doc:=Doc,Bytes:=Bytes);\nWirePassed:=WireTests.Passed; WireFailed:=WireTests.FailedChecks;')
    clock=dict(pou_name='NG_PlatformTimeChecks',variables=variables,code=code)
    return [wire,clock]


def write_assertion_sources():
    """Keep build_native.py's src/*.st path complete without changing archives."""
    for item in assertion_fbs():
        path=ROOT/'src'/(item['pou_name']+'.st')
        path.write_text('FUNCTION_BLOCK '+item['pou_name']+'\n'+item['variables']+'\n'+item['code']+'\nEND_FUNCTION_BLOCK\n',encoding='utf-8')
    print(json.dumps(dict(assertionSourcesWritten=True,archiveChanged=False)))


def build(destination,platform=False,drift_evidence=None,base=None):
    base = ROOT/'NativeGateway.pcwex' if base is None else base
    if destination.exists():raise FileExistsError(destination)
    if platform and (drift_evidence is None or not drift_evidence.is_file()):raise ValueError('Explicit existing drift evidence required for platform profile')
    with zipfile.ZipFile(base) as z:files={n:z.read(n) for n in z.namelist()}
    original=dict(files);patches=[]
    for name in POUS:
        source=(ROOT/'src'/f'{name}.st').read_text(encoding='utf-8-sig')
        if name=='Main' and platform:
            ref='DEV_OBSERVATION_'+hashlib.sha256(drift_evidence.read_bytes()).hexdigest()[:24]
            source=source.replace('TimeMode : BOOL;','TimeMode : BOOL := TRUE;',1)
            source=source.replace('TimeDriftEvidence : NG_Text;',f"TimeDriftEvidence : NG_Text := '{ref}';",1)
        variables,code=split(source);prefix=f'PROJECT/Logical%20Elements/{name}.pou/'
        for member,text in [('Variables.var',variables),('Code.st',code)]:
            path=prefix+member
            if path not in files:raise ValueError('Only existing POU overlays are supported')
            files[path]=text.encode('utf-8');patches.append(path)
    path='PROJECT/Logical%20Elements/NG_CaptureTypes.dt'
    if path not in files:raise ValueError('Capture type worksheet missing')
    files[path]=(ROOT/'src/NG_CaptureTypes.dt').read_bytes();patches.append(path)
    assert files['PROJECT/Logical%20Elements/NG_Types.dt']==original['PROJECT/Logical%20Elements/NG_Types.dt']
    destination.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED) as z:
        for path,data in files.items():z.writestr(path,data)
    result=dict(source=str(base),output=str(destination),sha256=hashlib.sha256(destination.read_bytes()).hexdigest(),
        platformMode=platform,driftEvidence=str(drift_evidence) if drift_evidence else None,patchedMembers=patches,
        otherMemberPayloadsIdentical=all(files[k]==v for k,v in original.items() if k not in patches),
        durableTypeLayoutUnchanged=True,taskTimingUnchanged=True,uploaded=False)
    destination.with_suffix('.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path,nargs='?')
    p.add_argument('--platform',action='store_true');p.add_argument('--drift-evidence',type=Path)
    p.add_argument('--base',type=Path,help='Explicit input engineering archive; defaults to the reviewed root candidate')
    p.add_argument('--write-assertion-sources',action='store_true')
    a=p.parse_args()
    if a.write_assertion_sources:write_assertion_sources()
    elif a.output is None:p.error('output or --write-assertion-sources required')
    else:build(a.output.resolve(),a.platform,a.drift_evidence,a.base.resolve() if a.base else None)
