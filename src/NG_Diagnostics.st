FUNCTION_BLOCK NG_Diagnostics
VAR_INPUT
    BootId : NG_Id;
    GatewayId : NG_Id;
    NowMs : ULINT;
    Force : BOOL;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    lastUpdate : ULINT;
    oldest : ULINT;
    hasOldest : BOOL;
    q : UINT;
    r : UINT;
    pendingBatches : UINT;
    deadBatches : UINT;
END_VAR
IF NOT Buffer.DiagnosticInitialized THEN
    Buffer.DiagnosticInitialized:=TRUE;
    Buffer.RestartLossUnknown:=TRUE; Buffer.AccountingComplete:=FALSE;
    Buffer.GapRecordsTotal:=NG_SafeAdd(Buffer.GapRecordsTotal,ULINT#1);
    Buffer.Diagnostics.LastGap.Reason:=9; Buffer.Diagnostics.LastGap.Outcome:=4;
    Buffer.Diagnostics.LastGapCountKnown:=FALSE;
END_IF;
IF NOT Force AND (NowMs<lastUpdate+1000) AND (Buffer.Diagnostics.Revision<>0) THEN RETURN; END_IF;
IF NOT Force AND (Buffer.WorkDeadlineUs>0) THEN IF GET_MICROSECONDS(TRUE)+ULINT#350>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
IF Buffer.Diagnostics.Revision>=ULINT#9007199254740988 THEN Buffer.CounterOverflow:=TRUE; RETURN; END_IF;
Buffer.Diagnostics.Revision:=Buffer.Diagnostics.Revision+1;
Buffer.Diagnostics.BootId:=BootId; Buffer.Diagnostics.GatewayId:=GatewayId;
Buffer.Diagnostics.CapturedMonoMs:=NowMs;
IF Buffer.ActiveSlot>0 THEN Buffer.Diagnostics.ConfigVersion:=Buffer.Configs[Buffer.ActiveSlot].Config.Version; END_IF;
Buffer.Diagnostics.Totals[1]:=Buffer.CapturedEventsTotal;
Buffer.Diagnostics.Totals[2]:=Buffer.EligibleEventsTotal;
Buffer.Diagnostics.Totals[3]:=Buffer.PolicyFilteredEventsTotal;
Buffer.Diagnostics.Totals[4]:=Buffer.TimeInvalidEventsTotal;
Buffer.Diagnostics.Totals[5]:=Buffer.CaptureOverflowEventsTotal;
Buffer.Diagnostics.Totals[6]:=Buffer.UndecidedLostEventsTotal;
Buffer.Diagnostics.Totals[7]:=Buffer.KnownUnsentEventsTotal;
Buffer.Diagnostics.Totals[8]:=Buffer.IsolatedEventsTotal;
Buffer.Diagnostics.Totals[9]:=Buffer.UncertainDeliveryEventsTotal;
Buffer.Diagnostics.Totals[10]:=Buffer.StoredConfirmedEventsTotal;
Buffer.Diagnostics.Totals[11]:=Buffer.LateStoredEventsTotal;
Buffer.Diagnostics.Totals[12]:=Buffer.EnqueueRejectedAttemptsTotal;
Buffer.Diagnostics.Totals[13]:=Buffer.MissedPollCyclesTotal;
Buffer.Diagnostics.Totals[14]:=Buffer.MissedReportSlotsTotal;
Buffer.Diagnostics.Totals[15]:=Buffer.SourceTimestampRepeatTotal;
Buffer.Diagnostics.Totals[16]:=Buffer.GapRecordsTotal;
Buffer.Diagnostics.DecisionPending:=TO_ULINT(Buffer.IngressCount);
Buffer.Diagnostics.PendingEvents:=TO_ULINT(Buffer.OwnedCount)-Buffer.DeadRetainedEvents-Buffer.UncertainRetainedEvents+TO_ULINT(Buffer.IngressCount);
Buffer.Diagnostics.DeadEvents:=Buffer.DeadRetainedEvents;
Buffer.Diagnostics.UncertainRetainedEvents:=Buffer.UncertainRetainedEvents;
oldest:=ULINT#9007199254740991; hasOldest:=FALSE; pendingBatches:=0; deadBatches:=0;
IF Buffer.IngressCount>0 THEN oldest:=Buffer.Ingress[Buffer.Head].CompletedMonoMs; hasOldest:=TRUE; END_IF;
FOR q:=1 TO 2 DO
    r:=Buffer.QueueHead[q];
    IF r>0 THEN oldest:=MIN(oldest,Buffer.Records[r].CompletedMonoMs); hasOldest:=TRUE; END_IF;
END_FOR;
FOR q:=1 TO 16 DO
    IF Buffer.BatchOwners[q].State=2 THEN pendingBatches:=pendingBatches+1; END_IF;
    IF Buffer.BatchOwners[q].State=3 THEN deadBatches:=deadBatches+1; END_IF;
    IF (Buffer.BatchOwners[q].State=1) OR (Buffer.BatchOwners[q].State=2) THEN oldest:=MIN(oldest,Buffer.BatchOwners[q].CreatedMs); hasOldest:=TRUE; END_IF;
END_FOR;
Buffer.Diagnostics.PendingBatches:=pendingBatches; Buffer.Diagnostics.DeadBatches:=deadBatches;
Buffer.Diagnostics.OldestPendingAgeMs:=0; Buffer.Diagnostics.HasPendingAge:=FALSE;
IF hasOldest AND (NowMs>=oldest) THEN Buffer.Diagnostics.OldestPendingAgeMs:=NowMs-oldest; Buffer.Diagnostics.HasPendingAge:=TRUE; END_IF;
Buffer.Diagnostics.AllocatedBytes:=Buffer.LayoutBytes;
Buffer.Diagnostics.UsedBytes:=Buffer.LayoutBytes-(UDINT#28800-Buffer.OwnedCount)*Buffer.RecordBytes;
Buffer.Diagnostics.MaxBytes:=4194304;
Buffer.Diagnostics.AccountingComplete:=Buffer.AccountingComplete;
Buffer.Diagnostics.CounterOverflow:=Buffer.CounterOverflow; Buffer.Diagnostics.DetailTruncated:=Buffer.DetailTruncated;
Buffer.Diagnostics.RestartLossUnknown:=Buffer.RestartLossUnknown;
Buffer.Diagnostics.AuditDropped:=Buffer.AuditDropped; Buffer.Diagnostics.AssociationDropped:=Buffer.AssociationDropped;
Buffer.Diagnostics.EvidenceComplete:=Buffer.EvidenceComplete;
IF Buffer.GapIndex>0 THEN Buffer.Diagnostics.LastGap:=Buffer.Gaps[Buffer.GapIndex]; Buffer.Diagnostics.LastGapCountKnown:=TRUE; END_IF;
Buffer.Diagnostics.HmiSummary:=CONCAT('RAM P=',TO_STRING(Buffer.Diagnostics.PendingEvents,'{0:d}'),' I=',TO_STRING(Buffer.Diagnostics.DeadEvents,'{0:d}'),' U-retained=',TO_STRING(Buffer.Diagnostics.UncertainRetainedEvents,'{0:d}'),' bytes=',TO_STRING(Buffer.Diagnostics.UsedBytes,'{0:d}'),'/',TO_STRING(Buffer.Diagnostics.MaxBytes,'{0:d}'),' restart-loss=UNKNOWN auditDrops=',TO_STRING(Buffer.AuditDropped+Buffer.AssociationDropped,'{0:d}'));
Buffer.Diagnostics.Revision:=Buffer.Diagnostics.Revision+1; lastUpdate:=NowMs;
END_FUNCTION_BLOCK
