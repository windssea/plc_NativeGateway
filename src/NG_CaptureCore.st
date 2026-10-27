FUNCTION_BLOCK NG_CaptureCore
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
    Cursor : NG_SourceCursor;
    Buffer : NG_Buffer;
END_VAR
VAR
    s : UINT;
    d : INT;
    Gap : NG_GapLog;
    Audit : NG_AuditCapture;
    AuditDecision : NG_AuditDecision;
END_VAR
Accepted:=FALSE; s:=Buffer.ActiveSlot;
IF Buffer.CaptureStopped OR NOT Buffer.LayoutValid OR (s=0) OR (s>4) THEN RETURN; END_IF;
IF (PointIndex<1) OR (PointIndex>320) THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
IF (Buffer.NextSampleSeq>=ULINT#9007199254740991) OR (NowMs>ULINT#9007199254740991) THEN
    Buffer.CaptureStopped:=TRUE; RETURN;
END_IF;
Buffer.NextSampleSeq:=Buffer.NextSampleSeq+1;
Buffer.CapturedEventsTotal:=NG_SafeAdd(Buffer.CapturedEventsTotal,ULINT#1);
Buffer.Scratch.SampleSeq:=Buffer.NextSampleSeq; Buffer.Scratch.Value:=0;
IF Quality=2 THEN Buffer.Scratch.Value:=Value; END_IF;
Buffer.Scratch.Kind:=Kind; Buffer.Scratch.Quality:=Quality;
Buffer.Scratch.PollSkippedBefore:=0;
IF Kind=1 THEN
    Buffer.Scratch.PollSkippedBefore:=Cursor.PollSkippedPending;
    Cursor.PollSkippedPending:=0;
END_IF;
Buffer.Scratch.CompletedMonoMs:=NowMs; Buffer.Scratch.NominalDueMonoMs:=0;
Buffer.Scratch.ConfigSlot:=s; Buffer.Scratch.ConfigGeneration:=Buffer.Configs[s].Generation;
Buffer.Scratch.PointIndex:=PointIndex; Buffer.Scratch.SamplingGeneration:=Buffer.SamplingGeneration;
Buffer.Scratch.ClockRevision:=0; Buffer.Scratch.CapturedUtcMs:=0; Buffer.Scratch.Flags:=WORD#8;
(* Explicit SYSTEM_RTC_COMPAT_UNVERIFIED: trusted UTC/timeValid remain absent. *)
IF (SystemUtcMs>0) AND (SystemUtcMs<=ULINT#9007199254740991) THEN Buffer.Scratch.CapturedUtcMs:=SystemUtcMs; Buffer.Scratch.Flags:=WORD#9; END_IF;
IF Buffer.PlatformTime THEN
    Buffer.Scratch.ClockRevision:=Buffer.ClockRevision; Buffer.Scratch.CapturedUtcMs:=0; Buffer.Scratch.Flags:=WORD#0;
    IF Buffer.TimeValid AND (SystemUtcMs>0) AND (SystemUtcMs<=ULINT#9007199254740991) THEN
        Buffer.Scratch.CapturedUtcMs:=SystemUtcMs; Buffer.Scratch.Flags:=WORD#3;
    END_IF;
END_IF;
IF Kind=1 THEN
    Buffer.Scratch.NominalDueMonoMs:=NominalDueMs; Buffer.Scratch.Flags:=Buffer.Scratch.Flags OR WORD#4;
    IF Cursor.HasPhysicalUtc AND ((Buffer.Scratch.Flags AND WORD#1)<>WORD#0) AND
       (Cursor.LastPhysicalUtcMs=SystemUtcMs) THEN
        Buffer.SourceTimestampRepeatTotal:=NG_SafeAdd(Buffer.SourceTimestampRepeatTotal,ULINT#1);
    END_IF;
    Cursor.HasPhysicalUtc:=(Buffer.Scratch.Flags AND WORD#1)<>WORD#0;
    Cursor.LastPhysicalUtcMs:=SystemUtcMs;
END_IF;
Audit(Buffer:=Buffer,Event:=Buffer.Scratch);
IF Buffer.IngressCount>=512 THEN
    Buffer.CaptureOverflowEventsTotal:=NG_SafeAdd(Buffer.CaptureOverflowEventsTotal,ULINT#1);
    Buffer.AccountingComplete:=FALSE;
    Buffer.UndecidedLostEventsTotal:=NG_SafeAdd(Buffer.UndecidedLostEventsTotal,ULINT#1);
    Gap(Reason:=USINT#1,Outcome:=USINT#5,Event:=Buffer.Scratch,Buffer:=Buffer);
    AuditDecision(SampleSeq:=Buffer.Scratch.SampleSeq,Decision:=USINT#4,Reason:=USINT#1,ReportSkipped:=ULINT#0,Buffer:=Buffer);
    RETURN;
END_IF;
Buffer.Ingress[Buffer.Tail]:=Buffer.Scratch; Buffer.Tail:=Buffer.Tail MOD 512+1;
Buffer.IngressCount:=Buffer.IngressCount+1; Buffer.Configs[s].References:=Buffer.Configs[s].References+1;
Accepted:=TRUE;
END_FUNCTION_BLOCK
