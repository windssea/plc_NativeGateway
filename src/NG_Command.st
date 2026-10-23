FUNCTION_BLOCK NG_Command
VAR_INPUT
    Execute : BOOL;
    IsPatch : BOOL;
    Retained : BOOL;
    GatewayId : NG_Id;
END_VAR
VAR_IN_OUT
    Doc : NG_Document;
    Active : NG_Config;
END_VAR
VAR_OUTPUT
    Done : BOOL;
    Candidate : NG_Config;
    ErrorCode : NG_Text;
    RequestId : NG_Id;
    RequestVersion : ULINT;
END_VAR
VAR
    ReadConfig : NG_ReadConfig;
    ReadDevice : NG_ReadDevice;
    Change : NG_EditDevice;
    NewDevice : NG_Device;
    NewPoints : ARRAY[1..32] OF NG_Point;
    Prev : BOOL;
    n : INT;
    t : INT;
    a : INT;
    g : INT;
    r : INT;
    op : INT;
    dev : INT;
    d : INT;
    i : INT;
    count : INT;
    id : NG_Id;
    mode : STRING[16];
    seen : ARRAY[1..50] OF NG_Id;
END_VAR
IF NOT Execute THEN Done := FALSE; Prev := FALSE; RETURN; END_IF;
IF Prev THEN RETURN; END_IF;
Prev := TRUE; Done := TRUE; ErrorCode := 'SCHEMA_INVALID'; RequestId := ''; RequestVersion := 0;
IF IsPatch THEN
    IF NOT NG_Allowed(1,'|schemaVersion|gatewayId|timestamp|messageId|configVersion|baseConfigVersion|baseMessageId|operations|gateway|',Doc) THEN RETURN; END_IF;
ELSE
    IF NOT NG_Allowed(1,'|schemaVersion|gatewayId|timestamp|messageId|configVersion|config|',Doc) THEN RETURN; END_IF;
END_IF;
t := NG_Member(1,'messageId',Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF;
RequestId := Doc.Tokens[t].Text;
IF NOT NG_ValidId(RequestId) THEN RequestId := ''; RETURN; END_IF;
t := NG_Member(1,'configVersion',Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < 1) OR (Doc.Tokens[t].Number > LREAL#9007199254740991.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN RETURN; END_IF;
RequestVersion := TO_ULINT(Doc.Tokens[t].Number);
t := NG_Member(1,'schemaVersion',Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number <> 1) THEN RETURN; END_IF;
t := NG_Member(1,'gatewayId',Doc);
IF (Doc.Tokens[t].Kind <> 3) OR (Doc.Tokens[t].Text <> GatewayId) THEN ErrorCode := 'GATEWAY_MISMATCH'; RETURN; END_IF;
t := NG_Member(1,'timestamp',Doc);
IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < 0) OR (Doc.Tokens[t].Number > LREAL#9007199254740991.0) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN RETURN; END_IF;
(* Version/replay checks run before this FB in the coordinator. *)
IF NOT IsPatch THEN
    n := NG_Member(1,'config',Doc);
    ReadConfig(Node := n, Doc := Doc, Config := Candidate);
    ErrorCode := ReadConfig.ErrorText;
ELSE
    IF Retained THEN ErrorCode := 'RETAINED_PATCH'; RETURN; END_IF;
    t := NG_Member(1,'baseConfigVersion',Doc);
    IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number <> TO_LREAL(Active.Version)) THEN ErrorCode := 'BASE_CONFIG_MISMATCH'; RETURN; END_IF;
    t := NG_Member(1,'baseMessageId',Doc);
    IF Active.Version = 0 THEN
        IF Doc.Tokens[t].Kind <> 6 THEN ErrorCode := 'BASE_CONFIG_MISMATCH'; RETURN; END_IF;
    ELSIF (Doc.Tokens[t].Kind <> 3) OR (Doc.Tokens[t].Text <> Active.MessageId) THEN ErrorCode := 'BASE_CONFIG_MISMATCH'; RETURN;
    END_IF;
    IF RequestVersion <= Active.Version THEN ErrorCode := 'STALE_VERSION'; RETURN; END_IF;
    Candidate := Active;
    g := NG_Member(1,'gateway',Doc);
    IF g > 0 THEN
        IF NOT NG_Allowed(g,'|enabled|report|',Doc) THEN RETURN; END_IF;
        t := NG_Member(g,'enabled',Doc);
        IF t > 0 THEN
            IF Doc.Tokens[t].Kind <> 5 THEN RETURN; END_IF;
            Candidate.enabled := Doc.Tokens[t].Text = 'true';
        ELSIF Active.Version = 0 THEN RETURN; END_IF;
        r := NG_Member(g,'report',Doc);
        IF r > 0 THEN
            IF NOT NG_Allowed(r,'|batchIntervalMs|maxBatchPoints|',Doc) THEN RETURN; END_IF;
            t := NG_Member(r,'batchIntervalMs',Doc);
            IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < 1) OR (Doc.Tokens[t].Number > 86400000) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN RETURN; END_IF;
            Candidate.batchIntervalMs := TO_UDINT(Doc.Tokens[t].Number);
            t := NG_Member(r,'maxBatchPoints',Doc);
            IF (Doc.Tokens[t].Kind <> 4) OR (Doc.Tokens[t].Number < 1) OR (Doc.Tokens[t].Number > 500) OR (Doc.Tokens[t].Number <> TO_LREAL(TO_LINT(Doc.Tokens[t].Number))) THEN RETURN; END_IF;
            Candidate.maxBatchPoints := TO_UINT(Doc.Tokens[t].Number);
        ELSIF Active.Version = 0 THEN RETURN; END_IF;
    ELSIF Active.Version = 0 THEN RETURN;
    END_IF;
    a := NG_Member(1,'operations',Doc);
    IF Doc.Tokens[a].Kind <> 2 THEN RETURN; END_IF;
    IF (Doc.Tokens[a].NextToken = a+1) AND ((g = 0) OR (Doc.Tokens[g].NextToken = g+1)) THEN RETURN; END_IF;
    op := a+1; count := 0;
    WHILE op < Doc.Tokens[a].NextToken DO
        IF count >= 50 THEN ErrorCode := 'POINT_LIMIT_EXCEEDED'; RETURN; END_IF;
        IF NOT NG_Allowed(op,'|op|deviceId|device|',Doc) THEN RETURN; END_IF;
        t := NG_Member(op,'deviceId',Doc);
        IF (Doc.Tokens[t].Kind <> 3) OR (LEN(Doc.Tokens[t].Text)>64) THEN RETURN; END_IF;
        id := Doc.Tokens[t].Text;
        IF NOT NG_ValidId(id) THEN RETURN; END_IF;
        FOR i := 1 TO count DO IF seen[i] = id THEN ErrorCode := 'OPERATION_CONFLICT'; RETURN; END_IF; END_FOR;
        count := count+1; seen[count] := id;
        t := NG_Member(op,'op',Doc);
        IF Doc.Tokens[t].Kind <> 3 THEN RETURN; END_IF;
        mode := Doc.Tokens[t].Text; d := 0;
        FOR i := 1 TO Candidate.DeviceCount DO IF Candidate.Devices[i].deviceId = id THEN d := i; EXIT; END_IF; END_FOR;
        IF mode = 'add' THEN
            IF d > 0 THEN ErrorCode := 'DEVICE_EXISTS'; RETURN; END_IF;
            IF Candidate.DeviceCount >= 50 THEN ErrorCode := 'POINT_LIMIT_EXCEEDED'; RETURN; END_IF;
            d := Candidate.DeviceCount+1;
        ELSIF (mode = 'replace') OR (mode = 'remove') THEN
            IF d = 0 THEN ErrorCode := 'DEVICE_NOT_FOUND'; RETURN; END_IF;
        ELSE RETURN; END_IF;
        dev := NG_Member(op,'device',Doc);
        IF mode = 'remove' THEN
            IF dev <> 0 THEN RETURN; END_IF;
            Change(DeviceIndex := d, Remove := TRUE, Replacement := NewDevice, Config := Candidate, Points := NewPoints);
            IF Change.ErrorText <> '' THEN ErrorCode := Change.ErrorText; RETURN; END_IF;
        ELSE
            ReadDevice(Node := dev, Doc := Doc, Device := NewDevice, Points := NewPoints);
            ErrorCode := ReadDevice.ErrorText;
            IF ErrorCode <> '' THEN RETURN; END_IF;
            ErrorCode := 'SCHEMA_INVALID';
            IF NewDevice.deviceId <> id THEN ErrorCode := 'OPERATION_CONFLICT'; RETURN; END_IF;
        END_IF;
        IF mode <> 'remove' THEN
            Change(DeviceIndex := d, Remove := FALSE, Replacement := NewDevice, Config := Candidate, Points := NewPoints);
            IF Change.ErrorText <> '' THEN ErrorCode := Change.ErrorText; RETURN; END_IF;
        END_IF;
        op := Doc.Tokens[op].NextToken;
    END_WHILE;
    ErrorCode := NG_CheckConfig(Candidate);
END_IF;
Candidate.Version := RequestVersion; Candidate.MessageId := RequestId;
END_FUNCTION_BLOCK
