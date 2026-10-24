FUNCTION_BLOCK NG_Capture
VAR_INPUT
    PointIndex : UINT;
    Kind : USINT;
    Quality : USINT;
    Value : LREAL;
    NowMs : ULINT;
    NominalDueMs : ULINT;
    SystemUtcMs : ULINT;
END_VAR
VAR_OUTPUT
    Accepted : BOOL;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    s : UINT;
    d : INT;
END_VAR
Accepted:=FALSE; s:=Buffer.ActiveSlot;
IF Buffer.CaptureStopped OR NOT Buffer.LayoutValid OR (s=0) OR (s>4) THEN RETURN; END_IF;
IF (PointIndex<1) OR (PointIndex>320) THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
IF (Buffer.NextSampleSeq>=ULINT#9007199254740991) OR (NowMs>ULINT#9007199254740991) THEN
    Buffer.CaptureStopped:=TRUE; RETURN;
END_IF;
Buffer.NextSampleSeq:=Buffer.NextSampleSeq+1;
Buffer.CapturedEventsTotal:=NG_SafeAdd(Buffer.CapturedEventsTotal,ULINT#1);
Buffer.Scratch.SampleSeq:=Buffer.NextSampleSeq; Buffer.Scratch.Value:=0;
IF Quality=2 THEN Buffer.Scratch.Value:=Value; END_IF;
Buffer.Scratch.Kind:=Kind; Buffer.Scratch.Quality:=Quality;
Buffer.Scratch.CompletedMonoMs:=NowMs; Buffer.Scratch.NominalDueMonoMs:=0;
Buffer.Scratch.ConfigSlot:=s; Buffer.Scratch.ConfigGeneration:=Buffer.Configs[s].Generation;
Buffer.Scratch.PointIndex:=PointIndex; Buffer.Scratch.SamplingGeneration:=Buffer.SamplingGeneration;
Buffer.Scratch.ClockRevision:=0; Buffer.Scratch.CapturedUtcMs:=0; Buffer.Scratch.Flags:=WORD#8;
(* Explicit SYSTEM_RTC_COMPAT_UNVERIFIED: trusted UTC/timeValid remain absent. *)
IF (SystemUtcMs>0) AND (SystemUtcMs<=ULINT#9007199254740991) THEN Buffer.Scratch.CapturedUtcMs:=SystemUtcMs; Buffer.Scratch.Flags:=WORD#9; END_IF;
IF Kind=1 THEN
    Buffer.Scratch.NominalDueMonoMs:=NominalDueMs; Buffer.Scratch.Flags:=Buffer.Scratch.Flags OR WORD#4;
    IF Buffer.Cursors[PointIndex].HasPhysicalUtc AND ((Buffer.Scratch.Flags AND WORD#1)<>WORD#0) AND
       (Buffer.Cursors[PointIndex].LastPhysicalUtcMs=SystemUtcMs) THEN
        Buffer.SourceTimestampRepeatTotal:=NG_SafeAdd(Buffer.SourceTimestampRepeatTotal,ULINT#1);
    END_IF;
    Buffer.Cursors[PointIndex].HasPhysicalUtc:=(Buffer.Scratch.Flags AND WORD#1)<>WORD#0;
    Buffer.Cursors[PointIndex].LastPhysicalUtcMs:=SystemUtcMs;
END_IF;
IF Buffer.IngressCount>=512 THEN
    Buffer.CaptureOverflowEventsTotal:=NG_SafeAdd(Buffer.CaptureOverflowEventsTotal,ULINT#1);
    Buffer.UndecidedLostEventsTotal:=NG_SafeAdd(Buffer.UndecidedLostEventsTotal,ULINT#1);
    Buffer.GapIndex:=Buffer.GapIndex MOD 64+1; IF Buffer.CaptureOverflowEventsTotal>64 THEN Buffer.DetailTruncated:=TRUE; END_IF;
    Buffer.Gaps[Buffer.GapIndex].SampleSeq:=Buffer.Scratch.SampleSeq;
    Buffer.Gaps[Buffer.GapIndex].ConfigVersion:=Buffer.Configs[s].Config.Version;
    Buffer.Gaps[Buffer.GapIndex].GatewayId:=Buffer.Configs[s].GatewayId;
    Buffer.Gaps[Buffer.GapIndex].CaptureBootId:=Buffer.Configs[s].CaptureBootId;
    Buffer.Gaps[Buffer.GapIndex].CompletedMonoMs:=NowMs;
    Buffer.Gaps[Buffer.GapIndex].PointId:=Buffer.Configs[s].Config.Points[PointIndex].pointId;
    Buffer.Gaps[Buffer.GapIndex].DeviceId:=''; Buffer.Gaps[Buffer.GapIndex].Reason:=1;
    FOR d:=1 TO Buffer.Configs[s].Config.DeviceCount DO
        IF (PointIndex>=TO_UINT(Buffer.Configs[s].Config.Devices[d].PointStart)) AND
           (PointIndex<TO_UINT(Buffer.Configs[s].Config.Devices[d].PointStart+Buffer.Configs[s].Config.Devices[d].PointCount)) THEN
            Buffer.Gaps[Buffer.GapIndex].DeviceId:=Buffer.Configs[s].Config.Devices[d].deviceId; EXIT;
        END_IF;
    END_FOR;
    RETURN;
END_IF;
Buffer.Ingress[Buffer.Tail]:=Buffer.Scratch; Buffer.Tail:=Buffer.Tail MOD 512+1;
Buffer.IngressCount:=Buffer.IngressCount+1; Buffer.Configs[s].References:=Buffer.Configs[s].References+1;
Accepted:=TRUE;
END_FUNCTION_BLOCK
