FUNCTION_BLOCK NG_SourceState
VAR_INPUT
    Index : UINT;
    Enabled : BOOL;
    NowMs : ULINT;
    UnixMs : ULINT;
    StaleAfterMs : UDINT;
    CheckStale : BOOL;
END_VAR
VAR_OUTPUT
    Accepted : BOOL;
END_VAR
VAR_IN_OUT
    Samples : ARRAY[1..320] OF NG_Sample;
    Buffer : NG_Buffer;
END_VAR
VAR
    Capture : NG_Capture;
    start : ULINT;
END_VAR
Accepted:=FALSE;
IF (Index<1) OR (Index>320) THEN RETURN; END_IF;
IF NOT Enabled THEN Buffer.Cursors[Index].Enabled:=FALSE; RETURN; END_IF;
IF (Buffer.Cursors[Index].Generation<>Buffer.SamplingGeneration) OR NOT Buffer.Cursors[Index].Enabled THEN
    Buffer.Cursors[Index].Generation:=Buffer.SamplingGeneration; Buffer.Cursors[Index].Enabled:=TRUE;
    Buffer.Cursors[Index].ActivatedMonoMs:=NowMs; Buffer.Cursors[Index].LastPhysicalMonoMs:=0;
    Buffer.Cursors[Index].HasPhysical:=FALSE; Buffer.Cursors[Index].HasPhysicalUtc:=FALSE;
    Buffer.Cursors[Index].NextDueMonoMs:=NowMs; Buffer.Cursors[Index].Quality:=1;
    Samples[Index].Quality:='UNKNOWN'; Samples[Index].Timestamp:=UnixMs; Samples[Index].Fresh:=TRUE;
    Samples[Index].NextPollMs:=NowMs;
    Capture(PointIndex:=Index, Kind:=USINT#2, Quality:=USINT#1, Value:=LREAL#0.0, NowMs:=NowMs, NominalDueMs:=ULINT#0, SystemUtcMs:=UnixMs, Buffer:=Buffer);
    Accepted:=Capture.Accepted;
END_IF;
IF NOT CheckStale THEN RETURN; END_IF;
start:=Buffer.Cursors[Index].ActivatedMonoMs;
IF Buffer.Cursors[Index].HasPhysical THEN start:=Buffer.Cursors[Index].LastPhysicalMonoMs; END_IF;
IF (NowMs>=start) AND (NowMs-start>=TO_ULINT(StaleAfterMs)) AND (Buffer.Cursors[Index].Quality<>3) THEN
    Buffer.Cursors[Index].Quality:=3; Samples[Index].Quality:='STALE';
    Samples[Index].Timestamp:=UnixMs; Samples[Index].Fresh:=TRUE;
    Capture(PointIndex:=Index, Kind:=USINT#2, Quality:=USINT#3, Value:=LREAL#0.0, NowMs:=NowMs, NominalDueMs:=ULINT#0, SystemUtcMs:=UnixMs, Buffer:=Buffer);
    Accepted:=Capture.Accepted;
END_IF;
END_FUNCTION_BLOCK
