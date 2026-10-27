FUNCTION_BLOCK NG_PollSlot
VAR_INPUT
    NowMs : ULINT;
    PeriodMs : UDINT;
END_VAR
VAR_OUTPUT
    NominalDueMs : ULINT;
END_VAR
VAR_IN_OUT
    Cursor : NG_SourceCursor;
    Buffer : NG_Buffer;
END_VAR
VAR
    skipped : ULINT;
END_VAR
(* Caller has checked NowMs>=NextDue; O is activation, never completion/UTC. *)
NominalDueMs:=Cursor.NextDueMonoMs;
IF (PeriodMs=0) OR (NowMs<Cursor.NextDueMonoMs) OR (NowMs>ULINT#9007199254740991) THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
skipped:=(NowMs-Cursor.NextDueMonoMs)/TO_ULINT(PeriodMs);
IF skipped<=ULINT#4294967295 THEN Cursor.PollSkippedPending:=TO_UDINT(skipped);
ELSE Cursor.PollSkippedPending:=UDINT#4294967295; Buffer.AuditFactsComplete:=FALSE; END_IF;
IF skipped>ULINT#9007199254740991-Buffer.MissedPollCyclesTotal THEN Buffer.CounterOverflow:=TRUE; END_IF;
Buffer.MissedPollCyclesTotal:=NG_SafeAdd(Buffer.MissedPollCyclesTotal,skipped);
NominalDueMs:=Cursor.NextDueMonoMs+skipped*TO_ULINT(PeriodMs);
IF NominalDueMs>ULINT#9007199254740991-TO_ULINT(PeriodMs) THEN Buffer.CaptureStopped:=TRUE;
ELSE Cursor.NextDueMonoMs:=NominalDueMs+TO_ULINT(PeriodMs); END_IF;
END_FUNCTION_BLOCK
