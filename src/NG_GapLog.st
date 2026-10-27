FUNCTION_BLOCK NG_GapLog
VAR_INPUT
    Reason : USINT; (* 1 overflow,2 version,4 time,5 capacity,6 age,7 corrupt *)
    Outcome : USINT;
END_VAR
VAR_IN_OUT
    Event : NG_CaptureEvent;
    Buffer : NG_Buffer;
END_VAR
VAR
    s : UINT;
    p : UINT;
    d : INT;
END_VAR
s:=Event.ConfigSlot; p:=Event.PointIndex;
Buffer.GapRecordsTotal:=NG_SafeAdd(Buffer.GapRecordsTotal,ULINT#1);
Buffer.GapIndex:=Buffer.GapIndex MOD 64+1;
IF Buffer.GapRecordsTotal>64 THEN Buffer.DetailTruncated:=TRUE; END_IF;
Buffer.Gaps[Buffer.GapIndex].SampleSeq:=Event.SampleSeq;
Buffer.Gaps[Buffer.GapIndex].CompletedMonoMs:=Event.CompletedMonoMs;
Buffer.Gaps[Buffer.GapIndex].Reason:=Reason;
Buffer.Gaps[Buffer.GapIndex].Outcome:=Outcome;
IF Outcome=0 THEN
    Buffer.Gaps[Buffer.GapIndex].Outcome:=2;
    IF (Reason=1) OR (Reason=2) THEN Buffer.Gaps[Buffer.GapIndex].Outcome:=5; END_IF;
END_IF;
Buffer.Gaps[Buffer.GapIndex].CapturedUtcMs:=Event.CapturedUtcMs;
Buffer.Gaps[Buffer.GapIndex].Flags:=Event.Flags;
Buffer.Gaps[Buffer.GapIndex].ConfigVersion:=Buffer.Configs[s].Config.Version;
Buffer.Gaps[Buffer.GapIndex].GatewayId:=Buffer.Configs[s].GatewayId;
Buffer.Gaps[Buffer.GapIndex].CaptureBootId:=Buffer.Configs[s].CaptureBootId;
Buffer.Gaps[Buffer.GapIndex].PointId:=Buffer.Configs[s].Config.Points[p].pointId;
Buffer.Gaps[Buffer.GapIndex].DeviceId:='';
FOR d:=1 TO Buffer.Configs[s].Config.DeviceCount DO
    IF (p>=TO_UINT(Buffer.Configs[s].Config.Devices[d].PointStart)) AND
       (p<TO_UINT(Buffer.Configs[s].Config.Devices[d].PointStart+Buffer.Configs[s].Config.Devices[d].PointCount)) THEN
        Buffer.Gaps[Buffer.GapIndex].DeviceId:=Buffer.Configs[s].Config.Devices[d].deviceId; EXIT;
    END_IF;
END_FOR;
END_FUNCTION_BLOCK
