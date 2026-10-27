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
    Core : NG_SourceResultCore;
END_VAR
(* Bind each bounded source/sample/deadline once for the final physical result. *)
Accepted:=FALSE;
IF (Index<1) OR (Index>320) THEN RETURN; END_IF;
Core(Index:=Index,Value:=Value,Quality:=Quality,NowMs:=NowMs,UnixMs:=UnixMs,NominalDueMs:=NominalDueMs,ConfigSlot:=ConfigSlot,ConfigGeneration:=ConfigGeneration,SamplingGeneration:=SamplingGeneration,Cursor:=Buffer.Cursors[Index],Sample:=Samples[Index],StaleDue:=Buffer.SourceStaleDue[Index],Buffer:=Buffer);
Accepted:=Core.Accepted;
END_FUNCTION_BLOCK
