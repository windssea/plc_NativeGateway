"""Generate no-I/O ST assertions from the shared timeSyncV1 golden cases."""
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def generate():
    golden=json.loads((ROOT/'tests/time-sync-cases.json').read_text(encoding='utf-8'))
    cases=[]
    for case in golden['cases']:
        value=dict(case['payload'])
        if case['kind']=='timeRequest':value.update(serverReceivedAt=1792739100000,serverSentAt=1792739100005)
        cases.append((case['name'],json.dumps(value,separators=(',',':')),case['valid'],False))
    base=next(dict(c['payload']) for c in golden['cases'] if c['name']=='response')
    wire=json.dumps(base,separators=(',',':'))
    cases.append(('retained',wire,False,True))
    for key,value in [('gatewayId','other'),('bootId','other'),('sessionId','other'),('requestId','other'),
                      ('clientMonoMs',10001),('clientMonoMs',10000.0),('serverSentAt',1.0),
                      ('serverSentAt',9007199254740992),('serverReceivedAt',True),('timestamp',0)]:
        cases.append((key+'-echo-or-type',json.dumps(dict(base,**{key:value}),separators=(',',':')),False,False))
    cases.append(('duplicate',wire[:-1]+',"schemaVersion":1}',False,False))
    cases.append(('exponent',wire.replace('"schemaVersion":1,','"schemaVersion":1e0,'),False,False))
    lines=[]
    for number,(_name,raw,valid,retained) in enumerate(cases,1):
        escaped=raw.replace('$','$$').replace("'","$'")
        lines.append(f"        {number}: Payload:='{escaped}'; Expected:={str(valid).upper()}; Retained:={str(retained).upper()};")
    source='''FUNCTION_BLOCK NG_TimeResponseTest
VAR_OUTPUT
    Done : BOOL;
    Passed : UINT;
    FailedChecks : UINT;
    CaseCount : UINT;
END_VAR
VAR
    Parser : NG_JsonParse;
    Reader : NG_TimeResponse;
    Doc : NG_Document;
    Bytes : NG_Bytes;
    CopyString : STRING_TO_BUF;
    Payload : STRING[2048];
    Stage : UINT;
    CaseIndex : UINT := 1;
    Expected : BOOL;
    Retained : BOOL;
    Actual : BOOL;
END_VAR
IF Done THEN RETURN; END_IF;
Parser(Execute:=Stage=1,Length:=TO_UDINT(LEN(Payload)),Buffer:=Bytes,Doc:=Doc);
CASE Stage OF
0:
    CASE CaseIndex OF
'''+ '\n'.join(lines)+'''
    END_CASE;
    CopyString(REQ:=FALSE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(Payload),SRC:=Payload,BUFFER:=Bytes);
    CopyString(REQ:=TRUE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(Payload),SRC:=Payload,BUFFER:=Bytes);
    IF CopyString.DONE THEN Stage:=1; END_IF;
1:
    IF Parser.Error OR Parser.Done THEN
        Actual:=FALSE;
        IF Parser.Done THEN
            Reader(Length:=TO_UDINT(LEN(Payload)),Retained:=Retained,GatewayId:='PLC-01',BootId:='boot-A',
                SessionId:='session-A',RequestId:='time-boot-A-1',ClientMonoMs:=10000,Doc:=Doc,Bytes:=Bytes);
            Actual:=Reader.Valid;
        END_IF;
        IF Actual=Expected THEN Passed:=Passed+1; ELSE FailedChecks:=FailedChecks+1; END_IF;
        CaseCount:=CaseCount+1; Stage:=2;
    END_IF;
2:
    CaseIndex:=CaseIndex+1;
    IF CaseIndex>'''+str(len(cases))+''' THEN Done:=TRUE; ELSE Stage:=0; END_IF;
END_CASE;
END_FUNCTION_BLOCK
'''
    path=ROOT/'tests/NG_TimeResponseTest.st';path.write_text(source,encoding='utf-8')
    print(json.dumps(dict(path=str(path),cases=len(cases),scope='compiled assertions; execution is separate')))


if __name__=='__main__':generate()
