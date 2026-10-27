PROGRAM Main
VAR
    Buffer : NG_Buffer;
    Event : NG_CaptureEvent;
    AuditRecord : NG_AuditEvent;
    Cursor : NG_SourceCursor;
    Capture : NG_CaptureCore;
    Poll : NG_PollSlot;
    Audit : NG_AuditCapture;
    Decide : NG_AuditDecision;
    Policy : NG_ReportPolicy;
    Checks : ARRAY[1..20] OF BOOL;
    Passed : UINT;
    FailedChecks : UINT;
    Done : BOOL;
    i : UINT;
END_VAR
(* Compile-only harness; no socket, SDK, persistent store, RTC or physical I/O.
   Cold compilation does not execute these assertions. *)
IF Done THEN RETURN; END_IF;
Checks[1]:=SIZEOF(Event)=UDINT#72;
Checks[2]:=SIZEOF(AuditRecord)=UDINT#80;
Checks[3]:=SIZEOF(Cursor)=UDINT#48;
Buffer.AuditEnabled:=TRUE; Buffer.PlatformTime:=TRUE; Buffer.TimeValid:=TRUE;
Event.SampleSeq:=1; Event.ConfigSlot:=1; Event.ConfigGeneration:=1;
Event.CompletedMonoMs:=1000; Event.ClockRevision:=2;
Buffer.DecisionSnapshotMonoMs:=66537; Buffer.ClockRevision:=5;
Audit(Buffer:=Buffer,Event:=Event);
Decide(SampleSeq:=ULINT#1,Decision:=USINT#2,Reason:=USINT#0,ReportSkipped:=ULINT#7,Buffer:=Buffer);
Checks[4]:=Buffer.AuditEvents[1].DecisionFlags=BYTE#63;
Checks[5]:=(Buffer.AuditEvents[1].DecisionDelayLo=1) AND (Buffer.AuditEvents[1].DecisionDelayHi=1);
Checks[6]:=(Buffer.AuditEvents[1].DecisionRevisionDelta=3) AND (Buffer.AuditEvents[1].ReportSkipped=7);
Buffer.DecisionSnapshotMonoMs:=ULINT#16778215; Buffer.ClockRevision:=257;
Audit(Buffer:=Buffer,Event:=Event);
Decide(SampleSeq:=ULINT#1,Decision:=USINT#3,Reason:=USINT#4,ReportSkipped:=ULINT#254,Buffer:=Buffer);
Checks[7]:=(Buffer.AuditEvents[1].DecisionFlags=BYTE#63) AND (Buffer.AuditEvents[1].DecisionDelayLo=65535) AND (Buffer.AuditEvents[1].DecisionDelayHi=255);
Buffer.DecisionSnapshotMonoMs:=ULINT#16778216;
Audit(Buffer:=Buffer,Event:=Event);
Decide(SampleSeq:=ULINT#1,Decision:=USINT#3,Reason:=USINT#4,ReportSkipped:=ULINT#0,Buffer:=Buffer);
Checks[8]:=((Buffer.AuditEvents[1].DecisionFlags AND BYTE#8)=BYTE#0) AND NOT Buffer.AuditFactsComplete;
Buffer.AuditFactsComplete:=TRUE; Buffer.DecisionSnapshotMonoMs:=1000; Buffer.ClockRevision:=258;
Audit(Buffer:=Buffer,Event:=Event);
Decide(SampleSeq:=ULINT#1,Decision:=USINT#3,Reason:=USINT#4,ReportSkipped:=ULINT#255,Buffer:=Buffer);
Checks[9]:=((Buffer.AuditEvents[1].DecisionFlags AND BYTE#16)=BYTE#0) AND ((Buffer.AuditEvents[1].DecisionFlags AND BYTE#32)=BYTE#0);
Buffer.DecisionSnapshotMonoMs:=999; Buffer.ClockRevision:=2;
Audit(Buffer:=Buffer,Event:=Event);
Decide(SampleSeq:=ULINT#1,Decision:=USINT#3,Reason:=USINT#4,ReportSkipped:=ULINT#0,Buffer:=Buffer);
Checks[10]:=(Buffer.AuditEvents[1].DecisionFlags AND BYTE#8)=BYTE#0;
Decide(SampleSeq:=ULINT#1,Decision:=USINT#2,Reason:=USINT#0,ReportSkipped:=ULINT#0,Buffer:=Buffer);
Checks[11]:=NOT Buffer.EvidenceComplete AND (Buffer.AuditEvents[1].Decision=3);
Buffer.EvidenceComplete:=TRUE; Buffer.AuditFactsComplete:=TRUE;
Cursor.NextDueMonoMs:=100;
Poll(NowMs:=ULINT#11100,PeriodMs:=UDINT#5000,Cursor:=Cursor,Buffer:=Buffer);
Checks[12]:=(Poll.NominalDueMs=10100) AND (Cursor.NextDueMonoMs=15100) AND (Cursor.PollSkippedPending=2);
Checks[13]:=Buffer.MissedPollCyclesTotal=2;
Buffer.ActiveSlot:=1; Buffer.LayoutValid:=TRUE; Buffer.NextSampleSeq:=0;
Buffer.SamplingGeneration:=1; Buffer.Configs[1].Generation:=1;
Buffer.Configs[1].Config.Points[1].reportMode:='cyclic';
Buffer.Configs[1].Config.Points[1].reportIntervalMs:=5000;
Buffer.Cursors[1].Enabled:=TRUE; Buffer.Cursors[1].ActivatedMonoMs:=100;
Buffer.Cursors[1].NextDueMonoMs:=15100; Buffer.Cursors[1].PollSkippedPending:=2;
Buffer.ClockRevision:=2; Buffer.TimeValid:=TRUE; Buffer.DecisionSnapshotMonoMs:=11100;
Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#7.0,
    NowMs:=ULINT#11100,NominalDueMs:=ULINT#10100,SystemUtcMs:=ULINT#100000,
    Cursor:=Buffer.Cursors[1],Buffer:=Buffer);
Checks[14]:=(Buffer.AuditEvents[1].Event.PollSkippedBefore=2) AND (Buffer.Cursors[1].PollSkippedPending=0);
Buffer.TimeValid:=FALSE; Buffer.ClockRevision:=3; Buffer.DecisionSnapshotMonoMs:=12000;
Policy(DeferCapacity:=FALSE,Buffer:=Buffer);
Checks[15]:=(Buffer.AuditEvents[1].Decision=3) AND (Buffer.AuditEvents[1].Reason=4);
Checks[16]:=(Buffer.AuditEvents[1].DecisionFlags=BYTE#59) AND (Buffer.AuditEvents[1].DecisionRevisionDelta=1);
Checks[17]:=(Buffer.AuditEvents[1].DecisionDelayLo=900) AND (Buffer.AuditEvents[1].ReportSkipped=2);
Checks[18]:=(Buffer.MissedReportSlotsTotal=2) AND (Buffer.AuditEvents[1].Event.CapturedUtcMs=100000);
Event.SampleSeq:=2; Event.Kind:=2; Event.PointIndex:=1;
Event.CompletedMonoMs:=15200; Event.ClockRevision:=4;
Event.SamplingGeneration:=1; Event.Flags:=WORD#3; Event.Quality:=3;
Buffer.Configs[1].Config.Points[1].pollIntervalMs:=5000;
Buffer.DecisionSnapshotMonoMs:=15210; Buffer.ClockRevision:=4; Buffer.TimeValid:=TRUE;
Buffer.Cursors[1].NextDueMonoMs:=20100;
Audit(Buffer:=Buffer,Event:=Event);
Buffer.Ingress[Buffer.Tail]:=Event; Buffer.Tail:=Buffer.Tail MOD 512+1;
Buffer.IngressCount:=Buffer.IngressCount+1; Buffer.Configs[1].References:=Buffer.Configs[1].References+1;
Policy(DeferCapacity:=FALSE,Buffer:=Buffer);
Checks[19]:=(Buffer.AuditEvents[2].DecisionFlags=BYTE#127) AND (Buffer.AuditEvents[2].ReportSkipped=128);
Event.SampleSeq:=3; Event.CompletedMonoMs:=15300; Event.ClockRevision:=5;
Buffer.ClockRevision:=6; Buffer.TimeValid:=FALSE; Buffer.DecisionSnapshotMonoMs:=15310;
Buffer.Cursors[1].NextDueMonoMs:=655100;
Audit(Buffer:=Buffer,Event:=Event);
Buffer.Ingress[Buffer.Tail]:=Event; Buffer.Tail:=Buffer.Tail MOD 512+1;
Buffer.IngressCount:=Buffer.IngressCount+1; Buffer.Configs[1].References:=Buffer.Configs[1].References+1;
Policy(DeferCapacity:=FALSE,Buffer:=Buffer);
Checks[20]:=((Buffer.AuditEvents[3].DecisionFlags AND BYTE#32)=BYTE#0) AND NOT Buffer.AuditFactsComplete;
FOR i:=1 TO 20 DO
    IF Checks[i] THEN Passed:=Passed+1; ELSE FailedChecks:=FailedChecks+1; END_IF;
END_FOR;
Done:=TRUE;
END_PROGRAM
