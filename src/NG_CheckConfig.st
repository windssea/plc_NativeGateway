FUNCTION NG_CheckConfig : NG_Text
VAR_INPUT
    Config : NG_Config;
END_VAR
VAR
    d : INT;
    p : INT;
    i : INT;
    width : UDINT;
    point : NG_Point;
END_VAR
NG_CheckConfig := 'SCHEMA_INVALID';
IF (Config.PointCount < 0) OR (Config.PointCount > 320) THEN RETURN; END_IF;
IF (Config.DeviceCount < 0) OR (Config.DeviceCount > 50) OR (Config.batchIntervalMs < 1) OR (Config.batchIntervalMs > 86400000) OR (Config.maxBatchPoints < 1) OR (Config.maxBatchPoints > 500) THEN RETURN; END_IF;
FOR d := 1 TO Config.DeviceCount DO
    IF NOT NG_ValidId(Config.Devices[d].deviceId) THEN RETURN; END_IF;
    FOR i := 1 TO d-1 DO
        IF Config.Devices[d].deviceId = Config.Devices[i].deviceId THEN NG_CheckConfig := 'DUPLICATE_DEVICE_ID'; RETURN; END_IF;
    END_FOR;
    IF NOT NG_IPv4(Config.Devices[d].host) THEN NG_CheckConfig := 'BAD_CONFIGURATION'; RETURN; END_IF;
    IF (Config.Devices[d].port = 0) OR (Config.Devices[d].PointCount < 0) OR (Config.Devices[d].PointCount > 32) THEN RETURN; END_IF;
    IF (Config.Devices[d].connectTimeoutMs < 1) OR (Config.Devices[d].connectTimeoutMs > 300000) OR (Config.Devices[d].requestTimeoutMs < 1) OR (Config.Devices[d].requestTimeoutMs > 300000) OR (Config.Devices[d].retryCount > 10) THEN RETURN; END_IF;
    FOR p := 1 TO Config.Devices[d].PointCount DO
        point := Config.Points[Config.Devices[d].PointStart+p-1];
        IF NOT NG_ValidId(point.pointId) THEN RETURN; END_IF;
        FOR i := 1 TO p-1 DO
            IF point.pointId = Config.Points[Config.Devices[d].PointStart+i-1].pointId THEN NG_CheckConfig := 'DUPLICATE_POINT_ID'; RETURN; END_IF;
        END_FOR;
        IF (point.pollIntervalMs < 1) OR (point.pollIntervalMs > 86400000) OR (point.reportIntervalMs < 1) OR (point.reportIntervalMs > 86400000) OR (point.staleAfterMs > 86400000) OR (point.deadband < 0) THEN RETURN; END_IF;
        IF point.staleAfterMs < point.pollIntervalMs THEN NG_CheckConfig := 'INVALID_STALE_INTERVAL'; RETURN; END_IF;
        IF (point.reportMode <> 'cyclic') AND (point.reportMode <> 'change') AND (point.reportMode <> 'change_or_cyclic') THEN RETURN; END_IF;
        IF point.dataType = 'bool' THEN
            width := 1;
            IF (point.area <> 'coil') AND (point.area <> 'discrete_input') THEN RETURN; END_IF;
            IF (point.byteOrder <> '') OR (point.scale <> 1) OR (point.offset <> 0) OR (point.deadband <> 0) THEN RETURN; END_IF;
        ELSE
            IF (point.area <> 'holding_register') AND (point.area <> 'input_register') THEN RETURN; END_IF;
            IF (point.dataType = 'uint16') OR (point.dataType = 'int16') THEN
                width := 1;
                IF (point.byteOrder <> 'AB') AND (point.byteOrder <> 'BA') THEN RETURN; END_IF;
            ELSIF (point.dataType = 'uint32') OR (point.dataType = 'int32') OR (point.dataType = 'float32') THEN
                width := 2;
                IF (point.byteOrder <> 'ABCD') AND (point.byteOrder <> 'BADC') AND (point.byteOrder <> 'CDAB') AND (point.byteOrder <> 'DCBA') THEN RETURN; END_IF;
            ELSE RETURN;
            END_IF;
        END_IF;
        IF TO_UDINT(point.address) + width > 65536 THEN NG_CheckConfig := 'INVALID_ADDRESS'; RETURN; END_IF;
    END_FOR;
END_FOR;
NG_CheckConfig := '';
END_FUNCTION
