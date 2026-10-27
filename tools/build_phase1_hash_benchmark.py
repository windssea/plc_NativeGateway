"""Package a no-I/O native comparison of exact-byte SHA readers.

Both readers share identical generated SHA rounds/padding and must match the
independent 15,244-byte golden vector. Timings include instrumentation and are
diagnostic only; they do not certify whole task or real STORED throughput.
"""
import argparse
import json
from pathlib import Path
import re
import zipfile
from build_phase1_capture_test import ROOT, build
from build_phase1_pipeline_test import KEEP
from generate_sha256 import generate


def package(output):
    golden = json.loads((ROOT/'tests/validation/p05-p06/plc-parallel-v20-test.json').read_text(encoding='utf-8'))
    payload = golden['LongPayload']
    assert len(payload) == 15244 and golden['longPayloadHashMatches'] and payload.isascii()
    literal = payload.replace("'", "''").replace('\\', '\\\\')
    fixture = output.with_suffix('.st')
    fixture.write_text('''PROGRAM Main
VAR
    Direct : NG_StringSHA256;
    BlockReader : NG_StringSHA256;
    FastReader : NG_StringSHA256;
    Payload : NG_Json;
    Stage : UINT;
    Done : BOOL;
    Passed : BOOL;
END_VAR
IF Done THEN RETURN; END_IF;
IF Stage=0 THEN
    Payload:=''' + "'" + literal + "';\n" + '''    Stage:=1;
END_IF;
Direct(Execute:=TRUE,Length:=TO_UDINT(LEN(Payload)),Payload:=Payload,UseBlock:=FALSE);
BlockReader(Execute:=TRUE,Length:=TO_UDINT(LEN(Payload)),Payload:=Payload,UseBlock:=TRUE);
FastReader(Execute:=TRUE,Length:=TO_UDINT(LEN(Payload)),Payload:=Payload,UseStringCopy:=TRUE);
IF Direct.Done AND BlockReader.Done AND FastReader.Done THEN
    Passed:=(Direct.Digest=BlockReader.Digest) AND (Direct.Digest=FastReader.Digest) AND (Direct.Digest=''' + "'" + golden['LongDigest'] + "');\n" + '''    Done:=TRUE;
END_IF;
END_PROGRAM
''', encoding='utf-8')
    build(output, fixture, set(KEEP)|{'NG_DeliveryParallel'})
    source = generate(reader='direct')
    source = source.replace('    Execute : BOOL;', '    Execute : BOOL;\n    UseBlock : BOOL;\n    UseStringCopy : BOOL;', 1)
    source = source.replace('    Digest : STRING[64];', '''    Digest : STRING[64];
    Calls : UDINT;
    TotalUs : ULINT;
    LoadUs : ULINT;
    ScheduleUs : ULINT;
    RoundsUs : ULINT;
    MaxCallUs : ULINT;''', 1)
    source = source.replace('\nVAR\n', '''
VAR
    StartUs : ULINT;
    MarkUs : ULINT;
    Scratch : ARRAY[0..64] OF BYTE;
    CopyBlock : STRING_TO_BUF;
''', 1)
    source = source.replace('FOR n := 1 TO 64 DO', 'StartUs:=GET_MICROSECONDS(TRUE);\nFOR n := 1 TO 64 DO', 1)
    source = source.replace('    Offset:=Block*64; BlockLength:=0;', '    MarkUs:=GET_MICROSECONDS(TRUE);\n    Offset:=Block*64; BlockLength:=0;', 1)
    marker = '    IF BlockLength=64 THEN\n'
    assert source.count(marker) == 1
    load = '''    IF UseBlock AND (BlockLength>0) THEN
        BlockText:=MID(Payload,BlockLength,TO_INT(Offset)+1);
        CopyBlock(REQ:=FALSE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=BlockLength,SRC:=BlockText,BUFFER:=Scratch);
        CopyBlock(REQ:=TRUE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=BlockLength,SRC:=BlockText,BUFFER:=Scratch);
        IF CopyBlock.ERROR THEN Error:=TRUE; Busy:=FALSE; RETURN; END_IF;
    END_IF;
'''
    source = source.replace(marker, load+marker, 1)
    start = source.index(marker)+len(marker)
    end = source.index('    ELSE\n', start)
    direct = source[start:end]
    block = re.sub(r'TO_DWORD\(TO_BYTE\(GET_CHAR\(Payload,TO_INT\(Offset\)\+(\d+)\)\)\)',
                   lambda m: 'TO_DWORD(Scratch['+str(int(m[1])-1)+'])', direct)
    assert block != direct and 'GET_CHAR' not in block
    fast = '''        BlockText:=MID(Payload,64,TO_INT(Offset)+1);
        CopyOk:=STRING_COPY(BlockText,W,UDINT#0,UDINT#64);
        IF NOT CopyOk THEN Error:=TRUE; Busy:=FALSE; RETURN; END_IF;
'''
    for index in range(16):
        fast += f'        W[{index}]:=SHR(W[{index}],24) OR (SHR(W[{index}],8) AND DWORD#16#0000FF00) OR (SHL(W[{index}],8) AND DWORD#16#00FF0000) OR SHL(W[{index}],24);\n'
    source = source[:start]+'    IF UseStringCopy THEN\n'+fast+'    ELSIF UseBlock THEN\n'+block+'    ELSE\n'+direct+'    END_IF;\n'+source[end:]
    source = source.replace('IF Offset < Length THEN v := TO_DWORD(TO_BYTE(GET_CHAR(Payload,TO_INT(Offset)+1)));',
        'IF Offset < Length THEN\n                IF UseBlock THEN v:=TO_DWORD(Scratch[Offset-Block*64]);\n                ELSE v := TO_DWORD(TO_BYTE(GET_CHAR(Payload,TO_INT(Offset)+1))); END_IF;', 1)
    source = source.replace('    (* W16 *)', '    LoadUs:=LoadUs+GET_MICROSECONDS(TRUE)-MarkUs; MarkUs:=GET_MICROSECONDS(TRUE);\n    (* W16 *)', 1)
    source = source.replace('    a := Hs[0];', '    ScheduleUs:=ScheduleUs+GET_MICROSECONDS(TRUE)-MarkUs; MarkUs:=GET_MICROSECONDS(TRUE);\n    a := Hs[0];', 1)
    source = source.replace('    Hs[0] := TO_DWORD', '    RoundsUs:=RoundsUs+GET_MICROSECONDS(TRUE)-MarkUs;\n    Hs[0] := TO_DWORD', 1)
    source = source.replace('\nEND_FUNCTION_BLOCK', '\nCalls:=Calls+1; MarkUs:=GET_MICROSECONDS(TRUE)-StartUs; TotalUs:=TotalUs+MarkUs; MaxCallUs:=MAX(MaxCallUs,MarkUs);\nEND_FUNCTION_BLOCK')
    body = re.sub(r'^FUNCTION_BLOCK NG_StringSHA256\s*', '', source)
    end = list(re.finditer(r'\bEND_VAR\b', body))[-1].end()
    variables, code = body[:end], re.sub(r'\s*END_FUNCTION_BLOCK\s*$', '', body[end:]).strip()+'\n'
    with zipfile.ZipFile(output) as z:
        files = {n: z.read(n) for n in z.namelist()}
    prefix = 'PROJECT/Logical%20Elements/NG_StringSHA256.pou/'
    files[prefix+'Variables.var'] = variables.encode()
    files[prefix+'Code.st'] = code.encode()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, content in files.items(): z.writestr(name, content)


if __name__ == '__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=Path)
    package(ap.parse_args().output.resolve())
