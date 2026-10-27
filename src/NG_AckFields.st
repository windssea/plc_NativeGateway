FUNCTION_BLOCK NG_AckFields
VAR_INPUT
    Parent : INT;
    ErrorObject : BOOL;
END_VAR
VAR_IN_OUT
    Doc : NG_Document;
END_VAR
VAR_OUTPUT
    Valid : BOOL;
    Fields : ARRAY[1..6] OF INT;
END_VAR
VAR
    i : INT;
    j : INT;
    field : INT;
    count : INT;
END_VAR
(* A bounded, reference-based index for the two ACK object shapes. It keeps
   the full document out of FUNCTION VAR_INPUT argument copies. *)
Valid:=FALSE; FOR j:=1 TO 6 DO Fields[j]:=0; END_FOR;
IF (Parent<1) OR (Parent>Doc.Count) THEN RETURN; END_IF;
IF Doc.Tokens[Parent].Kind<>1 THEN RETURN; END_IF;
i:=Parent+1; count:=0;
WHILE i<Doc.Tokens[Parent].NextToken DO
    count:=count+1; IF count>6 THEN RETURN; END_IF;
    IF (i>Doc.Count) OR (i>8192) THEN RETURN; END_IF;
    field:=0;
    IF ErrorObject THEN
        IF Doc.Tokens[i].Key='code' THEN field:=1;
        ELSIF Doc.Tokens[i].Key='path' THEN field:=2;
        ELSIF Doc.Tokens[i].Key='message' THEN field:=3;
        ELSIF Doc.Tokens[i].Key='deviceId' THEN field:=4;
        ELSIF Doc.Tokens[i].Key='pointId' THEN field:=5; END_IF;
    ELSE
        IF Doc.Tokens[i].Key='schemaVersion' THEN field:=1;
        ELSIF Doc.Tokens[i].Key='gatewayId' THEN field:=2;
        ELSIF Doc.Tokens[i].Key='timestamp' THEN field:=3;
        ELSIF Doc.Tokens[i].Key='messageId' THEN field:=4;
        ELSIF Doc.Tokens[i].Key='status' THEN field:=5;
        ELSIF Doc.Tokens[i].Key='errors' THEN field:=6; END_IF;
    END_IF;
    IF field=0 THEN RETURN; END_IF;
    IF Fields[field]<>0 THEN RETURN; END_IF;
    Fields[field]:=i;
    IF (Doc.Tokens[i].NextToken<=i) OR (Doc.Tokens[i].NextToken>Doc.Tokens[Parent].NextToken) THEN RETURN; END_IF;
    i:=Doc.Tokens[i].NextToken;
END_WHILE;
IF i<>Doc.Tokens[Parent].NextToken THEN RETURN; END_IF;
IF ErrorObject THEN
    IF (Fields[1]=0) OR (Fields[2]=0) OR (Fields[3]=0) THEN RETURN; END_IF;
ELSE
    FOR j:=1 TO 6 DO IF Fields[j]=0 THEN RETURN; END_IF; END_FOR;
END_IF;
Valid:=TRUE;
END_FUNCTION_BLOCK
