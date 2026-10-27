FUNCTION_BLOCK NG_PruneTerminal
VAR_INPUT
    Index : UINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    Free : NG_FreeRecord;
    j : UINT;
    r : UINT;
    offset : UINT;
END_VAR
IF (Index=0) OR (Index>64) THEN RETURN; END_IF;
IF Buffer.TerminalOwners[Index].Count=0 THEN RETURN; END_IF;
offset:=(Index-1)*64;
FOR j:=1 TO Buffer.TerminalOwners[Index].Count DO
    r:=Buffer.TerminalRefs[offset+j];
    IF r=0 THEN Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; RETURN; END_IF;
    IF (Buffer.RecordGenerations[r]<>Buffer.TerminalRefGenerations[offset+j]) OR (Buffer.RecordStates[r]=0) THEN
        Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; RETURN;
    END_IF;
END_FOR;
FOR j:=1 TO Buffer.TerminalOwners[Index].Count DO
    r:=Buffer.TerminalRefs[offset+j];
    IF (r<>0) AND (Buffer.RecordGenerations[r]=Buffer.TerminalRefGenerations[offset+j]) THEN Free(Index:=r,Buffer:=Buffer);
    ELSE Buffer.CaptureStopped:=TRUE; END_IF;
    Buffer.TerminalRefs[offset+j]:=0;
END_FOR;
Buffer.TerminalOwners[Index].Count:=0; Buffer.TerminalOwners[Index].MessageId:='';
Buffer.TombstonePrunedBatchesTotal:=NG_SafeAdd(Buffer.TombstonePrunedBatchesTotal,ULINT#1);
Buffer.DetailTruncated:=TRUE;
END_FUNCTION_BLOCK
