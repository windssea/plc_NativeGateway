FUNCTION_BLOCK NG_SourceStateCore
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
    Cursor : NG_SourceCursor;
    Sample : NG_Sample;
    Buffer : NG_Buffer;
END_VAR
VAR
    Capture : NG_CaptureCore;
    start : ULINT;
END_VAR

Accepted:=FALSE;
IF (Index<1) OR (Index>320) THEN RETURN; END_IF;
IF NOT Enabled THEN Cursor.Enabled:=FALSE; Buffer.SourceStaleDue[Index]:=0; RETURN; END_IF;
IF (Cursor.Generation<>Buffer.SamplingGeneration) OR NOT Cursor.Enabled THEN
    Cursor.Generation:=Buffer.SamplingGeneration; Cursor.Enabled:=TRUE;
    Cursor.ActivatedMonoMs:=NowMs; Cursor.LastPhysicalMonoMs:=0;
    Cursor.HasPhysical:=FALSE; Cursor.HasPhysicalUtc:=FALSE;
    Cursor.NextDueMonoMs:=NowMs; Cursor.Quality:=1;
    Buffer.SourceStaleDue[Index]:=NowMs+TO_ULINT(StaleAfterMs);
    IF Buffer.SourceStaleDue[Index]<Buffer.StaleCheckAt THEN Buffer.StaleCheckAt:=Buffer.SourceStaleDue[Index]; END_IF;
    Sample.Quality:='UNKNOWN'; Sample.Timestamp:=UnixMs; Sample.Fresh:=TRUE;
    Sample.NextPollMs:=NowMs;
    Capture(PointIndex:=Index, Kind:=USINT#2, Quality:=USINT#1, Value:=LREAL#0.0, NowMs:=NowMs, NominalDueMs:=ULINT#0, SystemUtcMs:=UnixMs, Cursor:=Cursor, Buffer:=Buffer);
    Accepted:=Capture.Accepted;
END_IF;
IF NOT CheckStale THEN RETURN; END_IF;
start:=Cursor.ActivatedMonoMs;
IF Cursor.HasPhysical THEN start:=Cursor.LastPhysicalMonoMs; END_IF;
IF (NowMs>=start) AND (NowMs-start>=TO_ULINT(StaleAfterMs)) AND (Cursor.Quality<>3) THEN
    Cursor.Quality:=3; Sample.Quality:='STALE';
    Buffer.SourceStaleDue[Index]:=0;
    Sample.Timestamp:=UnixMs; Sample.Fresh:=TRUE;
    Capture(PointIndex:=Index, Kind:=USINT#2, Quality:=USINT#3, Value:=LREAL#0.0, NowMs:=NowMs, NominalDueMs:=ULINT#0, SystemUtcMs:=UnixMs, Cursor:=Cursor, Buffer:=Buffer);
    Accepted:=Capture.Accepted;
END_IF;
END_FUNCTION_BLOCK
