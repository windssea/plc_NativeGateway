FUNCTION_BLOCK NG_SourceResult
VAR_INPUT
    Index : UINT;
    Value : LREAL;
    Quality : STRING[24];
    NowMs : ULINT;
    UnixMs : ULINT;
    NominalDueMs : ULINT;
    ConfigSlot : UINT;
    ConfigGeneration : UDINT;
    SamplingGeneration : ULINT;
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
    code : USINT;
    text : STRING[24];
END_VAR
Accepted:=FALSE;
IF (Index<1) OR (Index>320) OR (ConfigSlot=0) OR (ConfigSlot>4) THEN RETURN; END_IF;
IF (ConfigSlot<>Buffer.ActiveSlot) OR (Buffer.Configs[ConfigSlot].Generation<>ConfigGeneration) OR
   (Buffer.SamplingGeneration<>SamplingGeneration) OR NOT Buffer.Cursors[Index].Enabled THEN
    Buffer.CancelledReadsTotal:=NG_SafeAdd(Buffer.CancelledReadsTotal,ULINT#1);
    Buffer.CancellationReason:=2; RETURN;
END_IF;
IF NowMs<NominalDueMs THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
text:=Quality;
IF (text='GOOD') AND NOT (ABS(Value)<=LREAL#1.7976931348623157E308) THEN text:='BAD_DECODE'; END_IF;
code:=NG_QualityCode(text);
Capture(PointIndex:=Index, Kind:=USINT#1, Quality:=code, Value:=Value, NowMs:=NowMs, NominalDueMs:=NominalDueMs, SystemUtcMs:=UnixMs, Buffer:=Buffer);
    Accepted:=Capture.Accepted;
Buffer.Cursors[Index].LastPhysicalMonoMs:=NowMs; Buffer.Cursors[Index].HasPhysical:=TRUE;
Buffer.Cursors[Index].Quality:=code;
Samples[Index].Quality:=text; Samples[Index].Timestamp:=UnixMs; Samples[Index].Fresh:=TRUE;
IF text='GOOD' THEN Samples[Index].Value:=Value; Samples[Index].LastGoodMs:=NowMs; END_IF;
Samples[Index].NextPollMs:=Buffer.Cursors[Index].NextDueMonoMs;
END_FUNCTION_BLOCK
