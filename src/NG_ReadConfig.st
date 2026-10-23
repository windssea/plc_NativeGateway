FUNCTION_BLOCK NG_ReadConfig
VAR_INPUT
    Node : INT;
END_VAR
VAR_IN_OUT
    Doc : NG_Document;
    Config : NG_Config;
END_VAR
VAR_OUTPUT
    ErrorText : NG_Text;
END_VAR
VAR
    ReadDevice : NG_ReadDevice;
    Change : NG_EditDevice;
    Device : NG_Device;
    Points : ARRAY[1..32] OF NG_Point;
    t : INT;
    a : INT;
    d : INT;
    r : INT;
    err : NG_Text;
END_VAR
ErrorText := 'SCHEMA_INVALID';
IF NOT NG_Allowed(Node,'|enabled|report|devices|',Doc) THEN RETURN; END_IF;
t := NG_Member(Node,'enabled',Doc);
IF Doc.Tokens[t].Kind <> 5 THEN RETURN; END_IF;
Config.enabled := Doc.Tokens[t].Text = 'true';
r := NG_Member(Node,'report',Doc);
IF NOT NG_Allowed(r,'|batchIntervalMs|maxBatchPoints|',Doc) THEN RETURN; END_IF;
t := NG_Member(r,'batchIntervalMs',Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < 1) OR (Doc.Tokens[t].Number > 86400000) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN RETURN; END_IF;
Config.batchIntervalMs := TO_UDINT(Doc.Tokens[t].Number);
t := NG_Member(r,'maxBatchPoints',Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < 1) OR (Doc.Tokens[t].Number > 500) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN RETURN; END_IF;
Config.maxBatchPoints := TO_UINT(Doc.Tokens[t].Number);
a := NG_Member(Node,'devices',Doc);
IF Doc.Tokens[a].Kind <> 2 THEN RETURN; END_IF;
d := a + 1; Config.DeviceCount := 0; Config.PointCount := 0;
WHILE d < Doc.Tokens[a].NextToken DO
    IF Config.DeviceCount >= 50 THEN ErrorText := 'POINT_LIMIT_EXCEEDED'; RETURN; END_IF;
    ReadDevice(Node := d, Doc := Doc, Device := Device, Points := Points);
    err := ReadDevice.ErrorText;
    IF err <> '' THEN ErrorText := err; RETURN; END_IF;
    Change(DeviceIndex := Config.DeviceCount+1, Remove := FALSE, Replacement := Device, Config := Config, Points := Points);
    IF Change.ErrorText <> '' THEN ErrorText := Change.ErrorText; RETURN; END_IF;
    d := Doc.Tokens[d].NextToken;
END_WHILE;
ErrorText := NG_CheckConfig(Config);
END_FUNCTION_BLOCK
