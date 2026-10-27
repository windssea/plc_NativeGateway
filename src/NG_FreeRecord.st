FUNCTION_BLOCK NG_FreeRecord
VAR_INPUT
    Index : UINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    s : UINT;
END_VAR
IF (Index=0) OR (Index>Buffer.HighSlot) THEN RETURN; END_IF;
IF Buffer.RecordStates[Index]=0 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
s:=Buffer.Records[Index].ConfigSlot;
IF Buffer.Configs[s].References=0 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
Buffer.Configs[s].References:=Buffer.Configs[s].References-1;
IF Buffer.RecordStates[Index]=4 THEN Buffer.DeadRetainedEvents:=Buffer.DeadRetainedEvents-1; END_IF;
IF Buffer.RecordStates[Index]=3 THEN Buffer.UncertainRetainedEvents:=Buffer.UncertainRetainedEvents-1; END_IF;
Buffer.RecordStates[Index]:=0; Buffer.FreeSlots[Index]:=Buffer.FreeHead;
Buffer.FreeHead:=Index; Buffer.OwnedCount:=Buffer.OwnedCount-1;
END_FUNCTION_BLOCK
