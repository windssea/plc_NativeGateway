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
    Core : NG_CaptureCore;
END_VAR
(* Validate the index before binding the cursor reference. *)
Accepted:=FALSE;
IF Buffer.CaptureStopped OR NOT Buffer.LayoutValid OR (Buffer.ActiveSlot=0) OR (Buffer.ActiveSlot>4) THEN RETURN; END_IF;
IF (PointIndex<1) OR (PointIndex>320) THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
Core(PointIndex:=PointIndex,Kind:=Kind,Quality:=Quality,Value:=Value,NowMs:=NowMs,NominalDueMs:=NominalDueMs,SystemUtcMs:=SystemUtcMs,Cursor:=Buffer.Cursors[PointIndex],Buffer:=Buffer);
Accepted:=Core.Accepted;
END_FUNCTION_BLOCK
