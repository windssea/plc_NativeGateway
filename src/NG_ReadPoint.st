FUNCTION_BLOCK NG_ReadPoint
VAR_INPUT
    Node : INT;
END_VAR
VAR_IN_OUT
    Doc : NG_Document;
    Point : NG_Point;
END_VAR
VAR_OUTPUT
    ErrorText : NG_Text;
END_VAR
VAR
    t : INT;
    mb : INT;
END_VAR
ErrorText := '';
IF NOT NG_Allowed(Node,'|pointId|name|enabled|dataType|pollIntervalMs|scale|offset|unit|reportMode|reportIntervalMs|deadband|staleAfterMs|modbus|',Doc) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
t := NG_Member(Node, 'pointId', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 64) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.pointId := Doc.Tokens[t].Text;
t := NG_Member(Node, 'name', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 128) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.name := Doc.Tokens[t].Text;
t := NG_Member(Node, 'enabled', Doc);
IF (Doc.Tokens[t].Kind <> 5) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.enabled := (Doc.Tokens[t].Text = 'true');
t := NG_Member(Node, 'dataType', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 16) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.dataType := Doc.Tokens[t].Text;
t := NG_Member(Node, 'pollIntervalMs', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#1.0) OR (Doc.Tokens[t].Number > LREAL#86400000.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.pollIntervalMs := TO_UDINT(Doc.Tokens[t].Number);
t := NG_Member(Node, 'scale', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#-1.0E+100) OR (Doc.Tokens[t].Number > LREAL#1.0E+100) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.scale := Doc.Tokens[t].Number;
t := NG_Member(Node, 'offset', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#-1.0E+100) OR (Doc.Tokens[t].Number > LREAL#1.0E+100) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.offset := Doc.Tokens[t].Number;
t := NG_Member(Node, 'unit', Doc);
IF t > 0 THEN
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 0) OR (LEN(Doc.Tokens[t].Text) > 32) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.unit := Doc.Tokens[t].Text;
ELSE Point.unit := ''; END_IF;
t := NG_Member(Node, 'reportMode', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 24) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.reportMode := Doc.Tokens[t].Text;
t := NG_Member(Node, 'reportIntervalMs', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#1.0) OR (Doc.Tokens[t].Number > LREAL#86400000.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.reportIntervalMs := TO_UDINT(Doc.Tokens[t].Number);
t := NG_Member(Node, 'deadband', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#0.0) OR (Doc.Tokens[t].Number > LREAL#1.0E+100) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.deadband := Doc.Tokens[t].Number;
t := NG_Member(Node, 'staleAfterMs', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#1.0) OR (Doc.Tokens[t].Number > LREAL#86400000.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.staleAfterMs := TO_UDINT(Doc.Tokens[t].Number);
mb := NG_Member(Node,'modbus',Doc);
IF NOT NG_Allowed(mb,'|area|address|byteOrder|',Doc) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
t := NG_Member(mb, 'area', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 24) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.area := Doc.Tokens[t].Text;
t := NG_Member(mb, 'address', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#0.0) OR (Doc.Tokens[t].Number > LREAL#65535.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.address := TO_UINT(Doc.Tokens[t].Number);
t := NG_Member(mb, 'byteOrder', Doc);
IF t > 0 THEN
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 0) OR (LEN(Doc.Tokens[t].Text) > 4) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Point.byteOrder := Doc.Tokens[t].Text;
ELSE Point.byteOrder := ''; END_IF;
END_FUNCTION_BLOCK
