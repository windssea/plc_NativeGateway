FUNCTION_BLOCK NG_SourceResultCore
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
    Cursor : NG_SourceCursor;
    Sample : NG_Sample;
    StaleDue : ULINT;
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
   (Buffer.SamplingGeneration<>SamplingGeneration) OR NOT Cursor.Enabled THEN
    Buffer.CancelledReadsTotal:=NG_SafeAdd(Buffer.CancelledReadsTotal,ULINT#1);
    Buffer.CancellationReason:=2; RETURN;
END_IF;
IF NowMs<NominalDueMs THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
text:=Quality;
IF (text='GOOD') AND NOT (ABS(Value)<=LREAL#1.7976931348623157E308) THEN text:='BAD_DECODE'; END_IF;
code:=NG_QualityCode(text);
Capture(PointIndex:=Index, Kind:=USINT#1, Quality:=code, Value:=Value, NowMs:=NowMs, NominalDueMs:=NominalDueMs, SystemUtcMs:=UnixMs, Buffer:=Buffer);
    Accepted:=Capture.Accepted;
Cursor.LastPhysicalMonoMs:=NowMs; Cursor.HasPhysical:=TRUE;
Cursor.Quality:=code;
(* A final result extends this source's liveness. Keeping an earlier global
   deadline is safe; the due sweep recomputes the minimum before emitting stale. *)
StaleDue:=0;
IF code<>3 THEN
    StaleDue:=NowMs+TO_ULINT(Buffer.Configs[ConfigSlot].Config.Points[Index].staleAfterMs);
    IF StaleDue<Buffer.StaleCheckAt THEN Buffer.StaleCheckAt:=StaleDue; END_IF;
END_IF;
Sample.Quality:=text; Sample.Timestamp:=UnixMs; Sample.Fresh:=TRUE;
IF text='GOOD' THEN Sample.Value:=Value; Sample.LastGoodMs:=NowMs; END_IF;
Sample.NextPollMs:=Cursor.NextDueMonoMs;
END_FUNCTION_BLOCK
