FUNCTION_BLOCK NG_EditDevice
VAR_INPUT
    DeviceIndex : INT;
    Remove : BOOL;
    Replacement : NG_Device;
END_VAR
VAR_IN_OUT
    Config : NG_Config;
    Points : ARRAY[1..32] OF NG_Point;
END_VAR
VAR_OUTPUT
    ErrorText : NG_Text;
END_VAR
VAR
    oldCount : INT;
    newCount : INT;
    start : INT;
    delta : INT;
    i : INT;
    n : INT;
END_VAR
ErrorText := 'SCHEMA_INVALID';
IF (DeviceIndex < 1) OR (DeviceIndex > Config.DeviceCount+1) OR (DeviceIndex > 50) THEN RETURN; END_IF;
oldCount := 0; start := Config.PointCount+1;
IF DeviceIndex <= Config.DeviceCount THEN oldCount := Config.Devices[DeviceIndex].PointCount; start := Config.Devices[DeviceIndex].PointStart; END_IF;
newCount := Replacement.PointCount; IF Remove THEN newCount := 0; END_IF;
delta := newCount-oldCount;
IF (newCount < 0) OR (newCount > 32) OR (Config.PointCount+delta > 320) THEN ErrorText := 'POINT_LIMIT_EXCEEDED'; RETURN; END_IF;
IF delta > 0 THEN
    FOR i := Config.PointCount TO start+oldCount BY -1 DO Config.Points[i+delta] := Config.Points[i]; END_FOR;
ELSIF delta < 0 THEN
    FOR i := start+oldCount TO Config.PointCount DO Config.Points[i+delta] := Config.Points[i]; END_FOR;
END_IF;
Config.PointCount := Config.PointCount+delta;
IF Remove THEN
    IF DeviceIndex > Config.DeviceCount THEN RETURN; END_IF;
    FOR i := DeviceIndex TO Config.DeviceCount-1 DO Config.Devices[i] := Config.Devices[i+1]; END_FOR;
    Config.DeviceCount := Config.DeviceCount-1;
ELSE
    Config.Devices[DeviceIndex] := Replacement;
    IF DeviceIndex > Config.DeviceCount THEN Config.DeviceCount := DeviceIndex; END_IF;
    FOR i := 1 TO newCount DO Config.Points[start+i-1] := Points[i]; END_FOR;
END_IF;
n := 1;
FOR i := 1 TO Config.DeviceCount DO Config.Devices[i].PointStart := n; n := n+Config.Devices[i].PointCount; END_FOR;
ErrorText := '';
END_FUNCTION_BLOCK
