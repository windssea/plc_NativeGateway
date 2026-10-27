FUNCTION_BLOCK NG_BufferMaintenance
VAR_INPUT
    GateOpen : BOOL;
    NowMs : ULINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
    Packets : ARRAY[1..16] OF NG_Packet;
END_VAR
VAR
    EndBatch : NG_EndBatch;
    Free : NG_FreeRecord;
    Gap : NG_GapLog;
    Prune : NG_PruneTerminal;
    r : UINT;
    c : UINT;
    q : UINT;
    oldestSlot : UINT;
    oldestSeq : ULINT;
    oldestTerminal : UINT;
    deadSlot : UINT;
    deadCount : UINT;
    deadBytes : UDINT;
    n : INT;
    pressure : BOOL;
    expired : BOOL;
END_VAR
IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#200>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
IF GateOpen AND NOT Buffer.GateWasOpen THEN
    Buffer.Watermark:=Buffer.LastAdmittedSeq;
    IF Buffer.QueueHead[2]<>0 THEN
        IF Buffer.QueueHead[1]=0 THEN Buffer.QueueHead[1]:=Buffer.QueueHead[2];
        ELSE Buffer.FreeSlots[Buffer.QueueTail[1]]:=Buffer.QueueHead[2]; END_IF;
        Buffer.QueueTail[1]:=Buffer.QueueTail[2]; Buffer.QueueHead[2]:=0; Buffer.QueueTail[2]:=0;
    END_IF;
    FOR q:=1 TO 16 DO IF Buffer.BatchOwners[q].State<>0 THEN Buffer.BatchOwners[q].Category:=1; END_IF; END_FOR;
END_IF;
Buffer.GateWasOpen:=GateOpen;
deadCount:=0; deadBytes:=0; deadSlot:=0;
FOR q:=1 TO 16 DO
    IF Buffer.BatchOwners[q].State=3 THEN
        deadCount:=deadCount+1; deadBytes:=deadBytes+Packets[q].Length;
        IF deadSlot=0 THEN deadSlot:=q;
        ELSIF Buffer.BatchOwners[q].OrderSeq<Buffer.BatchOwners[deadSlot].OrderSeq THEN deadSlot:=q; END_IF;
    END_IF;
END_FOR;
IF deadSlot>0 THEN
    IF (deadCount>4) OR (deadBytes>65536) OR (NowMs>=Buffer.BatchOwners[deadSlot].TerminalMs+600000) THEN
        EndBatch(Slot:=deadSlot,Outcome:=USINT#5,Reason:=USINT#0,NowMs:=NowMs,Buffer:=Buffer,Packets:=Packets); RETURN;
    END_IF;
END_IF;
(* At most 64 single-record releases OR one whole batch per scan. Terminal
   evidence shares the same record quota and is reclaimed before live data. *)
FOR n:=1 TO 64 DO
    pressure:=Buffer.OwnedCount+TO_UDINT(MIN(Buffer.IngressCount,UINT#64))>UDINT#28800;
    IF pressure THEN
        oldestTerminal:=0;
        FOR q:=1 TO 64 DO
            IF Buffer.TerminalOwners[q].Count>0 THEN
                IF oldestTerminal=0 THEN oldestTerminal:=q;
                ELSIF Buffer.TerminalOwners[q].FirstSeq<Buffer.TerminalOwners[oldestTerminal].FirstSeq THEN oldestTerminal:=q; END_IF;
            END_IF;
        END_FOR;
        IF oldestTerminal>0 THEN Prune(Index:=oldestTerminal,Buffer:=Buffer); RETURN; END_IF;
    END_IF;
    c:=0; r:=0; oldestSlot:=0; oldestSeq:=ULINT#9007199254740991;
    FOR q:=1 TO 2 DO
        IF Buffer.QueueHead[q]>0 THEN
            IF Buffer.Records[Buffer.QueueHead[q]].SampleSeq<oldestSeq THEN
                c:=q; r:=Buffer.QueueHead[q]; oldestSeq:=Buffer.Records[r].SampleSeq;
            END_IF;
        END_IF;
    END_FOR;
    FOR q:=1 TO 16 DO
        IF Buffer.BatchOwners[q].State>=2 THEN
            IF Buffer.BatchOwners[q].OrderSeq<oldestSeq THEN oldestSlot:=q; oldestSeq:=Buffer.BatchOwners[q].OrderSeq; r:=0; END_IF;
        END_IF;
    END_FOR;
    expired:=FALSE;
    IF r>0 THEN expired:=NowMs>=Buffer.Records[r].CompletedMonoMs+900000;
    ELSIF oldestSlot>0 THEN expired:=NowMs>=Buffer.BatchOwners[oldestSlot].CreatedMs+900000; END_IF;
    IF NOT pressure AND NOT expired THEN EXIT; END_IF;
    IF r>0 THEN
        Buffer.QueueHead[c]:=Buffer.FreeSlots[r]; IF Buffer.QueueHead[c]=0 THEN Buffer.QueueTail[c]:=0; END_IF;
        Buffer.KnownUnsentEventsTotal:=NG_SafeAdd(Buffer.KnownUnsentEventsTotal,ULINT#1);
        IF expired THEN Gap(Reason:=USINT#6,Event:=Buffer.Records[r],Buffer:=Buffer); ELSE Gap(Reason:=USINT#5,Event:=Buffer.Records[r],Buffer:=Buffer); END_IF;
        Free(Index:=r,Buffer:=Buffer);
    ELSIF oldestSlot>0 THEN
        q:=2; IF Packets[oldestSlot].WasSent THEN q:=4; END_IF;
        IF Buffer.BatchOwners[oldestSlot].State=3 THEN q:=5; END_IF;
        c:=5; IF expired THEN c:=6; END_IF;
        EndBatch(Slot:=oldestSlot,Outcome:=TO_USINT(q),Reason:=TO_USINT(c),NowMs:=NowMs,Buffer:=Buffer,Packets:=Packets);
        (* Under a hard full-pool fence even terminal evidence must yield to
           new capture. Preserve the cumulative U/I fact and gap, explicitly
           mark evidence pruning rather than reject a fresh cohort silently. *)
        IF pressure AND (q>=4) THEN Prune(Index:=Buffer.TerminalIndex,Buffer:=Buffer); END_IF;
        RETURN;
    ELSE EXIT; END_IF;
END_FOR;
END_FUNCTION_BLOCK
