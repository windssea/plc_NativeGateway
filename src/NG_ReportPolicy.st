FUNCTION_BLOCK NG_ReportPolicy
VAR_INPUT
    DeferCapacity : BOOL;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    Event : NG_CaptureEvent;
    Gap : NG_GapLog;
    AuditDecision : NG_AuditDecision;
    s : UINT;
    p : UINT;
    r : UINT;
    c : UINT;
    n : INT;
    slots : ULINT;
    reportSkipped : ULINT;
    reportEpochCode : UINT;
    epochPeriod : ULINT;
    epochBase : ULINT;
    epochDelta : ULINT;
    selected : BOOL;
    present : BOOL;
    reject : BOOL;
    reason : USINT;
END_VAR
(* Atomic RAM admission is this mode's local commit boundary. The copied
   baseline has no dependency on delivery order or subsequent slot reuse. *)
FOR n:=1 TO 64 DO
    IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#70>=Buffer.WorkDeadlineUs THEN EXIT; END_IF; END_IF;
    IF Buffer.IngressCount=0 THEN EXIT; END_IF;
    (* A local whole-batch reclaim may need the next bounded scan. Keep this
       raw event undecided until that reclaim; never wait on SDK/ACK here. *)
    IF DeferCapacity AND (Buffer.FreeHead=0) AND (Buffer.HighSlot>=28800) THEN EXIT; END_IF;
    Event:=Buffer.Ingress[Buffer.Head]; s:=Event.ConfigSlot; p:=Event.PointIndex;
    Buffer.Head:=Buffer.Head MOD 512+1; Buffer.IngressCount:=Buffer.IngressCount-1;
    reject:=FALSE; reason:=0; reportSkipped:=0; reportEpochCode:=UINT#65535;
    IF (s<>Buffer.ActiveSlot) OR (Event.ConfigGeneration<>Buffer.Configs[s].Generation) OR
       (Event.SamplingGeneration<>Buffer.SamplingGeneration) OR NOT Buffer.Cursors[p].Enabled THEN
        Buffer.UndecidedLostEventsTotal:=NG_SafeAdd(Buffer.UndecidedLostEventsTotal,ULINT#1);
        Buffer.AccountingComplete:=FALSE;
        reason:=2; reject:=TRUE;
    ELSE
        present:=((Event.Flags AND WORD#1)<>WORD#0) AND
                 (((Event.Flags AND WORD#2)<>WORD#0) OR ((Event.Flags AND WORD#8)<>WORD#0));
        IF Buffer.PlatformTime THEN
            present:=present AND Buffer.TimeValid AND (Event.ClockRevision=Buffer.ClockRevision)
                AND ((Event.Flags AND WORD#2)<>WORD#0);
        END_IF;
        IF (Buffer.ReportCursors[p].SamplingGeneration<>Event.SamplingGeneration) OR
           (Buffer.ReportCursors[p].ConfigGeneration<>Event.ConfigGeneration) OR
           (Buffer.ReportCursors[p].ClockRevision<>Event.ClockRevision) OR
           (Buffer.ReportCursors[p].TimePresent<>present) THEN
            slots:=Buffer.Cursors[p].ActivatedMonoMs;
            IF (Buffer.ReportCursors[p].ConfigGeneration=Event.ConfigGeneration) AND
               ((Buffer.ReportCursors[p].TimePresent<>present) OR (Buffer.ReportCursors[p].ClockRevision<>Event.ClockRevision)) THEN
                slots:=Buffer.Cursors[p].NextDueMonoMs;
                IF Event.Kind=1 THEN slots:=Event.NominalDueMonoMs;
                ELSE
                    reportEpochCode:=UINT#255;
                    epochPeriod:=TO_ULINT(Buffer.Configs[s].Config.Points[p].pollIntervalMs);
                    IF (epochPeriod>0) AND (Event.CompletedMonoMs>=Buffer.Cursors[p].ActivatedMonoMs) AND (slots>=Buffer.Cursors[p].ActivatedMonoMs) THEN
                        IF (slots-Buffer.Cursors[p].ActivatedMonoMs) MOD epochPeriod=0 THEN
                            epochBase:=Buffer.Cursors[p].ActivatedMonoMs+((Event.CompletedMonoMs-Buffer.Cursors[p].ActivatedMonoMs)/epochPeriod)*epochPeriod;
                            IF slots>=epochBase THEN
                                epochDelta:=(slots-epochBase)/epochPeriod;
                                IF epochDelta<=ULINT#127 THEN reportEpochCode:=TO_UINT(ULINT#127+epochDelta); END_IF;
                            ELSE
                                epochDelta:=(epochBase-slots)/epochPeriod;
                                IF epochDelta<=ULINT#127 THEN reportEpochCode:=TO_UINT(ULINT#127-epochDelta); END_IF;
                            END_IF;
                        END_IF;
                    END_IF;
                END_IF;
            END_IF;
            Buffer.ReportCursors[p].SamplingGeneration:=Event.SamplingGeneration;
            Buffer.ReportCursors[p].ConfigGeneration:=Event.ConfigGeneration;
            Buffer.ReportCursors[p].ClockRevision:=Event.ClockRevision;
            Buffer.ReportCursors[p].TimePresent:=present;
            Buffer.ReportCursors[p].HasBaseline:=FALSE;
            Buffer.ReportCursors[p].NextDue:=slots;
        END_IF;
        selected:=NOT Buffer.ReportCursors[p].HasBaseline OR (Buffer.ReportCursors[p].Quality<>Event.Quality);
        IF Buffer.ReportCursors[p].HasBaseline AND (Event.Quality=2) AND (Buffer.ReportCursors[p].Quality=2) AND
           (Buffer.Configs[s].Config.Points[p].reportMode<>'cyclic') THEN
            IF Buffer.Configs[s].Config.Points[p].dataType='bool' THEN
                selected:=selected OR ((Event.Value=LREAL#0.0)<>(Buffer.ReportCursors[p].Value=LREAL#0.0));
            ELSE selected:=selected OR (ABS(Event.Value-Buffer.ReportCursors[p].Value)>Buffer.Configs[s].Config.Points[p].deadband); END_IF;
        END_IF;
        IF (Event.Kind=1) AND (Buffer.Configs[s].Config.Points[p].reportMode<>'change') AND
           (Event.NominalDueMonoMs>=Buffer.ReportCursors[p].NextDue) THEN
            slots:=(Event.NominalDueMonoMs-Buffer.ReportCursors[p].NextDue)/TO_ULINT(Buffer.Configs[s].Config.Points[p].reportIntervalMs)+1;
            reportSkipped:=slots-1;
            Buffer.MissedReportSlotsTotal:=NG_SafeAdd(Buffer.MissedReportSlotsTotal,slots-1);
            Buffer.ReportCursors[p].NextDue:=Buffer.ReportCursors[p].NextDue+slots*TO_ULINT(Buffer.Configs[s].Config.Points[p].reportIntervalMs);
            selected:=TRUE;
        END_IF;
        IF NOT selected THEN
            Buffer.PolicyFilteredEventsTotal:=NG_SafeAdd(Buffer.PolicyFilteredEventsTotal,ULINT#1); reject:=TRUE;
        ELSE
            Buffer.EligibleEventsTotal:=NG_SafeAdd(Buffer.EligibleEventsTotal,ULINT#1);
            IF NOT present THEN
                Buffer.TimeInvalidEventsTotal:=NG_SafeAdd(Buffer.TimeInvalidEventsTotal,ULINT#1); reason:=4; reject:=TRUE;
            ELSIF (Buffer.FreeHead=0) AND (Buffer.HighSlot>=28800) THEN
                Buffer.EnqueueRejectedAttemptsTotal:=NG_SafeAdd(Buffer.EnqueueRejectedAttemptsTotal,ULINT#1); reason:=5; reject:=TRUE;
            END_IF;
            IF reject THEN Buffer.KnownUnsentEventsTotal:=NG_SafeAdd(Buffer.KnownUnsentEventsTotal,ULINT#1); END_IF;
        END_IF;
    END_IF;
    IF reject THEN
        c:=1;
        IF reason=2 THEN c:=4; ELSIF reason<>0 THEN c:=3; END_IF;
        AuditDecision(SampleSeq:=Event.SampleSeq,Decision:=TO_USINT(c),Reason:=reason,ReportSkipped:=reportSkipped,ReportEpochCode:=reportEpochCode,Buffer:=Buffer);
        IF reason<>0 THEN Gap(Reason:=reason,Event:=Event,Buffer:=Buffer); END_IF;
        Buffer.Configs[s].References:=Buffer.Configs[s].References-1;
    ELSE
        IF Buffer.FreeHead<>0 THEN r:=Buffer.FreeHead; Buffer.FreeHead:=Buffer.FreeSlots[r];
        ELSE Buffer.HighSlot:=Buffer.HighSlot+1; r:=Buffer.HighSlot; END_IF;
        IF Buffer.RecordGenerations[r]=UDINT#4294967295 THEN Buffer.CaptureStopped:=TRUE;
            Buffer.KnownUnsentEventsTotal:=NG_SafeAdd(Buffer.KnownUnsentEventsTotal,ULINT#1);
            Gap(Reason:=USINT#5,Event:=Event,Buffer:=Buffer); Buffer.Configs[s].References:=Buffer.Configs[s].References-1;
            AuditDecision(SampleSeq:=Event.SampleSeq,Decision:=USINT#3,Reason:=USINT#5,ReportSkipped:=reportSkipped,ReportEpochCode:=reportEpochCode,Buffer:=Buffer);
        ELSE
            Buffer.RecordGenerations[r]:=Buffer.RecordGenerations[r]+1;
            Buffer.Records[r]:=Event; Buffer.RecordStates[r]:=1; Buffer.FreeSlots[r]:=0;
            Buffer.LastAdmittedSeq:=MAX(Buffer.LastAdmittedSeq,Event.SampleSeq);
            AuditDecision(SampleSeq:=Event.SampleSeq,Decision:=USINT#2,Reason:=USINT#0,ReportSkipped:=reportSkipped,ReportEpochCode:=reportEpochCode,Buffer:=Buffer);
            Buffer.OwnedCount:=Buffer.OwnedCount+1;
            c:=2; IF Event.SampleSeq<=Buffer.Watermark THEN c:=1; END_IF;
            IF Buffer.QueueHead[c]=0 THEN Buffer.QueueHead[c]:=r; ELSE Buffer.FreeSlots[Buffer.QueueTail[c]]:=r; END_IF;
            Buffer.QueueTail[c]:=r;
            IF Event.SampleSeq>Buffer.ReportCursors[p].LastSeq THEN
                Buffer.ReportCursors[p].LastSeq:=Event.SampleSeq; Buffer.ReportCursors[p].Value:=Event.Value;
                Buffer.ReportCursors[p].Quality:=Event.Quality; Buffer.ReportCursors[p].HasBaseline:=TRUE;
            END_IF;
        END_IF;
    END_IF;
END_FOR;
END_FUNCTION_BLOCK
