FUNCTION_BLOCK NG_ReadAck
VAR_INPUT
    GatewayId : NG_Id;
END_VAR
VAR_IN_OUT
    Doc : NG_Document;
END_VAR
VAR_OUTPUT
    Valid : BOOL;
    MessageId : NG_Id;
    Stored : BOOL;
    Retryable : BOOL;
    Codes : NG_Text;
END_VAR
VAR
    t : INT;
    n : INT;
    e : INT;
    count : INT;
    code : NG_Text;
    wire : NG_Text;
END_VAR
Valid := FALSE; MessageId := ''; Stored := FALSE; Retryable := TRUE; Codes := '';
IF NOT NG_Allowed(1,'|schemaVersion|gatewayId|timestamp|messageId|status|errors|',Doc) THEN RETURN; END_IF;
t := NG_Member(1,'schemaVersion',Doc); IF (Doc.Tokens[t].Kind<>4) OR (Doc.Tokens[t].Number<>1) THEN RETURN; END_IF;
t := NG_Member(1,'gatewayId',Doc); IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].Text<>GatewayId) THEN RETURN; END_IF;
t := NG_Member(1,'timestamp',Doc);
IF (Doc.Tokens[t].Kind<>4) OR (Doc.Tokens[t].Number<0) OR (Doc.Tokens[t].Number>LREAL#9007199254740991.0) OR (Doc.Tokens[t].Number<>TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN RETURN; END_IF;
t := NG_Member(1,'messageId',Doc);
IF (Doc.Tokens[t].Kind<>3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF;
MessageId := Doc.Tokens[t].Text; IF NOT NG_ValidId(MessageId) THEN RETURN; END_IF;
t := NG_Member(1,'status',Doc); IF Doc.Tokens[t].Kind<>3 THEN RETURN; END_IF;
IF Doc.Tokens[t].Text='STORED' THEN Stored:=TRUE;
ELSIF Doc.Tokens[t].Text<>'REJECTED' THEN RETURN; END_IF;
n := NG_Member(1,'errors',Doc); IF Doc.Tokens[n].Kind<>2 THEN RETURN; END_IF;
e:=n+1; count:=0;
WHILE e<Doc.Tokens[n].NextToken DO
    count:=count+1; IF Stored OR (count>32) THEN RETURN; END_IF;
    IF NOT NG_Allowed(e,'|code|path|message|deviceId|pointId|',Doc) THEN RETURN; END_IF;
    t:=NG_Member(e,'code',Doc); IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].TextLength>256) THEN RETURN; END_IF;
    code:=Doc.Tokens[t].Text; wire:=NG_WireCode(code,FALSE); IF wire<>code THEN RETURN; END_IF;
    IF (code<>'UNKNOWN_CONFIG_VERSION') AND (code<>'RESOURCE_LIMIT') AND (code<>'STORAGE_ERROR') THEN Retryable:=FALSE; END_IF;
    IF LEN(Codes)<200 THEN IF Codes<>'' THEN Codes:=CONCAT(Codes,','); END_IF; Codes:=CONCAT(Codes,code); END_IF;
    t:=NG_Member(e,'path',Doc); IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].TextLength>512) THEN RETURN; END_IF;
    IF (Doc.Tokens[t].Text<>'') AND (LEFT(Doc.Tokens[t].Text,1)<>'/') THEN RETURN; END_IF;
    t:=NG_Member(e,'message',Doc); IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].TextLength<1) OR (Doc.Tokens[t].TextLength>256) THEN RETURN; END_IF;
    t:=NG_Member(e,'deviceId',Doc);
    IF t>0 THEN IF (Doc.Tokens[t].Kind<>3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF; wire:=Doc.Tokens[t].Text; IF NOT NG_ValidId(wire) THEN RETURN; END_IF; END_IF;
    t:=NG_Member(e,'pointId',Doc);
    IF t>0 THEN IF (Doc.Tokens[t].Kind<>3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF; wire:=Doc.Tokens[t].Text; IF NOT NG_ValidId(wire) THEN RETURN; END_IF; END_IF;
    e:=Doc.Tokens[e].NextToken;
END_WHILE;
IF NOT Stored AND (count=0) THEN RETURN; END_IF;
Valid:=TRUE;
END_FUNCTION_BLOCK
