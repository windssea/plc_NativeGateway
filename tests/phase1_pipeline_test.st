PROGRAM Main
VAR
    Buffer : NG_Buffer;
    EmptyBuffer : NG_Buffer;
    Packets : ARRAY[1..16] OF NG_Packet;
    EmptyPacket : NG_Packet;
    Capture : NG_Capture;
    Source : NG_SourceState;
    SourceResult : NG_SourceResult;
    Policy : NG_ReportPolicy;
    Maintenance : NG_BufferMaintenance;
    Builder : NG_BatchBuilder;
    Delivery : NG_Delivery;
    EndBatch : NG_EndBatch;
    Prune : NG_PruneTerminal;
    StringHash : NG_StringSHA256;
    HashPayload : NG_Json;
    LongPayload : NG_Json;
    LongDigest : STRING[64];
    LongLength : UDINT;
    LongParts : ARRAY[1..64] OF NG_Text;
    Sequence : ULINT;
    Tick : ULINT;
    Stage : INT;
    Scenario : INT := 1;
    Row : INT;
    Rows : INT;
    Passed : UDINT;
    FailedChecks : UDINT;
    Done : BOOL;
    Checks : ARRAY[1..80] OF BOOL;
    CheckIndex : INT;
    Check : BOOL;
    q : ULINT;
    completed : ULINT;
    value : LREAL;
    quality : USINT;
    kind : USINT;
    utc : ULINT;
    pointIndex : UINT;
    i : INT;
    frozen : INT;
    firstSlot : UINT;
    secondSlot : UINT;
    savedId : NG_Id;
    savedPayload : NG_Json;
    savedDigest : STRING[64];
    savedGeneration : UDINT;
    savedSeq : ULINT;
    SubmitAck : BOOL;
    AckId : NG_Id;
    AckStored : BOOL;
    AckRetryable : BOOL;
    Gate : BOOL;
    budget : UDINT;
    BufferBytes : UDINT;
    RecordBytes : UDINT;
    BudgetBytes : UDINT;
    Tx : NG_Bytes;
    Rx : NG_Bytes;
    Values : NG_Json;
    Item : STRING[1024];
    TxPayload : NG_Json;
    DevicesJson : NG_Json;
    Header : STRING[512];
    Samples : ARRAY[1..320] OF NG_Sample;
    Point : NG_Point;
    Sample : NG_Sample;
    phaseTicks : INT;
    AttemptCount : INT;
    StaleCacheValid : BOOL;
    BudgetDigestHeld : BOOL;
    AttemptClasses : ARRAY[1..8] OF USINT;
    SentCount : INT;
    HistoryCount : INT;
    NewCount : INT;
    HashEmptyObject : STRING[64] := '44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a';
END_VAR
IF Done THEN RETURN; END_IF;
Tick:=Tick+20; CheckIndex:=0;
CASE Stage OF
0:
    Buffer:=EmptyBuffer;
    FOR i:=1 TO 16 DO Packets[i]:=EmptyPacket; END_FOR;
    Buffer.ActiveSlot:=1; Buffer.SamplingGeneration:=1; Buffer.LayoutValid:=TRUE;
    Buffer.Configs[1].Generation:=1; Buffer.Configs[1].GatewayId:='test-gw'; Buffer.Configs[1].CaptureBootId:='test-boot';
    Buffer.Configs[1].Config.Version:=1; Buffer.Configs[1].Config.enabled:=TRUE;
    Buffer.Configs[1].Config.maxBatchPoints:=64; Buffer.Configs[1].Config.batchIntervalMs:=1;
    Buffer.Configs[1].Config.DeviceCount:=1; Buffer.Configs[1].Config.PointCount:=64;
    Buffer.Configs[1].Config.Devices[1].deviceId:='device'; Buffer.Configs[1].Config.Devices[1].enabled:=TRUE;
    Buffer.Configs[1].Config.Devices[1].PointStart:=1; Buffer.Configs[1].Config.Devices[1].PointCount:=64;
    FOR i:=1 TO 64 DO
        Buffer.Configs[1].Config.Points[i].pointId:=CONCAT('p',TO_STRING(i,'{0:d}'));
        Buffer.Configs[1].Config.Points[i].enabled:=TRUE; Buffer.Configs[1].Config.Points[i].dataType:='float64';
        Buffer.Configs[1].Config.Points[i].reportMode:='cyclic'; Buffer.Configs[1].Config.Points[i].reportIntervalMs:=5000;
        Buffer.Cursors[i].Enabled:=TRUE; Buffer.Cursors[i].Generation:=1;
    END_FOR;
    IF (Scenario=3) OR (Scenario=4) OR (Scenario=9) THEN Buffer.Configs[1].Config.Points[1].reportMode:='change'; END_IF;
    IF Scenario=3 THEN Buffer.Configs[1].Config.Points[1].deadband:=LREAL#0.5; END_IF;
    IF Scenario=4 THEN Buffer.Configs[1].Config.Points[1].dataType:='bool'; END_IF;
    Row:=0; Rows:=3;
    CASE Scenario OF 2:Rows:=7; 3:Rows:=5; 4,5,6:Rows:=4; 9:Rows:=2; END_CASE;
    IF Scenario<=9 THEN Stage:=1;
    ELSIF Scenario=10 THEN Stage:=10;
    ELSIF Scenario=11 THEN Stage:=30;
    ELSIF Scenario=12 THEN Stage:=50;
    ELSIF Scenario=13 THEN Stage:=60;
    ELSIF Scenario=14 THEN Stage:=70;
    ELSIF Scenario=15 THEN Stage:=80;
    ELSIF Scenario=16 THEN Stage:=90;
    ELSIF Scenario=17 THEN Stage:=100;
    END_IF;
1:
    Row:=Row+1; q:=TO_ULINT(Row-1)*1000; quality:=2; value:=LREAL#10.0; kind:=1;
    CASE Scenario OF
    1:q:=TO_ULINT(Row-1)*5000;
    2:value:=TO_LREAL(Row);
    3:CASE Row OF 1:value:=LREAL#10.0; 2:value:=LREAL#10.5; 3:value:=LREAL#10.6; 4:value:=LREAL#10.9; 5:value:=LREAL#11.2; END_CASE;
    4:IF Row<=2 THEN value:=LREAL#0.0; ELSE value:=LREAL#1.0; END_IF;
    5:IF (Row=2) OR (Row=3) THEN quality:=5; END_IF;
    6:IF Row=1 THEN kind:=2; quality:=1; q:=0; ELSE q:=TO_ULINT(Row-2)*5000; END_IF;
    7:IF Row=3 THEN q:=12000; END_IF;
    END_CASE;
    completed:=q+10;
    IF Scenario=1 THEN
        IF Row=2 THEN completed:=q+8; ELSIF Row=3 THEN completed:=q+11; END_IF;
    ELSIF Scenario=6 THEN
        IF Row=1 THEN completed:=100; ELSIF Row=2 THEN completed:=110; END_IF;
    END_IF;
    IF ((Scenario=8) OR (Scenario=9)) AND (Row=1) THEN Buffer.HighSlot:=28800; Buffer.OwnedCount:=28800; END_IF;
    IF ((Scenario=8) OR (Scenario=9)) AND (Row=2) THEN Buffer.HighSlot:=0; Buffer.OwnedCount:=0; END_IF;
    Capture(PointIndex:=UINT#1,Kind:=kind,Quality:=quality,Value:=value,NowMs:=completed,NominalDueMs:=q,SystemUtcMs:=q+1000,Buffer:=Buffer);
    Policy(Buffer:=Buffer);
    IF Row=Rows THEN Stage:=2; END_IF;
2:
    CheckIndex:=Scenario;
    CASE Scenario OF
    1:Check:=(Buffer.OwnedCount=3) AND (Buffer.Records[1].SampleSeq=1) AND (Buffer.Records[3].SampleSeq=3);
    2:Check:=(Buffer.OwnedCount=2) AND (Buffer.Records[1].SampleSeq=1) AND (Buffer.Records[2].SampleSeq=6);
    3:Check:=(Buffer.OwnedCount=3) AND (Buffer.Records[1].SampleSeq=1) AND (Buffer.Records[2].SampleSeq=3) AND (Buffer.Records[3].SampleSeq=5);
    4:Check:=(Buffer.OwnedCount=2) AND (Buffer.Records[1].Value=LREAL#0.0) AND (Buffer.Records[2].SampleSeq=3);
    5:Check:=(Buffer.OwnedCount=3) AND (Buffer.Records[2].SampleSeq=2) AND (Buffer.Records[3].SampleSeq=4);
    6:Check:=(Buffer.OwnedCount=4) AND (Buffer.ReportCursors[1].NextDue=15000) AND (Buffer.Records[1].Kind=2);
    7:Check:=(Buffer.OwnedCount=2) AND (Buffer.Records[2].SampleSeq=3) AND (Buffer.MissedReportSlotsTotal=1) AND (Buffer.ReportCursors[1].NextDue=15000);
    8:Check:=(Buffer.OwnedCount=1) AND (Buffer.Records[1].SampleSeq=2) AND (Buffer.KnownUnsentEventsTotal=1) AND (Buffer.EnqueueRejectedAttemptsTotal=1) AND (Buffer.ReportCursors[1].NextDue=5000) AND (Buffer.MissedReportSlotsTotal=0);
    9:Check:=(Buffer.OwnedCount=1) AND (Buffer.Records[1].SampleSeq=2) AND (Buffer.KnownUnsentEventsTotal=1);
    END_CASE;
    Scenario:=Scenario+1; Stage:=0;
10:
    (* Same point's two physical events remain distinct across builder windows. *)
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#10.0,NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1000,Buffer:=Buffer);
    Policy(Buffer:=Buffer);
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#20.0,NowMs:=ULINT#5010,NominalDueMs:=ULINT#5000,SystemUtcMs:=ULINT#6000,Buffer:=Buffer);
    Policy(Buffer:=Buffer); Stage:=11; phaseTicks:=0;
11:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#10000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    frozen:=0; FOR i:=1 TO 16 DO IF Buffer.BatchOwners[i].State=2 THEN frozen:=frozen+1; END_IF; END_FOR;
    phaseTicks:=phaseTicks+1;
    IF (frozen=2) OR (phaseTicks>200) THEN
        CheckIndex:=10; Check:=(frozen=2) AND (Buffer.BatchOwners[1].Count=1) AND (Buffer.BatchOwners[2].Count=1) AND (Packets[1].MessageId<>Packets[2].MessageId) AND (Buffer.Records[Buffer.BatchRefs[1]].SampleSeq=1) AND (Buffer.Records[Buffer.BatchRefs[65]].SampleSeq=2);
        savedId:=Packets[1].MessageId; savedPayload:=Packets[1].Payload; savedDigest:=Buffer.BatchOwners[1].Digest;
        savedGeneration:=Buffer.BatchGenerations[1];
        Packets[1].WasSent:=TRUE; Packets[2].WasSent:=TRUE;
        AckId:=Packets[2].MessageId; AckStored:=TRUE; AckRetryable:=FALSE; SubmitAck:=TRUE; Stage:=12; phaseTicks:=0;
    END_IF;
12:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=AckStored,AckRetryable:=AckRetryable,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE;
    phaseTicks:=phaseTicks+1;
    IF NOT Delivery.AckBusy OR (phaseTicks>200) THEN
        CheckIndex:=11; Check:=(Buffer.StoredConfirmedEventsTotal=1) AND (Buffer.OwnedCount=1) AND (Packets[1].Payload=savedPayload) AND (Buffer.ReportCursors[1].LastSeq=2);
        AckId:=savedId; SubmitAck:=TRUE; Stage:=13; phaseTicks:=0;
    END_IF;
13:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE;
    phaseTicks:=phaseTicks+1;
    IF NOT Delivery.AckBusy OR (phaseTicks>200) THEN
        CheckIndex:=12; Check:=(Buffer.StoredConfirmedEventsTotal=2) AND (Buffer.OwnedCount=0) AND (Buffer.ReportCursors[1].LastSeq=2);
        Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#20.0,NowMs:=ULINT#6010,NominalDueMs:=ULINT#6000,SystemUtcMs:=ULINT#7000,Buffer:=Buffer); Policy(Buffer:=Buffer);
        Stage:=14;
    END_IF;
14:
    CheckIndex:=13; Check:=(Buffer.OwnedCount=0) AND (Buffer.PolicyFilteredEventsTotal=1) AND (Buffer.ReportCursors[1].LastSeq=2);
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#20.0,NowMs:=ULINT#10010,NominalDueMs:=ULINT#10000,SystemUtcMs:=ULINT#11000,Buffer:=Buffer); Policy(Buffer:=Buffer);
    Stage:=15; phaseTicks:=0;
15:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#12000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>200) THEN
        CheckIndex:=14; Check:=(Buffer.BatchGenerations[1]>savedGeneration) AND (Packets[1].MessageId<>savedId);
        AckId:=savedId; SubmitAck:=TRUE; Stage:=16;
    END_IF;
16:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE;
    CheckIndex:=15; Check:=(Buffer.OwnedCount=1) AND (Buffer.BatchOwners[1].State=2) AND (Buffer.StoredConfirmedEventsTotal=2);
    Packets[1].WasSent:=TRUE; savedId:=Packets[1].MessageId; savedPayload:=Packets[1].Payload;
    EndBatch(Slot:=UINT#1,Outcome:=USINT#4,Reason:=USINT#5,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
    AckId:=savedId; SubmitAck:=TRUE; Stage:=17;
17:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE;
    CheckIndex:=16; Check:=(Buffer.UncertainDeliveryEventsTotal=1) AND (Buffer.LateStoredEventsTotal=1) AND (Buffer.StoredConfirmedEventsTotal=3) AND (Buffer.OwnedCount=0);
    SubmitAck:=TRUE; Stage:=18;
18:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE;
    CheckIndex:=17; Check:=(Buffer.LateStoredEventsTotal=1) AND (Buffer.StoredConfirmedEventsTotal=3);
    Stage:=20;
20:
    (* Time invalid rejects only this selected event; prior admitted owner stays. *)
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#30.0,NowMs:=ULINT#15010,NominalDueMs:=ULINT#15000,SystemUtcMs:=ULINT#16000,Buffer:=Buffer); Policy(Buffer:=Buffer);
    savedSeq:=Buffer.Records[Buffer.QueueHead[2]].SampleSeq;
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#40.0,NowMs:=ULINT#20010,NominalDueMs:=ULINT#20000,SystemUtcMs:=ULINT#0,Buffer:=Buffer); Policy(Buffer:=Buffer);
    CheckIndex:=18; Check:=(Buffer.OwnedCount=1) AND (Buffer.TimeInvalidEventsTotal=1) AND (Buffer.KnownUnsentEventsTotal=1) AND (Buffer.Records[Buffer.QueueHead[2]].SampleSeq=savedSeq);
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#40.0,NowMs:=ULINT#21010,NominalDueMs:=ULINT#21000,SystemUtcMs:=ULINT#22000,Buffer:=Buffer); Policy(Buffer:=Buffer);
    Stage:=21;
21:
    CheckIndex:=19; Check:=(Buffer.OwnedCount=2) AND (Buffer.ReportCursors[1].LastSeq=7);
    Buffer.ActiveSlot:=2; Buffer.Configs[2].Generation:=2; Buffer.SamplingGeneration:=2;
    Maintenance(GateOpen:=FALSE,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
    Stage:=22;
22:
    CheckIndex:=20; Check:=(Buffer.OwnedCount=2) AND (Buffer.Configs[1].References=2) AND (Buffer.Records[Buffer.QueueHead[2]].ConfigSlot=1);
    Buffer.ActiveSlot:=1; Buffer.SamplingGeneration:=1;
    Maintenance(GateOpen:=TRUE,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
    Capture(PointIndex:=UINT#2,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#1.0,NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1000,Buffer:=Buffer); Policy(Buffer:=Buffer);
    Stage:=23;
23:
    CheckIndex:=21; Check:=(Buffer.QueueHead[1]<>0) AND (Buffer.QueueHead[2]<>0) AND (Buffer.Records[Buffer.QueueHead[2]].SampleSeq>Buffer.Watermark);
    HashPayload:='abc'; Stage:=24;
24:
    StringHash(Execute:=TRUE,Length:=UDINT#3,Payload:=HashPayload);
    IF StringHash.Done THEN
        CheckIndex:=22; Check:=StringHash.Digest='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'; Stage:=25;
    END_IF;
25:
    RecordBytes:=SIZEOF(Buffer.Scratch); BufferBytes:=SIZEOF(Buffer);
    budget:=SIZEOF(Packets)+SIZEOF(Samples)+SIZEOF(Values)+SIZEOF(Item)+SIZEOF(TxPayload)+SIZEOF(EmptyPacket)+SIZEOF(Sample)+SIZEOF(Point)+SIZEOF(Tx)+SIZEOF(Rx)+SIZEOF(DevicesJson)+SIZEOF(Header)+UDINT#16384+UDINT#135680+UDINT#65536;
    BudgetBytes:=BufferBytes+budget;
    CheckIndex:=23; Check:=(RecordBytes=72) AND (BudgetBytes<=4194304); Stage:=26;
26:
    Scenario:=11; Stage:=0;
30:
    FOR i:=1 TO 16 DO
        Capture(PointIndex:=TO_UINT(i),Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#-1.2345678901234567E300,NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#9007199254740991,Buffer:=Buffer);
    END_FOR;
    Policy(Buffer:=Buffer); Buffer.QueueHead[2]:=0; Buffer.QueueTail[2]:=0;
    FOR i:=1 TO 16 DO
        Packets[i].Payload:='{}'; Packets[i].Length:=2; Packets[i].MessageId:=CONCAT('fixture-',TO_STRING(i,'{0:d}'));
        Buffer.BatchGenerations[i]:=1; Buffer.BatchOwners[i].State:=2; Buffer.BatchOwners[i].Count:=1;
        Buffer.BatchOwners[i].OrderSeq:=TO_ULINT(i); Buffer.BatchOwners[i].ConfigSlot:=1;
        Buffer.BatchOwners[i].Digest:=HashEmptyObject; Buffer.BatchOwners[i].Category:=1;
        IF i>8 THEN Buffer.BatchOwners[i].Category:=2; END_IF;
        Buffer.BatchRefs[(i-1)*64+1]:=TO_UINT(i); Buffer.BatchRefGenerations[(i-1)*64+1]:=Buffer.RecordGenerations[i];
        Buffer.RecordStates[i]:=2;
    END_FOR;
    AttemptCount:=0; phaseTicks:=0; Stage:=31;
31:
    Delivery(GateOpen:=TRUE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=FALSE,AckMessageId:='',AckStored:=FALSE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    phaseTicks:=phaseTicks+1;
    IF Delivery.SendSlot>0 THEN
        firstSlot:=Delivery.SendSlot; AttemptCount:=AttemptCount+1; AttemptClasses[AttemptCount]:=Buffer.BatchOwners[firstSlot].Category;
        Packets[firstSlot].WasSent:=TRUE; Packets[firstSlot].Attempts:=1; Packets[firstSlot].RetryAtMs:=Tick+30000;
        Buffer.NextSendAt:=Tick+334; Buffer.PreferSend:=USINT#3-Buffer.BatchOwners[firstSlot].Category;
    END_IF;
    IF (AttemptCount=8) OR (phaseTicks>500) THEN
        SentCount:=0; HistoryCount:=0; NewCount:=0;
        FOR i:=1 TO 16 DO
            IF Packets[i].WasSent THEN SentCount:=SentCount+1;
                IF Buffer.BatchOwners[i].Category=1 THEN HistoryCount:=HistoryCount+1; ELSE NewCount:=NewCount+1; END_IF;
            END_IF;
        END_FOR;
        CheckIndex:=24; Check:=(AttemptCount=8) AND (SentCount=8) AND (HistoryCount=4) AND (NewCount=4);
        FOR i:=2 TO 8 DO Check:=Check AND (AttemptClasses[i]<>AttemptClasses[i-1]); END_FOR;
        Stage:=32; phaseTicks:=0;
    END_IF;
32:
    Delivery(GateOpen:=TRUE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=FALSE,AckMessageId:='',AckStored:=FALSE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    phaseTicks:=phaseTicks+1;
    IF phaseTicks=30 THEN CheckIndex:=25; Check:=(Delivery.SendSlot=0) AND (Buffer.OwnedCount=16); Tick:=Tick+31000; Stage:=33; phaseTicks:=0; END_IF;
33:
    Delivery(GateOpen:=TRUE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=FALSE,AckMessageId:='',AckStored:=FALSE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    phaseTicks:=phaseTicks+1;
    IF (Delivery.SendSlot>0) OR (phaseTicks>100) THEN
        CheckIndex:=26; Check:=FALSE;
        IF Delivery.SendSlot>0 THEN Check:=Packets[Delivery.SendSlot].WasSent; END_IF;
        firstSlot:=Delivery.SendSlot; AckId:=Packets[firstSlot].MessageId; SubmitAck:=TRUE; phaseTicks:=0; Stage:=34;
    END_IF;
34:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=FALSE,AckRetryable:=TRUE,AckCodes:='STORAGE_ERROR',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE; phaseTicks:=phaseTicks+1;
    IF NOT Delivery.AckBusy OR (phaseTicks>100) THEN
        CheckIndex:=27; Check:=(Packets[firstSlot].RetryAtMs>=Tick+60000) AND (Buffer.StoredConfirmedEventsTotal=0) AND (Buffer.IsolatedEventsTotal=0);
        savedSeq:=Packets[firstSlot].RetryAtMs; Maintenance(GateOpen:=FALSE,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
        Maintenance(GateOpen:=TRUE,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
        Stage:=35;
    END_IF;
35:
    CheckIndex:=28; Check:=(Packets[firstSlot].RetryAtMs=savedSeq) AND (Packets[firstSlot].Attempts=1);
    AckId:=Packets[2].MessageId; Packets[2].WasSent:=TRUE; SubmitAck:=TRUE; Stage:=36; phaseTicks:=0;
36:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=FALSE,AckRetryable:=FALSE,AckCodes:='VALIDATION_ERROR',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE; phaseTicks:=phaseTicks+1;
    IF NOT Delivery.AckBusy OR (phaseTicks>100) THEN
        CheckIndex:=29; Check:=(Buffer.BatchOwners[2].State=3) AND (Buffer.IsolatedEventsTotal=1) AND Packets[2].Dead;
        SubmitAck:=TRUE; Stage:=37; phaseTicks:=0;
    END_IF;
37:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE; phaseTicks:=phaseTicks+1;
    IF NOT Delivery.AckBusy OR (phaseTicks>100) THEN
        CheckIndex:=30; Check:=(Buffer.IsolatedEventsTotal=1) AND (Buffer.StoredConfirmedEventsTotal=0) AND (Buffer.ConflictingAcksTotal=1);
        FOR i:=1 TO 6 DO EndBatch(Slot:=TO_UINT(i),Outcome:=USINT#3,Reason:=USINT#8,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets); END_FOR;
        Stage:=38;
    END_IF;
38:
    Maintenance(GateOpen:=FALSE,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
    Maintenance(GateOpen:=FALSE,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
    frozen:=0; FOR i:=1 TO 16 DO IF Buffer.BatchOwners[i].State=3 THEN frozen:=frozen+1; END_IF; END_FOR;
    CheckIndex:=31; Check:=(frozen=4) AND (Buffer.IsolatedEventsTotal=6) AND (Buffer.DeadPrunedBatchesTotal=2) AND (Buffer.OwnedCount=16);
    Prune(Index:=UINT#1,Buffer:=Buffer); Stage:=39;
39:
    CheckIndex:=32; Check:=(Buffer.IsolatedEventsTotal=6) AND (Buffer.TombstonePrunedBatchesTotal=1) AND (Buffer.OwnedCount=15) AND Buffer.DetailTruncated;
    Packets[15].WasSent:=TRUE; Packets[15].Payload:='{"changed":true}'; Packets[15].Length:=16;
    AckId:=Packets[15].MessageId; SubmitAck:=TRUE; Stage:=40; phaseTicks:=0;
40:
    Delivery(GateOpen:=FALSE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
    SubmitAck:=FALSE; phaseTicks:=phaseTicks+1;
    IF NOT Delivery.AckBusy OR (phaseTicks>100) THEN
        CheckIndex:=33; Check:=Buffer.CaptureStopped AND NOT Buffer.AccountingComplete AND (Buffer.CorruptBatchesTotal=1) AND (Buffer.StoredConfirmedEventsTotal=0) AND (Buffer.UncertainDeliveryEventsTotal=1);
        Scenario:=12; Stage:=0;
    END_IF;
50:
    FOR i:=1 TO 8 DO Capture(PointIndex:=TO_UINT(i),Kind:=USINT#1,Quality:=USINT#2,Value:=TO_LREAL(i),NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1000,Buffer:=Buffer); END_FOR;
    Policy(Buffer:=Buffer);
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#2000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    Stage:=51;
51:
    Builder(GateOpen:=FALSE,NowMs:=Tick,UnixMs:=ULINT#0,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    CheckIndex:=34; Check:=(Buffer.OwnedCount=8) AND (Buffer.BatchOwners[1].State=0) AND (Buffer.Records[Buffer.QueueHead[2]].SampleSeq=1) AND (Buffer.Records[Buffer.QueueTail[2]].SampleSeq=8) AND (Buffer.KnownUnsentEventsTotal=0);
    Scenario:=13; Stage:=0;
60:
    (* Mutating a frozen dictionary requires a new generation, as in the real allocator. *)
    Buffer.Configs[1].Generation:=2;
    Buffer.Configs[1].Config.DeviceCount:=2; Buffer.Configs[1].Config.Devices[1].PointCount:=32;
    Buffer.Configs[1].Config.Devices[1].deviceId:='dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
    Buffer.Configs[1].Config.Devices[2].deviceId:='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
    Buffer.Configs[1].Config.Devices[2].enabled:=TRUE; Buffer.Configs[1].Config.Devices[2].PointStart:=33; Buffer.Configs[1].Config.Devices[2].PointCount:=32;
    FOR i:=1 TO 64 DO
        Buffer.Configs[1].Config.Points[i].pointId:=CONCAT('pppppppppppppppppppppppppppppppppppppppppppppppppppppppppppppp',TO_STRING(i,'{0:d}'));
        Capture(PointIndex:=TO_UINT(i),Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#-1.2345678901234567E300,NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#9007199254740991,Buffer:=Buffer);
    END_FOR;
    Policy(Buffer:=Buffer); Stage:=61; phaseTicks:=0;
61:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#2000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1; frozen:=0; SentCount:=0;
    FOR i:=1 TO 16 DO IF Buffer.BatchOwners[i].State=2 THEN frozen:=frozen+1; SentCount:=SentCount+TO_INT(Buffer.BatchOwners[i].Count); END_IF; END_FOR;
    IF (SentCount=64) OR (phaseTicks>500) THEN
        CheckIndex:=35; Check:=(SentCount=64) AND (frozen>=1) AND (Buffer.OwnedCount=64) AND (Buffer.QueueHead[2]=0);
        FOR i:=1 TO 16 DO IF Buffer.BatchOwners[i].State=2 THEN Check:=Check AND (Packets[i].Length<=16380) AND (Packets[i].Length=TO_UDINT(LEN(Packets[i].Payload))) AND (RIGHT(Packets[i].Payload,2)=']}') AND (Buffer.BatchOwners[i].Count<=64); END_IF; END_FOR;
        LongPayload:=Packets[1].Payload; LongDigest:=Buffer.BatchOwners[1].Digest; LongLength:=Packets[1].Length;
        FOR i:=1 TO 64 DO
            LongParts[i]:='';
            IF (i-1)*256<LEN(LongPayload) THEN LongParts[i]:=MID(LongPayload,MIN(256,LEN(LongPayload)-(i-1)*256),(i-1)*256+1); END_IF;
        END_FOR;
        Stage:=62;
    END_IF;
62:
    Maintenance(GateOpen:=FALSE,NowMs:=ULINT#900010,Buffer:=Buffer,Packets:=Packets);
    Maintenance(GateOpen:=FALSE,NowMs:=ULINT#900010,Buffer:=Buffer,Packets:=Packets);
    CheckIndex:=36; Check:=(Buffer.KnownUnsentEventsTotal=64) AND (Buffer.OwnedCount=0) AND (Buffer.UncertainDeliveryEventsTotal=0);
    Scenario:=14; Stage:=0;
70:
    FOR i:=1 TO 64 DO Capture(PointIndex:=TO_UINT(i),Kind:=USINT#1,Quality:=USINT#2,Value:=TO_LREAL(i),NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1000,Buffer:=Buffer); END_FOR;
    Policy(Buffer:=Buffer); Maintenance(GateOpen:=FALSE,NowMs:=ULINT#900010,Buffer:=Buffer,Packets:=Packets);
    CheckIndex:=37; Check:=(Buffer.KnownUnsentEventsTotal=64) AND (Buffer.OwnedCount=0) AND (Buffer.Configs[1].References=0) AND (Buffer.GapRecordsTotal=64);
    Scenario:=15; Stage:=0; Row:=0;
80:
    FOR i:=1 TO 64 DO
        q:=Buffer.NextSampleSeq*5000;
        Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=TO_LREAL(Buffer.NextSampleSeq),NowMs:=q+10,NominalDueMs:=q,SystemUtcMs:=q+1000,Buffer:=Buffer);
    END_FOR;
    Policy(Buffer:=Buffer);
    IF Buffer.OwnedCount=28800 THEN Stage:=81; END_IF;
81:
    savedSeq:=Buffer.Records[Buffer.QueueHead[2]].SampleSeq;
    FOR i:=1 TO 64 DO
        q:=Buffer.NextSampleSeq*5000;
        Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=TO_LREAL(Buffer.NextSampleSeq),NowMs:=q+10,NominalDueMs:=q,SystemUtcMs:=q+1000,Buffer:=Buffer);
    END_FOR;
    Maintenance(GateOpen:=FALSE,NowMs:=ULINT#0,Buffer:=Buffer,Packets:=Packets); Policy(Buffer:=Buffer);
    CheckIndex:=38; Check:=(Buffer.OwnedCount=28800) AND (Buffer.KnownUnsentEventsTotal=64) AND (Buffer.EnqueueRejectedAttemptsTotal=0) AND (Buffer.Records[Buffer.QueueHead[2]].SampleSeq=savedSeq+64) AND (Buffer.Configs[1].References=28800);
    Stage:=82;
82:
    firstSlot:=Buffer.QueueHead[2]; Buffer.QueueHead[2]:=Buffer.FreeSlots[firstSlot];
    Packets[1].MessageId:='pressure-sent'; Packets[1].Payload:='{}'; Packets[1].Length:=2; Packets[1].WasSent:=TRUE;
    Buffer.BatchOwners[1].State:=2; Buffer.BatchOwners[1].Count:=1; Buffer.BatchOwners[1].Category:=2;
    Buffer.BatchOwners[1].ConfigSlot:=1; Buffer.BatchOwners[1].OrderSeq:=Buffer.Records[firstSlot].SampleSeq;
    Buffer.BatchOwners[1].Digest:=HashEmptyObject; Buffer.BatchRefs[1]:=firstSlot;
    Buffer.BatchRefGenerations[1]:=Buffer.RecordGenerations[firstSlot]; Buffer.RecordStates[firstSlot]:=2;
    q:=Buffer.NextSampleSeq*5000;
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#1.0,NowMs:=q+10,NominalDueMs:=q,SystemUtcMs:=q+1000,Buffer:=Buffer);
    Maintenance(GateOpen:=FALSE,NowMs:=ULINT#0,Buffer:=Buffer,Packets:=Packets); Policy(DeferCapacity:=TRUE,Buffer:=Buffer); Stage:=83;
83:
    CheckIndex:=41; Check:=(Buffer.OwnedCount=28800) AND (Buffer.UncertainDeliveryEventsTotal=1) AND (Buffer.TombstonePrunedBatchesTotal=1) AND (Buffer.KnownUnsentEventsTotal=64) AND (Buffer.IngressCount=0) AND (Buffer.Configs[1].References=28800);
    Scenario:=16; Stage:=0;
90:
    Buffer.Configs[1].Config.Points[1].staleAfterMs:=3000;
    Buffer.Cursors[1].Enabled:=FALSE;
    Source(Index:=UINT#1,Enabled:=TRUE,NowMs:=ULINT#1000,UnixMs:=ULINT#2000,StaleAfterMs:=UDINT#3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    StaleCacheValid:=Buffer.SourceStaleDue[1]=4000;
    FOR i:=0 TO 2 DO
        q:=ULINT#1010+TO_ULINT(i)*1000;
        SourceResult(Index:=UINT#1,Value:=LREAL#0.0,Quality:='BAD_TIMEOUT',NowMs:=q,UnixMs:=q+1000,NominalDueMs:=q-10,ConfigSlot:=UINT#1,ConfigGeneration:=UDINT#1,SamplingGeneration:=ULINT#1,Samples:=Samples,Buffer:=Buffer);
        StaleCacheValid:=StaleCacheValid AND (Buffer.SourceStaleDue[1]=q+3000);
        Source(Index:=UINT#1,Enabled:=TRUE,NowMs:=q,UnixMs:=q+1000,StaleAfterMs:=UDINT#3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    END_FOR;
    Source(Index:=UINT#1,Enabled:=TRUE,NowMs:=ULINT#6009,UnixMs:=ULINT#7009,StaleAfterMs:=UDINT#3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer);
    StaleCacheValid:=StaleCacheValid AND (Buffer.SourceStaleDue[1]=6010);
    savedSeq:=Buffer.CapturedEventsTotal;
    FOR i:=1 TO 100 DO Source(Index:=UINT#1,Enabled:=TRUE,NowMs:=ULINT#6010+TO_ULINT(i-1),UnixMs:=ULINT#7010+TO_ULINT(i-1),StaleAfterMs:=UDINT#3000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer); END_FOR;
    Policy(Buffer:=Buffer); Stage:=91;
91:
    CheckIndex:=39; Check:=StaleCacheValid AND (Buffer.SourceStaleDue[1]=0) AND (savedSeq=4) AND (Buffer.CapturedEventsTotal=5) AND (Buffer.OwnedCount=3) AND (Buffer.PolicyFilteredEventsTotal=2) AND (Samples[1].Quality='STALE') AND (Samples[1].LastGoodMs=0);
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#1.0,NowMs:=ULINT#10010,NominalDueMs:=ULINT#10000,SystemUtcMs:=ULINT#11000,Buffer:=Buffer);
    Buffer.ActiveSlot:=2; Buffer.SamplingGeneration:=2; Policy(Buffer:=Buffer); Stage:=92;
92:
    CheckIndex:=40; Check:=(Buffer.UndecidedLostEventsTotal=1) AND (Buffer.EligibleEventsTotal=3) AND (Buffer.PolicyFilteredEventsTotal=2) AND (Buffer.OwnedCount=3) AND NOT Buffer.AccountingComplete AND (Buffer.Gaps[Buffer.GapIndex].Reason=2);
    Stage:=93;
93:
    HashPayload:=LongPayload;
    StringHash(Execute:=FALSE,Length:=LongLength,DeadlineUs:=ULINT#1,Payload:=HashPayload);
    StringHash(Execute:=TRUE,Length:=LongLength,DeadlineUs:=ULINT#1,Payload:=HashPayload);
    BudgetDigestHeld:=StringHash.Busy AND NOT StringHash.Done;
    phaseTicks:=0; Stage:=94;
94:
    (* An expired absolute deadline may not advance an in-progress digest.
       Fresh bounded slices must still produce the independent long vector. *)
    savedDigest:=StringHash.Digest;
    StringHash(Execute:=TRUE,Length:=LongLength,DeadlineUs:=ULINT#1,Payload:=HashPayload);
    BudgetDigestHeld:=BudgetDigestHeld AND (savedDigest=StringHash.Digest) AND StringHash.Busy AND NOT StringHash.Done;
    StringHash(Execute:=TRUE,Length:=LongLength,DeadlineUs:=GET_MICROSECONDS(TRUE)+ULINT#250,Payload:=HashPayload);
    phaseTicks:=phaseTicks+1;
    IF StringHash.Done OR (phaseTicks>2000) THEN Stage:=95; END_IF;
95:
    CheckIndex:=42; Check:=StringHash.Done AND NOT StringHash.Error AND (StringHash.Digest=LongDigest);
    Stage:=96;
96:
    CheckIndex:=43; Check:=BudgetDigestHeld;
    Stage:=97;
97:
    Scenario:=17; Stage:=0;
100:
    Buffer.Configs[1].Config.Devices[1].deviceId:='new"device';
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#1.0,NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1000,Buffer:=Buffer);
    Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=101;
101:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#2000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>500) THEN
        CheckIndex:=44; Check:=(Buffer.BatchOwners[1].Count=1) AND (FIND(Packets[1].Payload,CONCAT('"deviceId":',NG_Quote('new"device')))>0);
        EndBatch(Slot:=UINT#1,Outcome:=USINT#2,Reason:=USINT#0,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
        Stage:=102;
    END_IF;
102:
    Buffer.Configs[1].Generation:=2; Buffer.Configs[1].Config.Devices[1].deviceId:='changed"device';
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#2.0,NowMs:=ULINT#5010,NominalDueMs:=ULINT#5000,SystemUtcMs:=ULINT#6000,Buffer:=Buffer);
    Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=103;
103:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#7000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>500) THEN
        CheckIndex:=45; Check:=(Buffer.BatchOwners[1].Count=1) AND (FIND(Packets[1].Payload,CONCAT('"deviceId":',NG_Quote('changed"device')))>0) AND (FIND(Packets[1].Payload,NG_Quote('new"device'))=0);
        EndBatch(Slot:=UINT#1,Outcome:=USINT#2,Reason:=USINT#0,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
        Stage:=104;
    END_IF;
104:
    Buffer.Configs[2]:=Buffer.Configs[1]; Buffer.ActiveSlot:=2;
    Buffer.Configs[2].Config.Devices[1].deviceId:='other"slot';
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#3.0,NowMs:=ULINT#10010,NominalDueMs:=ULINT#10000,SystemUtcMs:=ULINT#11000,Buffer:=Buffer);
    Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=105;
105:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#12000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>500) THEN
        CheckIndex:=46; Check:=(Buffer.BatchOwners[1].Count=1) AND (FIND(Packets[1].Payload,CONCAT('"deviceId":',NG_Quote('other"slot')))>0) AND (FIND(Packets[1].Payload,NG_Quote('changed"device'))=0);
        Stage:=106;
    END_IF;
106:
    Done:=TRUE;
END_CASE;
IF CheckIndex>0 THEN
    Checks[CheckIndex]:=Check;
    IF Check THEN Passed:=Passed+1; ELSE FailedChecks:=FailedChecks+1; END_IF;
END_IF;
END_PROGRAM
