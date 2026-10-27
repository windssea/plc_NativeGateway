FUNCTION_BLOCK NG_Delivery
VAR_INPUT
    GateOpen : BOOL;
    NowMs : ULINT;
    GatewayId : NG_Id;
    BootId : NG_Id;
    SubmitAck : BOOL;
    AckMessageId : NG_Id;
    AckStored : BOOL;
    AckRetryable : BOOL;
    AckCodes : NG_Text;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
    Packets : ARRAY[1..16] OF NG_Packet;
END_VAR
VAR_OUTPUT
    AckBusy : BOOL;
    SendSlot : UINT;
    SendGeneration : UDINT;
    SendMessageId : NG_Id;
END_VAR
VAR
    Digest : NG_StringSHA256;
    EndBatch : NG_EndBatch;
    Free : NG_FreeRecord;
    pendingAck : BOOL;
    ackId : NG_Id;
    stored : BOOL;
    retryable : BOOL;
    codes : NG_Text;
    op : UINT; (* 1 verify send,2 verify ACK *)
    slot : UINT;
    generation : UDINT;
    id : NG_Id;
    q : UINT;
    j : UINT;
    r : UINT;
    c : UINT;
    terminal : UINT;
    inFlight : UINT;
    inHistory : UINT;
    inNew : UINT;
    candidates : ARRAY[1..2] OF UINT;
    offset : UINT;
    valid : BOOL;
    eligible : BOOL;
END_VAR
IF SubmitAck AND NOT pendingAck THEN
    pendingAck:=TRUE; ackId:=AckMessageId; stored:=AckStored; retryable:=AckRetryable; codes:=AckCodes;
    IF op=1 THEN op:=0; SendSlot:=0; END_IF;
END_IF;
AckBusy:=pendingAck OR (op=2);
IF SendSlot>0 THEN
    IF NOT GateOpen OR (Buffer.BatchGenerations[SendSlot]<>SendGeneration) OR
       (Buffer.BatchOwners[SendSlot].State<>2) OR (Packets[SendSlot].MessageId<>SendMessageId) OR
       (NowMs<Packets[SendSlot].RetryAtMs) THEN SendSlot:=0; END_IF;
END_IF;
IF op<>0 THEN
    IF (Buffer.BatchGenerations[slot]<>generation) OR (Packets[slot].MessageId<>id) OR (Buffer.BatchOwners[slot].State<2) THEN
        IF op=2 THEN pendingAck:=FALSE; END_IF;
        op:=0;
    END_IF;
END_IF;
IF op=0 THEN
    IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#180>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
    Digest(Execute:=FALSE,Length:=UDINT#0,Payload:=Packets[1].Payload);
    IF pendingAck THEN
        SendSlot:=0; slot:=0;
        FOR q:=1 TO 16 DO
            IF (Packets[q].MessageId=ackId) AND (Buffer.BatchOwners[q].State>=2) AND Packets[q].WasSent THEN slot:=q; EXIT; END_IF;
        END_FOR;
        IF slot>0 THEN
            generation:=Buffer.BatchGenerations[slot]; id:=ackId; op:=2;
        ELSE
            terminal:=0;
            FOR q:=1 TO 64 DO
                IF (Buffer.TerminalOwners[q].Count>0) AND (Buffer.TerminalOwners[q].MessageId=ackId) THEN terminal:=q; EXIT; END_IF;
            END_FOR;
            IF terminal=0 THEN Buffer.UnknownAcksTotal:=NG_SafeAdd(Buffer.UnknownAcksTotal,ULINT#1);
            ELSIF stored THEN
                IF Buffer.TerminalOwners[terminal].Outcome=2 THEN Buffer.ConflictingAcksTotal:=NG_SafeAdd(Buffer.ConflictingAcksTotal,ULINT#1);
                ELSE
                    offset:=(terminal-1)*64; valid:=Buffer.TerminalOwners[terminal].Digest<>'';
                    FOR j:=1 TO Buffer.TerminalOwners[terminal].Count DO
                        r:=Buffer.TerminalRefs[offset+j];
                        IF r=0 THEN valid:=FALSE;
                        ELSIF (Buffer.RecordGenerations[r]<>Buffer.TerminalRefGenerations[offset+j]) OR (Buffer.RecordStates[r]<>3) THEN valid:=FALSE;
                        ELSIF (Buffer.Configs[Buffer.Records[r].ConfigSlot].GatewayId<>GatewayId) OR
                              (Buffer.Configs[Buffer.Records[r].ConfigSlot].CaptureBootId<>BootId) THEN valid:=FALSE; END_IF;
                    END_FOR;
                    IF valid THEN
                        FOR j:=1 TO Buffer.TerminalOwners[terminal].Count DO
                            r:=Buffer.TerminalRefs[offset+j]; Free(Index:=r,Buffer:=Buffer);
                            Buffer.StoredConfirmedEventsTotal:=NG_SafeAdd(Buffer.StoredConfirmedEventsTotal,ULINT#1);
                            Buffer.LateStoredEventsTotal:=NG_SafeAdd(Buffer.LateStoredEventsTotal,ULINT#1);
                            Buffer.TerminalRefs[offset+j]:=0;
                        END_FOR;
                        Buffer.TerminalOwners[terminal].Count:=0; Buffer.TerminalOwners[terminal].Outcome:=3;
                    ELSE Buffer.CaptureStopped:=TRUE; END_IF;
                END_IF;
            END_IF;
            pendingAck:=FALSE;
        END_IF;
    (* Verify during the pacing wait; actual submission still gates NextSendAt. *)
    ELSIF GateOpen AND (SendSlot=0) THEN
        inFlight:=0; inHistory:=0; inNew:=0; candidates[1]:=0; candidates[2]:=0;
        FOR q:=1 TO 16 DO
            IF (Buffer.BatchOwners[q].State=2) AND Packets[q].WasSent THEN
                inFlight:=inFlight+1;
                IF Buffer.BatchOwners[q].Category=1 THEN inHistory:=inHistory+1; ELSE inNew:=inNew+1; END_IF;
            END_IF;
        END_FOR;
        FOR q:=1 TO 16 DO
            IF Buffer.BatchOwners[q].State=2 THEN
                c:=TO_UINT(Buffer.BatchOwners[q].Category);
                IF (c<1) OR (c>2) THEN Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; RETURN; END_IF;
                eligible:=Packets[q].WasSent OR ((inFlight<8) AND (((c=1) AND (inHistory<7)) OR ((c=2) AND (inNew<7))));
                eligible:=eligible AND (NowMs>=Packets[q].RetryAtMs);
                IF eligible THEN
                    IF candidates[c]=0 THEN candidates[c]:=q;
                    ELSIF Buffer.BatchOwners[q].OrderSeq<Buffer.BatchOwners[candidates[c]].OrderSeq THEN candidates[c]:=q; END_IF;
                END_IF;
            END_IF;
        END_FOR;
        c:=TO_UINT(Buffer.PreferSend); IF candidates[c]=0 THEN c:=UINT#3-c; END_IF;
        slot:=candidates[c];
        IF slot>0 THEN generation:=Buffer.BatchGenerations[slot]; id:=Packets[slot].MessageId; op:=1; END_IF;
    END_IF;
END_IF;
IF op<>0 THEN
    Digest(Execute:=TRUE,Length:=Packets[slot].Length,DeadlineUs:=Buffer.WorkDeadlineUs,Payload:=Packets[slot].Payload);
    IF Digest.Error THEN Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; RETURN; END_IF;
    IF Digest.Done THEN
        IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#350>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
        valid:=(Digest.Digest=Buffer.BatchOwners[slot].Digest) AND (Packets[slot].Length=TO_UDINT(LEN(Packets[slot].Payload)));
        c:=Buffer.BatchOwners[slot].ConfigSlot;
        IF (c<1) OR (c>4) THEN Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; op:=0; pendingAck:=FALSE; RETURN; END_IF;
        valid:=valid AND (Buffer.Configs[c].GatewayId=GatewayId) AND (Buffer.Configs[c].CaptureBootId=BootId);
        offset:=(slot-1)*64;
        FOR j:=1 TO Buffer.BatchOwners[slot].Count DO
            r:=Buffer.BatchRefs[offset+j];
            IF r=0 THEN valid:=FALSE;
            ELSIF Buffer.RecordGenerations[r]<>Buffer.BatchRefGenerations[offset+j] THEN valid:=FALSE; END_IF;
        END_FOR;
        IF NOT valid THEN
            Buffer.CorruptBatchesTotal:=NG_SafeAdd(Buffer.CorruptBatchesTotal,ULINT#1); Buffer.CaptureStopped:=TRUE;
            Buffer.AccountingComplete:=FALSE;
            IF Buffer.BatchOwners[slot].State=2 THEN
                c:=2; IF Packets[slot].WasSent THEN c:=4; END_IF;
                EndBatch(Slot:=slot,Outcome:=TO_USINT(c),Reason:=USINT#7,NowMs:=NowMs,Buffer:=Buffer,Packets:=Packets);
            END_IF;
        ELSIF op=2 THEN
            IF stored THEN
                IF Buffer.BatchOwners[slot].State=3 THEN Buffer.ConflictingAcksTotal:=NG_SafeAdd(Buffer.ConflictingAcksTotal,ULINT#1);
                ELSE EndBatch(Slot:=slot,Outcome:=USINT#1,Reason:=USINT#0,NowMs:=NowMs,Buffer:=Buffer,Packets:=Packets); END_IF;
            ELSIF Buffer.BatchOwners[slot].State=2 THEN
                IF retryable THEN Packets[slot].RetryAtMs:=MAX(Packets[slot].RetryAtMs,NowMs+60000+TO_ULINT(slot)*17); Packets[slot].LastError:=codes;
                ELSE Packets[slot].LastError:=codes; EndBatch(Slot:=slot,Outcome:=USINT#3,Reason:=USINT#8,NowMs:=NowMs,Buffer:=Buffer,Packets:=Packets); END_IF;
            END_IF;
        ELSIF GateOpen AND (NowMs>=Packets[slot].RetryAtMs) THEN
            SendSlot:=slot; SendGeneration:=generation; SendMessageId:=id;
        END_IF;
        IF op=2 THEN pendingAck:=FALSE; END_IF;
        op:=0;
    END_IF;
END_IF;
AckBusy:=pendingAck OR (op=2);
END_FUNCTION_BLOCK
