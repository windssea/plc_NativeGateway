FUNCTION_BLOCK NG_CheckCounters
VAR_IN_OUT
    Buffer : NG_Buffer;
END_VAR
VAR
    maximum : ULINT := ULINT#9007199254740991;
END_VAR
IF (Buffer.CapturedEventsTotal>=maximum) OR (Buffer.EligibleEventsTotal>=maximum) OR
   (Buffer.PolicyFilteredEventsTotal>=maximum) OR (Buffer.TimeInvalidEventsTotal>=maximum) OR
   (Buffer.CaptureOverflowEventsTotal>=maximum) OR (Buffer.UndecidedLostEventsTotal>=maximum) OR
   (Buffer.KnownUnsentEventsTotal>=maximum) OR (Buffer.IsolatedEventsTotal>=maximum) OR
   (Buffer.UncertainDeliveryEventsTotal>=maximum) OR (Buffer.StoredConfirmedEventsTotal>=maximum) OR
   (Buffer.LateStoredEventsTotal>=maximum) OR (Buffer.EnqueueRejectedAttemptsTotal>=maximum) OR
   (Buffer.MissedPollCyclesTotal>=maximum) OR (Buffer.MissedReportSlotsTotal>=maximum) OR
   (Buffer.SourceTimestampRepeatTotal>=maximum) OR (Buffer.GapRecordsTotal>=maximum) THEN
    Buffer.CounterOverflow:=TRUE;
END_IF;
IF Buffer.CounterOverflow OR Buffer.CaptureStopped OR (Buffer.UndecidedLostEventsTotal>0) THEN Buffer.AccountingComplete:=FALSE; END_IF;
END_FUNCTION_BLOCK
