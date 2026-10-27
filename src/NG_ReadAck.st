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
    RootFields : NG_AckFields;
    ErrorFields : NG_AckFields;
    t : INT;
    n : INT;
    e : INT;
    count : INT;
    code : NG_Text;
    wire : NG_Text;
END_VAR
Valid := FALSE; MessageId := ''; Stored := FALSE; Retryable := TRUE; Codes := '';
RootFields(Parent:=1,ErrorObject:=FALSE,Doc:=Doc); IF NOT RootFields.Valid THEN RETURN; END_IF;
t := RootFields.Fields[1]; IF (Doc.Tokens[t].Kind<>4) OR (Doc.Tokens[t].Number<>1) THEN RETURN; END_IF;
t := RootFields.Fields[2]; IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].Text<>GatewayId) THEN RETURN; END_IF;
t := RootFields.Fields[3];
(* Guard range before conversion. TO_LINT rounds and changes max-safe odd integers. *)
IF Doc.Tokens[t].Kind<>4 THEN RETURN; END_IF;
IF NOT ((Doc.Tokens[t].Number>=0) AND (Doc.Tokens[t].Number<=LREAL#9007199254740991.0)) THEN RETURN; END_IF;
IF Doc.Tokens[t].Number<>TO_LREAL(TRUNC_LINT(Doc.Tokens[t].Number)) THEN RETURN; END_IF;
t := RootFields.Fields[4];
IF (Doc.Tokens[t].Kind<>3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF;
MessageId := Doc.Tokens[t].Text; IF NOT NG_ValidId(MessageId) THEN RETURN; END_IF;
t := RootFields.Fields[5]; IF Doc.Tokens[t].Kind<>3 THEN RETURN; END_IF;
IF Doc.Tokens[t].Text='STORED' THEN Stored:=TRUE;
ELSIF Doc.Tokens[t].Text<>'REJECTED' THEN RETURN; END_IF;
n := RootFields.Fields[6]; IF Doc.Tokens[n].Kind<>2 THEN RETURN; END_IF;
e:=n+1; count:=0;
WHILE e<Doc.Tokens[n].NextToken DO
    count:=count+1; IF Stored OR (count>32) THEN RETURN; END_IF;
    ErrorFields(Parent:=e,ErrorObject:=TRUE,Doc:=Doc); IF NOT ErrorFields.Valid THEN RETURN; END_IF;
    t:=ErrorFields.Fields[1]; IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].TextLength>256) THEN RETURN; END_IF;
    code:=Doc.Tokens[t].Text; wire:=NG_WireCode(code,FALSE); IF wire<>code THEN RETURN; END_IF;
    IF (code<>'UNKNOWN_CONFIG_VERSION') AND (code<>'RESOURCE_LIMIT') AND (code<>'STORAGE_ERROR') THEN Retryable:=FALSE; END_IF;
    IF LEN(Codes)<200 THEN IF Codes<>'' THEN Codes:=CONCAT(Codes,','); END_IF; Codes:=CONCAT(Codes,code); END_IF;
    t:=ErrorFields.Fields[2]; IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].TextLength>512) THEN RETURN; END_IF;
    IF (Doc.Tokens[t].Text<>'') AND (LEFT(Doc.Tokens[t].Text,1)<>'/') THEN RETURN; END_IF;
    t:=ErrorFields.Fields[3]; IF (Doc.Tokens[t].Kind<>3) OR (Doc.Tokens[t].TextLength<1) OR (Doc.Tokens[t].TextLength>256) THEN RETURN; END_IF;
    t:=ErrorFields.Fields[4];
    IF t>0 THEN IF (Doc.Tokens[t].Kind<>3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF; wire:=Doc.Tokens[t].Text; IF NOT NG_ValidId(wire) THEN RETURN; END_IF; END_IF;
    t:=ErrorFields.Fields[5];
    IF t>0 THEN IF (Doc.Tokens[t].Kind<>3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF; wire:=Doc.Tokens[t].Text; IF NOT NG_ValidId(wire) THEN RETURN; END_IF; END_IF;
    e:=Doc.Tokens[e].NextToken;
END_WHILE;
IF NOT Stored AND (count=0) THEN RETURN; END_IF;
Valid:=TRUE;
END_FUNCTION_BLOCK
