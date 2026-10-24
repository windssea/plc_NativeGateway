FUNCTION_BLOCK NG_SameConfig
VAR_OUTPUT
    Equal : BOOL;
END_VAR
VAR_IN_OUT
    A : NG_Config;
    B : NG_Config;
END_VAR
VAR
    i : INT;
END_VAR
Equal := FALSE;
IF (A.Version<>B.Version) OR (A.MessageId<>B.MessageId) OR (A.enabled<>B.enabled) OR
   (A.batchIntervalMs<>B.batchIntervalMs) OR (A.maxBatchPoints<>B.maxBatchPoints) OR
   (A.DeviceCount<>B.DeviceCount) OR (A.PointCount<>B.PointCount) THEN RETURN; END_IF;
FOR i:=1 TO A.DeviceCount DO
    IF (A.Devices[i].deviceId<>B.Devices[i].deviceId) OR (A.Devices[i].name<>B.Devices[i].name) OR
       (A.Devices[i].enabled<>B.Devices[i].enabled) OR (A.Devices[i].host<>B.Devices[i].host) OR
       (A.Devices[i].port<>B.Devices[i].port) OR (A.Devices[i].unitId<>B.Devices[i].unitId) OR
       (A.Devices[i].connectTimeoutMs<>B.Devices[i].connectTimeoutMs) OR
       (A.Devices[i].requestTimeoutMs<>B.Devices[i].requestTimeoutMs) OR
       (A.Devices[i].retryCount<>B.Devices[i].retryCount) OR
       (A.Devices[i].PointStart<>B.Devices[i].PointStart) OR (A.Devices[i].PointCount<>B.Devices[i].PointCount) THEN RETURN; END_IF;
END_FOR;
FOR i:=1 TO A.PointCount DO
    IF (A.Points[i].pointId<>B.Points[i].pointId) OR (A.Points[i].name<>B.Points[i].name) OR
       (A.Points[i].enabled<>B.Points[i].enabled) OR (A.Points[i].dataType<>B.Points[i].dataType) OR
       (A.Points[i].pollIntervalMs<>B.Points[i].pollIntervalMs) OR (A.Points[i].scale<>B.Points[i].scale) OR
       (A.Points[i].offset<>B.Points[i].offset) OR (A.Points[i].unit<>B.Points[i].unit) OR
       (A.Points[i].reportMode<>B.Points[i].reportMode) OR (A.Points[i].reportIntervalMs<>B.Points[i].reportIntervalMs) OR
       (A.Points[i].deadband<>B.Points[i].deadband) OR (A.Points[i].staleAfterMs<>B.Points[i].staleAfterMs) OR
       (A.Points[i].area<>B.Points[i].area) OR (A.Points[i].address<>B.Points[i].address) OR
       (A.Points[i].byteOrder<>B.Points[i].byteOrder) THEN RETURN; END_IF;
END_FOR;
Equal := TRUE;
END_FUNCTION_BLOCK
