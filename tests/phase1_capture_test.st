PROGRAM Main
VAR
    Buffer : NG_Buffer;
    Samples : ARRAY[1..320] OF NG_Sample;
    Config : NG_Config;
    Selector : NG_ConfigSlot;
    Source : NG_SourceState;
    Result : NG_SourceResult;
    Poll : NG_PollSlot;
    Capture : NG_Capture;
    Compare : NG_SameConfig;
    Stage : INT;
    Passed : UDINT;
    FailedChecks : UDINT;
    Done : BOOL;
    Check : BOOL;
    Checks : ARRAY[1..40] OF BOOL;
    RecordBytes : UDINT;
    BufferBytes : UDINT;
    BudgetBytes : UDINT;
    DummyPacket : NG_Packet;
    Packets : ARRAY[1..16] OF NG_Packet;
    Values : NG_Json;
    TxPayload : NG_Json;
    Item : STRING[1024];
    Point : NG_Point;
    Sample : NG_Sample;
    Tx : NG_Bytes;
    Rx : NG_Bytes;
    n : INT;
    PreviousSeq : ULINT;
    PreviousCaptured : ULINT;
    OldSlot : UINT;
    OldGeneration : UDINT;
    HashBefore : ULINT;
END_VAR
IF Done THEN RETURN; END_IF;
Check:=FALSE;
CASE Stage OF
0:
    RecordBytes:=SIZEOF(Buffer.Scratch); BufferBytes:=SIZEOF(Buffer);
    BudgetBytes:=BufferBytes+SIZEOF(Packets)+SIZEOF(Samples)+SIZEOF(Values)+SIZEOF(Item)+SIZEOF(TxPayload)+SIZEOF(DummyPacket)+SIZEOF(Sample)+SIZEOF(Point)+SIZEOF(Tx)+SIZEOF(Rx)+UDINT#16384+UDINT#135680+UDINT#65536;
    Buffer.LayoutValid:=BudgetBytes<=UDINT#4194304;
    Config.Version:=1; Config.MessageId:='capture-test-1'; Config.enabled:=TRUE;
    Config.DeviceCount:=1; Config.PointCount:=3;
    Config.Devices[1].deviceId:='D1'; Config.Devices[1].PointStart:=1; Config.Devices[1].PointCount:=3;
    FOR n:=1 TO 3 DO Config.Points[n].enabled:=TRUE; Config.Points[n].pollIntervalMs:=1000; END_FOR;
    Config.Points[1].pointId:='P1'; Config.Points[2].pointId:='P2'; Config.Points[3].pointId:='P3';
    Selector(GatewayId:='TEST',CaptureBootId:='BOOT',Config:=Config,Buffer:=Buffer);
    Buffer.ActiveSlot:=Selector.Slot; Buffer.Configs[Selector.Slot].Reserved:=FALSE; Buffer.SamplingGeneration:=1;
    Check:=(Selector.Slot>0) AND Buffer.LayoutValid;
1: (* UNKNOWN once; nominal slot is absent; O comes from activation. *)
    Source(Index:=1,Enabled:=TRUE,NowMs:=100,UnixMs:=100000,StaleAfterMs:=3000,CheckStale:=FALSE,Samples:=Samples,Buffer:=Buffer);
    Check:=Source.Accepted AND (Buffer.IngressCount=1) AND (Buffer.Ingress[1].Kind=2) AND (Buffer.Ingress[1].Quality=1) AND (Buffer.Cursors[1].NextDueMonoMs=100) AND ((Buffer.Ingress[1].Flags AND WORD#4)=WORD#0);
2:
    Source(Index:=1,Enabled:=TRUE,NowMs:=200,UnixMs:=100000,StaleAfterMs:=3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    Check:=(Buffer.CapturedEventsTotal=1) AND (Buffer.Cursors[1].NextDueMonoMs=100);
3: (* Final BAD counts as physical liveness. *)
    Poll(NowMs:=1100,PeriodMs:=1000,Cursor:=Buffer.Cursors[1],Buffer:=Buffer);
    Result(Index:=1,Value:=LREAL#123.0,Quality:='BAD_TIMEOUT',NowMs:=1110,UnixMs:=101000,NominalDueMs:=Poll.NominalDueMs,ConfigSlot:=Buffer.ActiveSlot,ConfigGeneration:=Buffer.Configs[Buffer.ActiveSlot].Generation,SamplingGeneration:=1,Samples:=Samples,Buffer:=Buffer);
    Check:=Result.Accepted AND (Buffer.MissedPollCyclesTotal=1) AND (Buffer.Ingress[2].Value=0) AND (Buffer.Ingress[2].NominalDueMonoMs=1100) AND (Buffer.Cursors[1].NextDueMonoMs=2100);
4:
    Source(Index:=1,Enabled:=TRUE,NowMs:=4000,UnixMs:=101000,StaleAfterMs:=3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    Check:=(Buffer.CapturedEventsTotal=2) AND (Samples[1].Quality='BAD_TIMEOUT');
5:
    Result(Index:=1,Value:=LREAL#0.0,Quality:='BAD_TIMEOUT',NowMs:=4100,UnixMs:=101000,NominalDueMs:=2100,ConfigSlot:=Buffer.ActiveSlot,ConfigGeneration:=Buffer.Configs[Buffer.ActiveSlot].Generation,SamplingGeneration:=1,Samples:=Samples,Buffer:=Buffer);
    Source(Index:=1,Enabled:=TRUE,NowMs:=4100,UnixMs:=101000,StaleAfterMs:=3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    Check:=(Buffer.CapturedEventsTotal=3) AND (Buffer.SourceTimestampRepeatTotal=1) AND (Samples[1].Quality='BAD_TIMEOUT');
6: (* STALE at the exact boundary, once. *)
    Source(Index:=1,Enabled:=TRUE,NowMs:=7100,UnixMs:=107000,StaleAfterMs:=3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    Check:=(Buffer.CapturedEventsTotal=4) AND (Buffer.Ingress[4].Kind=2) AND (Buffer.Ingress[4].Quality=3) AND (Buffer.Ingress[4].CompletedMonoMs=7100);
7:
    Source(Index:=1,Enabled:=TRUE,NowMs:=7200,UnixMs:=108000,StaleAfterMs:=3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    Check:=(Buffer.CapturedEventsTotal=4);
8: (* GOOD scalar is frozen, never rescaled by capture. *)
    Result(Index:=1,Value:=LREAL#42.25,Quality:='GOOD',NowMs:=7300,UnixMs:=109000,NominalDueMs:=3100,ConfigSlot:=Buffer.ActiveSlot,ConfigGeneration:=Buffer.Configs[Buffer.ActiveSlot].Generation,SamplingGeneration:=1,Samples:=Samples,Buffer:=Buffer);
    Check:=(Buffer.CapturedEventsTotal=5) AND (Buffer.Ingress[5].Value=LREAL#42.25) AND (Buffer.Ingress[5].CapturedUtcMs=109000) AND ((Buffer.Ingress[5].Flags AND WORD#10)=WORD#8);
9: (* Equal RTC remains two events. *)
    Result(Index:=1,Value:=LREAL#43.25,Quality:='GOOD',NowMs:=7310,UnixMs:=109000,NominalDueMs:=4100,ConfigSlot:=Buffer.ActiveSlot,ConfigGeneration:=Buffer.Configs[Buffer.ActiveSlot].Generation,SamplingGeneration:=1,Samples:=Samples,Buffer:=Buffer);
    Check:=(Buffer.CapturedEventsTotal=6) AND (Buffer.SourceTimestampRepeatTotal=2) AND (Buffer.Ingress[5].Value=LREAL#42.25) AND (Buffer.Ingress[6].Value=LREAL#43.25);
10: (* RTC invalid is null, no later backfill. *)
    Result(Index:=1,Value:=LREAL#44.0,Quality:='GOOD',NowMs:=7400,UnixMs:=0,NominalDueMs:=5100,ConfigSlot:=Buffer.ActiveSlot,ConfigGeneration:=Buffer.Configs[Buffer.ActiveSlot].Generation,SamplingGeneration:=1,Samples:=Samples,Buffer:=Buffer);
    Check:=((Buffer.Ingress[7].Flags AND WORD#1)=WORD#0) AND (Buffer.Ingress[7].CapturedUtcMs=0) AND (Buffer.Ingress[5].CapturedUtcMs=109000);
11: (* Per-point missed slots in an N-point logical block. *)
    FOR n:=2 TO 3 DO
        Source(Index:=TO_UINT(n),Enabled:=TRUE,NowMs:=100,UnixMs:=100000,StaleAfterMs:=3000,CheckStale:=FALSE,Samples:=Samples,Buffer:=Buffer);
        Poll(NowMs:=3100,PeriodMs:=1000,Cursor:=Buffer.Cursors[n],Buffer:=Buffer);
    END_FOR;
    Check:=(Buffer.MissedPollCyclesTotal=7) AND (Buffer.Cursors[2].NextDueMonoMs=4100) AND (Buffer.Cursors[3].NextDueMonoMs=4100);
12: (* Old read revoked, no new event or source-view mutation. *)
    PreviousCaptured:=Buffer.CapturedEventsTotal;
    Result(Index:=1,Value:=LREAL#99.0,Quality:='GOOD',NowMs:=7500,UnixMs:=110000,NominalDueMs:=6100,ConfigSlot:=Buffer.ActiveSlot,ConfigGeneration:=0,SamplingGeneration:=1,Samples:=Samples,Buffer:=Buffer);
    Check:=NOT Result.Accepted AND (Buffer.CapturedEventsTotal=PreviousCaptured) AND (Samples[1].Value=LREAL#44.0) AND (Buffer.CancelledReadsTotal=1) AND (Buffer.CancellationReason=2);
13: (* Idempotent config application keeps slot and sampling origin. *)
    OldSlot:=Buffer.ActiveSlot; OldGeneration:=Buffer.Configs[OldSlot].Generation;
    Selector(GatewayId:='TEST',CaptureBootId:='BOOT',Config:=Config,Buffer:=Buffer);
    Check:=(Selector.Slot=OldSlot) AND (Buffer.Configs[OldSlot].Generation=OldGeneration) AND (Buffer.Configs[OldSlot].References=Buffer.IngressCount);
14: (* All versions retained, old slot is immutable. *)
    Config.Version:=2; Config.MessageId:='capture-test-2'; Config.Points[1].scale:=2;
    Selector(GatewayId:='TEST',CaptureBootId:='BOOT',Config:=Config,Buffer:=Buffer);
    Buffer.ActiveSlot:=Selector.Slot; Buffer.Configs[Selector.Slot].Reserved:=FALSE; Buffer.SamplingGeneration:=2;
    Check:=(Selector.Slot<>OldSlot) AND (Buffer.Configs[OldSlot].Config.Version=1) AND (Buffer.Ingress[5].ConfigGeneration=OldGeneration) AND (Buffer.Ingress[5].Value=LREAL#42.25);
15:
    Source(Index:=1,Enabled:=TRUE,NowMs:=8000,UnixMs:=111000,StaleAfterMs:=3000,CheckStale:=FALSE,Samples:=Samples,Buffer:=Buffer);
    Check:=Source.Accepted AND (Buffer.Cursors[1].NextDueMonoMs=8000) AND (Samples[1].Quality='UNKNOWN');
16: (* Pin all four dictionaries. Fifth version cannot replace current/history. *)
    FOR n:=3 TO 4 DO
        Config.Version:=TO_ULINT(n);
        Selector(GatewayId:='TEST',CaptureBootId:='BOOT',Config:=Config,Buffer:=Buffer);
        Buffer.ActiveSlot:=Selector.Slot; Buffer.Configs[Selector.Slot].Reserved:=FALSE;
        Buffer.SamplingGeneration:=TO_ULINT(n);
        Capture(PointIndex:=1,Kind:=2,Quality:=1,Value:=LREAL#0.0,NowMs:=9000,NominalDueMs:=0,SystemUtcMs:=112000,Buffer:=Buffer);
    END_FOR;
    OldSlot:=Buffer.ActiveSlot; Config.Version:=5;
    Selector(GatewayId:='TEST',CaptureBootId:='BOOT',Config:=Config,Buffer:=Buffer);
    Check:=(Selector.Slot=0) AND (Buffer.ActiveSlot=OldSlot) AND (Buffer.Configs[OldSlot].Config.Version=4) AND (Buffer.Configs[1].Config.Version=1);
17: (* Queue fill one bounded capture per scan. *)
    IF Buffer.IngressCount<512 THEN
        Capture(PointIndex:=1,Kind:=1,Quality:=2,Value:=LREAL#12.0,NowMs:=10000,NominalDueMs:=10000,SystemUtcMs:=112000,Buffer:=Buffer);
        RETURN;
    END_IF;
    PreviousSeq:=Buffer.NextSampleSeq; PreviousCaptured:=Buffer.CapturedEventsTotal;
    Check:=(Buffer.CaptureOverflowEventsTotal=0);
18:
    Capture(PointIndex:=1,Kind:=1,Quality:=2,Value:=LREAL#99.0,NowMs:=10001,NominalDueMs:=10000,SystemUtcMs:=112000,Buffer:=Buffer);
    Check:=NOT Capture.Accepted AND (Buffer.IngressCount=512) AND (Buffer.CaptureOverflowEventsTotal=1) AND (Buffer.UndecidedLostEventsTotal=1) AND (Buffer.NextSampleSeq=PreviousSeq+1) AND (Buffer.CapturedEventsTotal=PreviousCaptured+1) AND (Buffer.Ingress[5].Value=LREAL#42.25) AND (Buffer.Gaps[1].PointId='P1');
19: (* Bounded detail ring; totals remain exact. *)
    FOR n:=1 TO 64 DO
        Capture(PointIndex:=1,Kind:=1,Quality:=5,Value:=LREAL#0.0,NowMs:=10002,NominalDueMs:=10000,SystemUtcMs:=112000,Buffer:=Buffer);
    END_FOR;
    Check:=(Buffer.CaptureOverflowEventsTotal=65) AND (Buffer.UndecidedLostEventsTotal=65) AND Buffer.DetailTruncated AND (Buffer.GapIndex=1);
20:
    Check:=(NG_SafeAdd(ULINT#9007199254740990,ULINT#10)=ULINT#9007199254740991) AND (NG_SafeAdd(ULINT#7,ULINT#4)=11);
21: (* Exhausted sample identity fails closed, never wraps. *)
    Buffer.NextSampleSeq:=ULINT#9007199254740991; PreviousCaptured:=Buffer.CapturedEventsTotal;
    Capture(PointIndex:=1,Kind:=1,Quality:=2,Value:=LREAL#99.0,NowMs:=11000,NominalDueMs:=11000,SystemUtcMs:=113000,Buffer:=Buffer);
    Check:=NOT Capture.Accepted AND Buffer.CaptureStopped AND (Buffer.CapturedEventsTotal=PreviousCaptured) AND (Buffer.NextSampleSeq=ULINT#9007199254740991);
ELSE Done:=TRUE; RETURN;
END_CASE;
Checks[Stage+1]:=Check;
IF Check THEN Passed:=Passed+1; ELSE FailedChecks:=FailedChecks+1; END_IF;
Stage:=Stage+1;
END_PROGRAM
