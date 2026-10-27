FUNCTION_BLOCK NG_EndBatch
VAR_INPUT
    Slot : UINT;
    Outcome : USINT; (* 1 STORED,2 known unsent,3 permanent isolated,4 uncertain,5 prune isolated *)
    Reason : USINT;
    NowMs : ULINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
    Packets : ARRAY[1..16] OF NG_Packet;
END_VAR
VAR
    Free : NG_FreeRecord;
    Gap : NG_GapLog;
    Prune : NG_PruneTerminal;
    j : UINT;
    r : UINT;
    offset : UINT;
    terminalOffset : UINT;
    terminal : UINT;
END_VAR
IF (Slot=0) OR (Slot>16) THEN RETURN; END_IF;
IF Buffer.BatchOwners[Slot].State<2 THEN RETURN; END_IF;
IF (Outcome=3) AND (Buffer.BatchOwners[Slot].State=3) THEN RETURN; END_IF;
offset:=(Slot-1)*64; terminal:=0;
(* Validate the whole ownership set before any irreversible counter/release. *)
FOR j:=1 TO Buffer.BatchOwners[Slot].Count DO
    r:=Buffer.BatchRefs[offset+j];
    IF r=0 THEN Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; RETURN; END_IF;
    IF (Buffer.RecordGenerations[r]<>Buffer.BatchRefGenerations[offset+j]) OR (Buffer.RecordStates[r]=0) THEN
        Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; RETURN;
    END_IF;
END_FOR;
IF Outcome=1 THEN Buffer.StoredBatchesTotal:=NG_SafeAdd(Buffer.StoredBatchesTotal,ULINT#1); END_IF;
IF (Outcome=4) OR (Outcome=5) THEN
    Buffer.TerminalIndex:=Buffer.TerminalIndex MOD 64+1; terminal:=Buffer.TerminalIndex;
    Prune(Index:=terminal,Buffer:=Buffer); terminalOffset:=(terminal-1)*64;
    Buffer.TerminalOwners[terminal].MessageId:=Packets[Slot].MessageId;
    Buffer.TerminalOwners[terminal].Digest:=Buffer.BatchOwners[Slot].Digest;
    Buffer.TerminalOwners[terminal].BatchGeneration:=Buffer.BatchGenerations[Slot];
    Buffer.TerminalOwners[terminal].Count:=Buffer.BatchOwners[Slot].Count;
    Buffer.TerminalOwners[terminal].FirstSeq:=Buffer.BatchOwners[Slot].OrderSeq;
    Buffer.TerminalOwners[terminal].CreatedMs:=NowMs;
    Buffer.TerminalOwners[terminal].Outcome:=1;
    IF Outcome=5 THEN Buffer.TerminalOwners[terminal].Outcome:=2;
        Buffer.DeadPrunedBatchesTotal:=NG_SafeAdd(Buffer.DeadPrunedBatchesTotal,ULINT#1); END_IF;
END_IF;
FOR j:=1 TO Buffer.BatchOwners[Slot].Count DO
    r:=Buffer.BatchRefs[offset+j];
    IF (r=0) OR (Buffer.RecordGenerations[r]<>Buffer.BatchRefGenerations[offset+j]) THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
    CASE Outcome OF
    1: Buffer.StoredConfirmedEventsTotal:=NG_SafeAdd(Buffer.StoredConfirmedEventsTotal,ULINT#1); Free(Index:=r,Buffer:=Buffer);
    2: Buffer.KnownUnsentEventsTotal:=NG_SafeAdd(Buffer.KnownUnsentEventsTotal,ULINT#1); Gap(Reason:=Reason,Outcome:=USINT#2,Event:=Buffer.Records[r],Buffer:=Buffer); Free(Index:=r,Buffer:=Buffer);
    3: Buffer.IsolatedEventsTotal:=NG_SafeAdd(Buffer.IsolatedEventsTotal,ULINT#1); Gap(Reason:=Reason,Outcome:=USINT#3,Event:=Buffer.Records[r],Buffer:=Buffer); Buffer.RecordStates[r]:=4; Buffer.DeadRetainedEvents:=Buffer.DeadRetainedEvents+1;
    4: Buffer.UncertainDeliveryEventsTotal:=NG_SafeAdd(Buffer.UncertainDeliveryEventsTotal,ULINT#1); Gap(Reason:=Reason,Outcome:=USINT#4,Event:=Buffer.Records[r],Buffer:=Buffer); Buffer.RecordStates[r]:=3; Buffer.UncertainRetainedEvents:=Buffer.UncertainRetainedEvents+1;
    END_CASE;
    IF terminal>0 THEN
        Buffer.TerminalRefs[terminalOffset+j]:=r;
        Buffer.TerminalRefGenerations[terminalOffset+j]:=Buffer.RecordGenerations[r];
    END_IF;
    IF Outcome<>3 THEN Buffer.BatchRefs[offset+j]:=0; END_IF;
END_FOR;
IF Outcome=3 THEN
    Buffer.BatchOwners[Slot].State:=3; Buffer.BatchOwners[Slot].TerminalMs:=NowMs; Packets[Slot].Dead:=TRUE;
ELSE
    Buffer.BatchOwners[Slot].State:=0; Buffer.BatchOwners[Slot].Count:=0;
    Packets[Slot].MessageId:=''; Packets[Slot].Payload:=''; Packets[Slot].Length:=0;
    Packets[Slot].WasSent:=FALSE; Packets[Slot].Dead:=FALSE; Packets[Slot].Attempts:=0;
    Packets[Slot].LastSentMs:=0; Packets[Slot].RetryAtMs:=0; Packets[Slot].LastError:='';
END_IF;
END_FUNCTION_BLOCK
