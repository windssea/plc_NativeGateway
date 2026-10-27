(* Included only by --slice-assertions in the no-I/O harness. *)
110:
    EndBatch(Slot:=UINT#1,Outcome:=USINT#2,Reason:=USINT#0,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
    Capture(PointIndex:=UINT#2,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#1.0,NowMs:=ULINT#15010,NominalDueMs:=ULINT#15000,SystemUtcMs:=ULINT#16000,Buffer:=Buffer);
    Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=111;
111:
    Buffer.WorkDeadlineUs:=0;
    Builder(SliceTestHold:=TRUE,GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#17000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF Builder.SliceTestPending OR (phaseTicks>500) THEN
        savedGeneration:=Buffer.RecordGenerations[Buffer.QueueHead[2]]; firstSlot:=Buffer.QueueHead[2];
        CheckIndex:=47; Check:=Builder.SliceTestPending AND (Buffer.BatchOwners[1].Count=0) AND (firstSlot>0) AND (Buffer.RecordStates[firstSlot]=1);
        Maintenance(GateOpen:=FALSE,NowMs:=ULINT#1000010,Buffer:=Buffer,Packets:=Packets);
        Capture(PointIndex:=UINT#2,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#2.0,NowMs:=ULINT#1000020,NominalDueMs:=ULINT#1000000,SystemUtcMs:=ULINT#1001000,Buffer:=Buffer);
        Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=112;
    END_IF;
112:
    Builder(SliceTestHold:=FALSE,GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1002000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>500) THEN
        CheckIndex:=48; Check:=(Buffer.BatchOwners[1].Count=1) AND (Buffer.RecordGenerations[firstSlot]<>savedGeneration) AND (FIND(Packets[1].Payload,CONCAT('"value":',TO_STRING(LREAL#2.0,'{0:E16}')))>0) AND (FIND(Packets[1].Payload,CONCAT('"value":',TO_STRING(LREAL#1.0,'{0:E16}')))=0);
        EndBatch(Slot:=UINT#1,Outcome:=USINT#2,Reason:=USINT#0,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
        Capture(PointIndex:=UINT#3,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#3.0,NowMs:=ULINT#1005010,NominalDueMs:=ULINT#1005000,SystemUtcMs:=ULINT#1006000,Buffer:=Buffer);
        Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=113;
    END_IF;
113:
    Builder(SliceTestHold:=TRUE,GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1007000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF Builder.SliceTestPending OR (phaseTicks>500) THEN Stage:=114; END_IF;
114:
    firstSlot:=Buffer.QueueHead[2];
    Builder(SliceTestHold:=FALSE,GateOpen:=FALSE,NowMs:=Tick,UnixMs:=ULINT#1007000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    CheckIndex:=49; Check:=(firstSlot>0) AND (Buffer.QueueHead[2]=firstSlot) AND (Buffer.RecordStates[firstSlot]=1) AND (Buffer.BatchOwners[1].State=0) AND NOT Buffer.CaptureStopped;
    phaseTicks:=0; Stage:=115;
115:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1007000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>500) THEN
        CheckIndex:=50; Check:=(Buffer.BatchOwners[1].Count=1) AND (FIND(Packets[1].Payload,CONCAT('"value":',TO_STRING(LREAL#3.0,'{0:E16}')))>0) AND NOT Buffer.CaptureStopped;
        Stage:=116;
    END_IF;
116:
    CheckIndex:=51; Check:=(NG_Quote('')='""') AND (NG_Quote('plain-id')='"plain-id"'); Stage:=117;
117:
    CheckIndex:=52; Check:=NG_Quote('a"b\\c')='"a\\"b\\\\c"'; Stage:=118;
118:
    HashPayload:='a\nb c'; quality:=13;
    firstSlot:=MEMORY_COPY(quality,UDINT#0,HashPayload,UDINT#7,UDINT#1);
    CheckIndex:=53; Check:=(firstSlot=0) AND (NG_Quote(HashPayload)='"a\\nb\\rc"'); Stage:=119;
119:
    CheckIndex:=54; Check:=NG_Quote('a\tb')='"a\\tb"'; Stage:=120;
120:
    EndBatch(Slot:=UINT#1,Outcome:=USINT#2,Reason:=USINT#0,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
    Capture(PointIndex:=UINT#1,Kind:=USINT#2,Quality:=USINT#5,Value:=LREAL#0.0,NowMs:=ULINT#1006010,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1006000,Buffer:=Buffer);
    Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=121;
121:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1007000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>500) THEN
        CheckIndex:=55; Check:=(FIND(Packets[1].Payload,'"quality":"BAD_TIMEOUT"')>0) AND (FIND(Packets[1].Payload,'"timestamp":1006000')>0) AND (FIND(Packets[1].Payload,'"value":null')>0);
        EndBatch(Slot:=UINT#1,Outcome:=USINT#2,Reason:=USINT#0,NowMs:=Tick,Buffer:=Buffer,Packets:=Packets);
        Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#4.0,NowMs:=ULINT#1010010,NominalDueMs:=ULINT#1010000,SystemUtcMs:=ULINT#1011000,Buffer:=Buffer);
        Policy(Buffer:=Buffer); phaseTicks:=0; Stage:=122;
    END_IF;
122:
    Builder(GateOpen:=TRUE,NowMs:=Tick,UnixMs:=ULINT#1012000,GatewayId:='test-gw',BootId:='test-boot',BatchIntervalMs:=UDINT#1,Buffer:=Buffer,Packets:=Packets,Sequence:=Sequence);
    phaseTicks:=phaseTicks+1;
    IF (Buffer.BatchOwners[1].State=2) OR (phaseTicks>500) THEN
        CheckIndex:=56; Check:=(FIND(Packets[1].Payload,'"quality":"GOOD"')>0) AND (FIND(Packets[1].Payload,'"timestamp":1011000')>0) AND (FIND(Packets[1].Payload,'"value":null')=0);
        Stage:=124;
    END_IF;
124:
    Done:=TRUE;
