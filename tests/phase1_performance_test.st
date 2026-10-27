PROGRAM Main
VAR_EXTERNAL
    ESM_DATA : ESM_DAT;
END_VAR
VAR
    Buffer : NG_Buffer;
    Samples : ARRAY[1..320] OF NG_Sample;
    Packets : ARRAY[1..16] OF NG_Packet;
    State : NG_SourceState;
    Result : NG_SourceResult;
    Policy : NG_ReportPolicy;
    Maintenance : NG_BufferMaintenance;
    Builder : NG_BatchBuilder;
    Delivery : NG_DeliveryParallel;
    Drain : NG_AuditDrain;
    Diagnostics : NG_Diagnostics;
    Sequence : ULINT;
    Tick : ULINT;
    Scan : UDINT;
    Stage : UINT;
    SamplesMeasured : UDINT;
    SetupUs : LINT;
    SourceStartupUs : LINT;
    LastUs : LINT;
    MaxUs : LINT;
    MinUs : LINT := LINT#9223372036854775807;
    SumUs : ULINT;
    OverOneMs : UDINT;
    OverPeriod : UDINT;
    Done : BOOL;
    d : INT;
    p : INT;
    slot : UINT;
    SubmitAck : BOOL;
    AckId : NG_Id;
    AckQueue : ARRAY[1..8] OF NG_Id;
    AckHead : UINT := 1;
    AckTail : UINT := 1;
    AckCount : UINT;
    ProfileStart : ULINT;
    ProfileWhole : ULINT;
    ProfileDelta : ULINT;
    ProfileMax : ARRAY[1..8] OF ULINT;
    ProfileSum : ARRAY[1..8] OF ULINT;
    ProfileLast : ARRAY[1..8] OF ULINT;
    ProfileIndex : INT;
END_VAR
IF Done THEN RETURN; END_IF;
IF Stage=0 THEN
    Buffer.ActiveSlot:=1; Buffer.SamplingGeneration:=1; Buffer.LayoutValid:=TRUE; Buffer.AuditEnabled:=TRUE;
    Buffer.Configs[1].Generation:=1; Buffer.Configs[1].GatewayId:='test-gw'; Buffer.Configs[1].CaptureBootId:='test-boot';
    Buffer.Configs[1].Config.Version:=13; Buffer.Configs[1].Config.DeviceCount:=50; Buffer.Configs[1].Config.PointCount:=250;
    Buffer.Configs[1].Config.enabled:=TRUE; Buffer.Configs[1].Config.maxBatchPoints:=64;
    Buffer.RecordBytes:=SIZEOF(Buffer.Scratch); Buffer.LayoutBytes:=SIZEOF(Buffer);
    FOR d:=1 TO 50 DO
        Buffer.Configs[1].Config.Devices[d].deviceId:=CONCAT('d-2113457017974222',TO_STRING(850+d,'{0:d}'));
        Buffer.Configs[1].Config.Devices[d].enabled:=TRUE;
        Buffer.Configs[1].Config.Devices[d].PointStart:=(d-1)*5+1; Buffer.Configs[1].Config.Devices[d].PointCount:=5;
    END_FOR;
    FOR p:=1 TO 250 DO
        Buffer.Configs[1].Config.Points[p].pointId:=CONCAT('p-2113457019169599',TO_STRING(490+p,'{0:d}'));
        Buffer.Configs[1].Config.Points[p].enabled:=TRUE;
        Buffer.Configs[1].Config.Points[p].reportMode:='cyclic'; Buffer.Configs[1].Config.Points[p].reportIntervalMs:=5000;
        Buffer.Configs[1].Config.Points[p].dataType:='float32';
    END_FOR;
    Stage:=1; RETURN;
END_IF;
Scan:=Scan+1; Tick:=TO_ULINT(Scan-1)*20;
LastUs:=ESM_DATA.ESM_INFOS[1].TASK_INFOS[1].LAST_EXEC_DURATION;
IF Scan=1 THEN SetupUs:=LastUs;
ELSE
    IF Scan=2 THEN SourceStartupUs:=LastUs; END_IF;
    SamplesMeasured:=SamplesMeasured+1; MaxUs:=MAX(MaxUs,LastUs); MinUs:=MIN(MinUs,LastUs); SumUs:=SumUs+TO_ULINT(LastUs);
    IF LastUs>1000 THEN OverOneMs:=OverOneMs+1; END_IF;
    IF LastUs>20000 THEN OverPeriod:=OverPeriod+1; END_IF;
END_IF;
ProfileWhole:=GET_MICROSECONDS(TRUE); ProfileStart:=ProfileWhole; Buffer.WorkDeadlineUs:=ProfileWhole+ULINT#850;
Drain(BootId:='test-boot',Buffer:=Buffer);
FOR p:=1 TO 250 DO
IF (Buffer.Cursors[p].Generation<>Buffer.SamplingGeneration) OR NOT Buffer.Cursors[p].Enabled OR
   ((Buffer.Cursors[p].Quality<>3) AND (Tick>=Buffer.Cursors[p].LastPhysicalMonoMs+ULINT#30000)) THEN State(Index:=TO_UINT(p),Enabled:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1792840000000+Tick,StaleAfterMs:=UDINT#30000,CheckStale:=TRUE,Samples:=Samples,Buffer:=Buffer); END_IF; END_FOR;
ProfileLast[1]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
(* 50 parallel device completions on five scans per 5 seconds: 250/5s.
   This fixture has no sockets/SDK/MQTT. Its ACKs test logic cost only. *)
IF (Scan>=11) AND ((Scan-11) MOD 250<5) THEN
    FOR d:=1 TO 50 DO
        p:=(d-1)*5+TO_INT((Scan-11) MOD 250)+1;
        Result(Index:=TO_UINT(p),Value:=LREAL#123.125,Quality:='GOOD',NowMs:=Tick,UnixMs:=ULINT#1792840000000+Tick,
            NominalDueMs:=Tick-Tick MOD 5000,ConfigSlot:=UINT#1,ConfigGeneration:=UDINT#1,SamplingGeneration:=ULINT#1,Samples:=Samples,Buffer:=Buffer);
    END_FOR;
END_IF;
ProfileLast[2]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
Maintenance(GateOpen:=TRUE,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
ProfileLast[3]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
Policy(Buffer:=Buffer);
ProfileLast[4]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
IF Scan MOD 2=0 THEN
Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1792840000000+Tick,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1000,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
ProfileLast[5]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
SubmitAck:=FALSE; AckId:='';
IF (AckCount>0) AND NOT Delivery.AckBusy THEN
    SubmitAck:=TRUE; AckId:=AckQueue[AckHead]; AckHead:=AckHead MOD 8+1; AckCount:=AckCount-1;
END_IF;
Delivery(GateOpen:=TRUE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,
    AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
slot:=Delivery.SendSlot;
IF slot>0 THEN
    IF (Tick>=Buffer.NextSendAt) AND (Tick>=Packets[slot].RetryAtMs) THEN
        Packets[slot].WasSent:=TRUE; Packets[slot].RetryAtMs:=Tick+30000; Buffer.NextSendAt:=Tick+334;
        Buffer.PreferSend:=USINT#3-Buffer.BatchOwners[slot].Category;
        IF AckCount>=8 THEN Buffer.CaptureStopped:=TRUE;
        ELSE AckQueue[AckTail]:=Packets[slot].MessageId; AckTail:=AckTail MOD 8+1; AckCount:=AckCount+1; END_IF;
    END_IF;
END_IF;
ProfileLast[6]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
ELSE
SubmitAck:=FALSE; AckId:='';
IF (AckCount>0) AND NOT Delivery.AckBusy THEN
    SubmitAck:=TRUE; AckId:=AckQueue[AckHead]; AckHead:=AckHead MOD 8+1; AckCount:=AckCount-1;
END_IF;
Delivery(GateOpen:=TRUE,NowMs:=Tick,GatewayId:='test-gw',BootId:='test-boot',SubmitAck:=SubmitAck,AckMessageId:=AckId,
    AckStored:=TRUE,AckRetryable:=FALSE,AckCodes:='',Buffer:=Buffer,Packets:=Packets);
slot:=Delivery.SendSlot;
IF slot>0 THEN
    IF (Tick>=Buffer.NextSendAt) AND (Tick>=Packets[slot].RetryAtMs) THEN
        Packets[slot].WasSent:=TRUE; Packets[slot].RetryAtMs:=Tick+30000; Buffer.NextSendAt:=Tick+334;
        Buffer.PreferSend:=USINT#3-Buffer.BatchOwners[slot].Category;
        IF AckCount>=8 THEN Buffer.CaptureStopped:=TRUE;
        ELSE AckQueue[AckTail]:=Packets[slot].MessageId; AckTail:=AckTail MOD 8+1; AckCount:=AckCount+1; END_IF;
    END_IF;
END_IF;
ProfileLast[6]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1792840000000+Tick,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1000,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
ProfileLast[5]:=GET_MICROSECONDS(TRUE)-ProfileStart; ProfileStart:=GET_MICROSECONDS(TRUE);
END_IF;
Diagnostics(BootId:='test-boot',GatewayId:='test-gw',NowMs:=Tick,Force:=FALSE,Buffer:=Buffer);
Buffer.AuditAckBootId:='test-boot'; Buffer.AuditAckSeq:=Buffer.AuditWriteSeq;
Buffer.AssociationAckBootId:='test-boot'; Buffer.AssociationAckSeq:=Buffer.AssociationWriteSeq;
ProfileLast[7]:=GET_MICROSECONDS(TRUE)-ProfileStart;
ProfileLast[8]:=GET_MICROSECONDS(TRUE)-ProfileWhole;
FOR ProfileIndex:=1 TO 8 DO
    ProfileMax[ProfileIndex]:=MAX(ProfileMax[ProfileIndex],ProfileLast[ProfileIndex]);
    ProfileSum[ProfileIndex]:=ProfileSum[ProfileIndex]+ProfileLast[ProfileIndex];
END_FOR;
IF SamplesMeasured>=600 THEN Done:=TRUE; END_IF;
END_PROGRAM
