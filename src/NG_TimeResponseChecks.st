FUNCTION_BLOCK NG_TimeResponseChecks
VAR_IN_OUT
    Doc : NG_Document;
    Bytes : NG_Bytes;
END_VAR
VAR_OUTPUT
    Done : BOOL;
    Passed : UINT;
    FailedChecks : UINT;
    CaseCount : UINT;
END_VAR
VAR
    Parser : NG_JsonParse;
    Reader : NG_TimeResponse;
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
        1: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=TRUE; Retained:=FALSE;
        2: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=TRUE; Retained:=FALSE;
        3: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"timestamp":0,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        4: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":true,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        5: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000.0,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        6: Payload:='{"schemaVersion":1.0,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        7: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":null,"clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        8: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":9007199254740992,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        9: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        10: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"a/b","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        11: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=TRUE;
        12: Payload:='{"schemaVersion":1,"gatewayId":"other","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        13: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"other","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        14: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"other","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        15: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"other","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        16: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10001,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        17: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000.0,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        18: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1.0}'; Expected:=FALSE; Retained:=FALSE;
        19: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":9007199254740992}'; Expected:=FALSE; Retained:=FALSE;
        20: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":true,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
        21: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005,"timestamp":0}'; Expected:=FALSE; Retained:=FALSE;
        22: Payload:='{"schemaVersion":1,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005,"schemaVersion":1}'; Expected:=FALSE; Retained:=FALSE;
        23: Payload:='{"schemaVersion":1e0,"gatewayId":"PLC-01","requestId":"time-boot-A-1","bootId":"boot-A","sessionId":"session-A","clientMonoMs":10000,"serverReceivedAt":1792739100000,"serverSentAt":1792739100005}'; Expected:=FALSE; Retained:=FALSE;
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
    IF CaseIndex>23 THEN Done:=TRUE; ELSE Stage:=0; END_IF;
END_CASE;

END_FUNCTION_BLOCK
