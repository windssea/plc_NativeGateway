FUNCTION_BLOCK NG_TimeResponse
VAR_INPUT
    Length : UDINT;
    Retained : BOOL;
    GatewayId : NG_Id;
    BootId : NG_Id;
    SessionId : NG_Id;
    RequestId : NG_Id;
    ClientMonoMs : ULINT;
END_VAR
VAR_IN_OUT
    Doc : NG_Document;
    Bytes : NG_Bytes;
END_VAR
VAR_OUTPUT
    Valid : BOOL;
    ServerReceivedMs : ULINT;
    ServerSentMs : ULINT;
END_VAR
VAR
    Fields : ARRAY[1..8] OF INT;
    i : INT;
    j : INT;
    f : INT;
    t : INT;
    n : INT;
    offset : DINT;
    wireId : NG_Id;
    integerValue : ULINT;
END_VAR
Valid:=FALSE; ServerReceivedMs:=0; ServerSentMs:=0;
IF Retained OR (Length=0) OR (Length>2048) OR (Doc.Count<>9) THEN RETURN; END_IF;
IF (Doc.Tokens[1].Kind<>1) OR (Doc.Tokens[1].NextToken<>10) THEN RETURN; END_IF;
FOR j:=1 TO 8 DO Fields[j]:=0; END_FOR;
FOR i:=2 TO 9 DO
    IF (Doc.Tokens[i].Parent<>1) OR (Doc.Tokens[i].NextToken<>i+1) THEN RETURN; END_IF;
    f:=0;
    IF Doc.Tokens[i].Key='schemaVersion' THEN f:=1;
    ELSIF Doc.Tokens[i].Key='gatewayId' THEN f:=2;
    ELSIF Doc.Tokens[i].Key='requestId' THEN f:=3;
    ELSIF Doc.Tokens[i].Key='bootId' THEN f:=4;
    ELSIF Doc.Tokens[i].Key='sessionId' THEN f:=5;
    ELSIF Doc.Tokens[i].Key='clientMonoMs' THEN f:=6;
    ELSIF Doc.Tokens[i].Key='serverReceivedAt' THEN f:=7;
    ELSIF Doc.Tokens[i].Key='serverSentAt' THEN f:=8; END_IF;
    IF f=0 THEN RETURN; END_IF;
    IF Fields[f]<>0 THEN RETURN; END_IF; Fields[f]:=i;
END_FOR;
FOR j:=1 TO 8 DO
    t:=Fields[j]; IF t=0 THEN RETURN; END_IF;
    IF (j=1) OR (j>=6) THEN
        IF Doc.Tokens[t].Kind<>4 THEN RETURN; END_IF;
        (* Lexical digits only: reject JSON 1.0/1e0, signed and bool integers. *)
        n:=TO_INT(Doc.Tokens[t].Count); offset:=Doc.Tokens[t].Start;
        IF (n<1) OR (n>16) OR (offset<0) OR (offset+TO_DINT(n)>TO_DINT(Length)) THEN RETURN; END_IF;
        FOR i:=0 TO n-1 DO
            IF (Bytes[offset+i]<BYTE#48) OR (Bytes[offset+i]>BYTE#57) THEN RETURN; END_IF;
        END_FOR;
        IF NOT ((Doc.Tokens[t].Number>=0) AND (Doc.Tokens[t].Number<=LREAL#9007199254740991.0)) THEN RETURN; END_IF;
        IF Doc.Tokens[t].Number<>TO_LREAL(TRUNC_LINT(Doc.Tokens[t].Number)) THEN RETURN; END_IF;
        integerValue:=TO_ULINT(TRUNC_LINT(Doc.Tokens[t].Number));
        CASE j OF
            1: IF integerValue<>1 THEN RETURN; END_IF;
            6: IF integerValue<>ClientMonoMs THEN RETURN; END_IF;
            7: ServerReceivedMs:=integerValue;
            8: ServerSentMs:=integerValue;
        END_CASE;
    ELSE
        IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].TextLength<1) OR (Doc.Tokens[t].TextLength>64) THEN RETURN; END_IF;
        wireId:=Doc.Tokens[t].Text; IF NOT NG_ValidId(wireId) THEN RETURN; END_IF;
        CASE j OF
            2: IF wireId<>GatewayId THEN RETURN; END_IF;
            3: IF wireId<>RequestId THEN RETURN; END_IF;
            4: IF wireId<>BootId THEN RETURN; END_IF;
            5: IF wireId<>SessionId THEN RETURN; END_IF;
        END_CASE;
    END_IF;
END_FOR;
Valid:=TRUE;
END_FUNCTION_BLOCK
