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
    Core : NG_SourceStateCore;
END_VAR
(* Bind each bounded source/sample reference once. Repeated field updates in
   Core avoid dozens of generated array-bound helper calls per activation. *)
Accepted:=FALSE;
IF (Index<1) OR (Index>320) THEN RETURN; END_IF;
Core(Index:=Index,Enabled:=Enabled,NowMs:=NowMs,UnixMs:=UnixMs,
    StaleAfterMs:=StaleAfterMs,CheckStale:=CheckStale,
    Cursor:=Buffer.Cursors[Index],Sample:=Samples[Index],Buffer:=Buffer);
Accepted:=Core.Accepted;
END_FUNCTION_BLOCK
