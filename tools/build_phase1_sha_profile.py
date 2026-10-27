"""Add diagnostic-only SHA/component counters to an existing test overlay.

No source, DB, device or service operation. Extra timing calls perturb the
budget: this variant is ineligible for P06 performance acceptance.
"""
import argparse
from pathlib import Path
import zipfile


def build(base, output):
    with zipfile.ZipFile(base) as z:
        files={name:z.read(name) for name in z.namelist()}
    prefix='PROJECT/Logical%20Elements/NG_StringSHA256.pou/'
    variables=files[prefix+'Variables.var'].decode()
    variables=variables.replace('    Digest : STRING[64];','''    Digest : STRING[64];
    ProfileTotalUs : ULINT;
    ProfileLoadUs : ULINT;
    ProfileScheduleUs : ULINT;
    ProfileRoundsUs : ULINT;
    ProfileBlocks : ULINT;
    ProfileCalls : ULINT;''',1)
    variables=variables.replace('\nVAR\n','\nVAR\n    ProfileStart : ULINT;\n    ProfileMark : ULINT;\n    ProfileFirstBlock : UDINT;\n',1)
    code=files[prefix+'Code.st'].decode()
    markers=['FOR n := 1 TO 64 DO','    Offset:=Block*64; BlockLength:=0;',
             '    (* W16 *)','    a := Hs[0];','    Hs[0] := TO_DWORD']
    assert all(code.count(marker)==1 for marker in markers)
    code=code.replace(markers[0],'ProfileStart:=GET_MICROSECONDS(TRUE); ProfileFirstBlock:=Block;\n'+markers[0],1)
    code=code.replace(markers[1],'    ProfileMark:=GET_MICROSECONDS(TRUE);\n'+markers[1],1)
    code=code.replace(markers[2],'    ProfileLoadUs:=ProfileLoadUs+GET_MICROSECONDS(TRUE)-ProfileMark; ProfileMark:=GET_MICROSECONDS(TRUE);\n'+markers[2],1)
    code=code.replace(markers[3],'    ProfileScheduleUs:=ProfileScheduleUs+GET_MICROSECONDS(TRUE)-ProfileMark; ProfileMark:=GET_MICROSECONDS(TRUE);\n'+markers[3],1)
    code=code.replace(markers[4],'    ProfileRoundsUs:=ProfileRoundsUs+GET_MICROSECONDS(TRUE)-ProfileMark;\n'+markers[4],1)
    code+='''
ProfileTotalUs:=ProfileTotalUs+GET_MICROSECONDS(TRUE)-ProfileStart;
ProfileBlocks:=ProfileBlocks+TO_ULINT(Block-ProfileFirstBlock); ProfileCalls:=ProfileCalls+1;
'''
    files[prefix+'Variables.var']=variables.encode()
    files[prefix+'Code.st']=code.encode()
    prefix='PROJECT/Logical%20Elements/Main.pou/'
    variables=files[prefix+'Variables.var'].decode()
    variables=variables.replace('    P06WorkMark : ULINT;','    P06WorkMark : ULINT;\n    P06WorkSum : ARRAY[1..6] OF ULINT;',1)
    code=files[prefix+'Code.st'].decode()
    assert code.count('CaptureBuffer.LayoutBytes:=')==1
    code=code.replace('CaptureBuffer.LayoutBytes:=','CaptureExtraBytes:=CaptureExtraBytes+SIZEOF(P06WorkSum);\nCaptureBuffer.LayoutBytes:=',1)
    marker='CaptureBuffer.WorkMaxUs:=MAX(CaptureBuffer.WorkMaxUs,CaptureBuffer.WorkLastUs);'
    assert marker in code
    code=code.replace(marker,marker+'\nFOR P06SectionIndex:=1 TO 6 DO P06WorkSum[P06SectionIndex]:=P06WorkSum[P06SectionIndex]+P06WorkParts[P06SectionIndex]; END_FOR;',1)
    files[prefix+'Variables.var']=variables.encode()
    files[prefix+'Code.st']=code.encode()
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
        for name,content in files.items():z.writestr(name,content)
    print(output)


if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('base',type=Path)
    ap.add_argument('output',type=Path)
    args=ap.parse_args();build(args.base,args.output)
