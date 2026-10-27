"""Generate native ACK protocol regression and timing fixtures; no I/O/Hub ACKs."""
import argparse
import copy
import json
from pathlib import Path
from build_phase1_capture_test import ROOT,build

BASE=dict(schemaVersion=1,gatewayId='test-gw',timestamp=1000,messageId='d-test-boot-1',status='STORED',errors=[])
ERROR=dict(code='RESOURCE_LIMIT',path='/values/0',message='fixture error')

def cases():
    rows=[]
    def add(name,value,valid,stored=False,retryable=True):rows.append((name,value,valid,stored,retryable))
    add('stored',BASE,True,True)
    add('reordered',dict(reversed(list(BASE.items()))),True,True)
    for key,value in [('schemaVersion',2),('gatewayId','other'),('timestamp',-1),('timestamp',1.5),
                      ('timestamp',9007199254740992),('messageId','bad/id'),('messageId','x'*65),
                      ('status','OTHER'),('status',None),('errors',None)]:
        row=copy.deepcopy(BASE);row[key]=value;add(f'invalid {key}',row,False)
    row=copy.deepcopy(BASE);row['extra']=1;add('unknown root field',row,False)
    for key in BASE:
        row=copy.deepcopy(BASE);del row[key];add('missing '+key,row,False)
    row=copy.deepcopy(BASE);row['timestamp']=9007199254740991;add('maximum timestamp',row,True,True)
    row=copy.deepcopy(BASE);row['errors']=[ERROR];add('stored with errors',row,False)
    row=copy.deepcopy(BASE);row['status']='REJECTED';add('rejected empty',row,False)
    for code in ['RESOURCE_LIMIT','STORAGE_ERROR','UNKNOWN_CONFIG_VERSION','INVALID_TIMESTAMP']:
        row=copy.deepcopy(BASE);row['status']='REJECTED';row['errors']=[dict(ERROR,code=code)]
        add(code,row,True,False,code!='INVALID_TIMESTAMP')
    for field,value in [('code','UNKNOWN'),('path','not-pointer'),('message',''),('deviceId','bad/id'),
                        ('pointId',42),('extra',True)]:
        row=copy.deepcopy(BASE);row['status']='REJECTED';row['errors']=[dict(ERROR,**{field:value})]
        add('invalid error '+field,row,False)
    for field in ['code','path','message']:
        row=copy.deepcopy(BASE);row['status']='REJECTED';error=dict(ERROR);del error[field];row['errors']=[error]
        add('missing error '+field,row,False)
    for count in (32,33):
        row=copy.deepcopy(BASE);row['status']='REJECTED';row['errors']=[ERROR]*count
        add(f'{count} errors',row,count==32)
    row=copy.deepcopy(BASE);row['status']='REJECTED';row['errors']=[dict(ERROR,deviceId='device',pointId='point')]
    add('optional identities',row,True)
    duplicate=json.dumps(BASE,separators=(',',':'))[:-1]+',"status":"STORED"}'
    add('duplicate root key',duplicate,False)
    return rows

def package(output):
    rows=cases()
    definitions=[]
    for i,(name,value,valid,stored,retryable) in enumerate(rows,1):
        wire=value if isinstance(value,str) else json.dumps(value,separators=(',',':'))
        assert len(wire)<16380
        definitions.append(f"    {i}: Payload:='{wire.replace(chr(39),chr(39)*2)}'; ExpectedValid:={str(valid).upper()}; ExpectedStored:={str(stored).upper()}; ExpectedRetryable:={str(retryable).upper()};")
    source='''PROGRAM Main
VAR
    Doc : NG_Document;
    Parser : NG_JsonParse;
    Reader : NG_ReadAck;
    Bytes : NG_Bytes;
    CopyString : STRING_TO_BUF;
    Payload : NG_Json;
    ExpectedValid : BOOL;
    ExpectedStored : BOOL;
    ExpectedRetryable : BOOL;
    CaseIndex : INT := 1;
    Stage : INT;
    Done : BOOL;
    Passed : UDINT;
    FailedChecks : UDINT;
    Checks : ARRAY[1..64] OF BOOL;
    BoundaryNumber : LREAL;
    BoundaryAsLint : LINT;
    BoundaryLimit : LREAL;
    BoundaryTruncated : LINT;
    BoundaryParserError : BOOL;
    BoundaryValid : BOOL;
    MaxReaderUs : ULINT;
    LastReaderUs : ULINT;
    StartUs : ULINT;
END_VAR
IF Done THEN RETURN; END_IF;
IF Stage=0 THEN
    Parser(Execute:=FALSE,Length:=UDINT#0,Buffer:=Bytes,Doc:=Doc);
    CASE CaseIndex OF
'''+ '\n'.join(definitions)+'''
    END_CASE;
    CopyString(REQ:=FALSE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(Payload),SRC:=Payload,BUFFER:=Bytes);
    CopyString(REQ:=TRUE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(Payload),SRC:=Payload,BUFFER:=Bytes);
    Stage:=1;
END_IF;
Parser(Execute:=TRUE,Length:=TO_UDINT(LEN(Payload)),Buffer:=Bytes,Doc:=Doc);
IF Parser.Done OR Parser.Error THEN
    IF Parser.Error THEN Checks[CaseIndex]:=NOT ExpectedValid;
    ELSE
        StartUs:=GET_MICROSECONDS(TRUE); Reader(GatewayId:='test-gw',Doc:=Doc);
        LastReaderUs:=GET_MICROSECONDS(TRUE)-StartUs; MaxReaderUs:=MAX(MaxReaderUs,LastReaderUs);
        Checks[CaseIndex]:=Reader.Valid=ExpectedValid;
        IF Reader.Valid THEN Checks[CaseIndex]:=Checks[CaseIndex] AND (Reader.Stored=ExpectedStored) AND (Reader.Retryable=ExpectedRetryable) AND (Reader.MessageId='d-test-boot-1'); END_IF;
    END_IF;
    IF Checks[CaseIndex] THEN Passed:=Passed+1; ELSE FailedChecks:=FailedChecks+1; END_IF;
    IF CaseIndex=20 THEN BoundaryNumber:=Doc.Tokens[4].Number; BoundaryAsLint:=TO_LINT(BoundaryNumber); BoundaryLimit:=LREAL#9007199254740991.0; BoundaryTruncated:=TRUNC_LINT(BoundaryNumber); BoundaryParserError:=Parser.Error; BoundaryValid:=Reader.Valid; END_IF;
    CaseIndex:=CaseIndex+1; Stage:=0;
    IF CaseIndex>'''+str(len(rows))+''' THEN Done:=TRUE; END_IF;
END_IF;
END_PROGRAM
'''
    fixture=output.with_suffix('.st');fixture.parent.mkdir(parents=True,exist_ok=True);fixture.write_text(source,encoding='utf-8')
    build(output,fixture,{'Main','NG_JsonParse','NG_Char','NG_ReadAck','NG_AckFields','NG_ValidId','NG_WireCode','NG_NumberValid','NG_SafeAdd'})
    print(json.dumps(dict(cases=len(rows),caseNames=[r[0] for r in rows])))

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path);package(ap.parse_args().output.resolve())
