FUNCTION_BLOCK NG_ReadDevice
VAR_INPUT
    Node : INT;
END_VAR
VAR_IN_OUT
    Doc : NG_Document;
    Device : NG_Device;
    Points : ARRAY[1..32] OF NG_Point;
END_VAR
VAR_OUTPUT
    ErrorText : NG_Text;
END_VAR
VAR
    ReadPoint : NG_ReadPoint;
    t : INT;
    conn : INT;
    pointsNode : INT;
    p : INT;
    err : NG_Text;
END_VAR
ErrorText := '';
IF NOT NG_Allowed(Node,'|deviceId|name|enabled|protocol|connection|points|',Doc) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
t := NG_Member(Node, 'deviceId', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 64) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.deviceId := Doc.Tokens[t].Text;
t := NG_Member(Node, 'name', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 128) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.name := Doc.Tokens[t].Text;
t := NG_Member(Node, 'enabled', Doc);
IF (Doc.Tokens[t].Kind <> 5) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.enabled := (Doc.Tokens[t].Text = 'true');
t := NG_Member(Node,'protocol',Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (Doc.Tokens[t].Text <> 'modbus_tcp') THEN ErrorText := 'UNSUPPORTED_PROTOCOL'; RETURN; END_IF;
conn := NG_Member(Node,'connection',Doc);
IF NOT NG_Allowed(conn,'|host|port|unitId|connectTimeoutMs|requestTimeoutMs|retryCount|',Doc) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
t := NG_Member(conn, 'host', Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text) < 1) OR (LEN(Doc.Tokens[t].Text) > 253) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.host := Doc.Tokens[t].Text;
t := NG_Member(conn, 'port', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#1.0) OR (Doc.Tokens[t].Number > LREAL#65535.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.port := TO_UINT(Doc.Tokens[t].Number);
t := NG_Member(conn, 'unitId', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#0.0) OR (Doc.Tokens[t].Number > LREAL#255.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.unitId := TO_USINT(Doc.Tokens[t].Number);
t := NG_Member(conn, 'connectTimeoutMs', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#1.0) OR (Doc.Tokens[t].Number > LREAL#300000.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.connectTimeoutMs := TO_UDINT(Doc.Tokens[t].Number);
t := NG_Member(conn, 'requestTimeoutMs', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#1.0) OR (Doc.Tokens[t].Number > LREAL#300000.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.requestTimeoutMs := TO_UDINT(Doc.Tokens[t].Number);
t := NG_Member(conn, 'retryCount', Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < LREAL#0.0) OR (Doc.Tokens[t].Number > LREAL#10.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.retryCount := TO_USINT(Doc.Tokens[t].Number);
pointsNode := NG_Member(Node,'points',Doc);
IF Doc.Tokens[pointsNode].Kind <> 2 THEN ErrorText := 'SCHEMA_INVALID'; RETURN; END_IF;
Device.PointCount := 0; p := pointsNode + 1;
WHILE p < Doc.Tokens[pointsNode].NextToken DO
    IF Device.PointCount >= 32 THEN ErrorText := 'POINT_LIMIT_EXCEEDED'; RETURN; END_IF;
    Device.PointCount := Device.PointCount + 1;
    ReadPoint(Node := p, Doc := Doc, Point := Points[Device.PointCount]);
    err := ReadPoint.ErrorText;
    IF err <> '' THEN ErrorText := err; RETURN; END_IF;
    p := Doc.Tokens[p].NextToken;
END_WHILE;

END_FUNCTION_BLOCK
