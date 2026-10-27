PROGRAM Main
VAR
    Buffer : NG_Buffer;
    Capture : NG_Capture;
    Policy : NG_ReportPolicy;
    Drain : NG_AuditDrain;
    Associate : NG_AuditAssociation;
    Diagnostics : NG_Diagnostics;
    Stage : INT;
    Checks : ARRAY[1..16] OF BOOL;
    Passed : UINT;
    FailedChecks : UINT;
    Done : BOOL;
    i : INT;
END_VAR
IF Done THEN RETURN; END_IF;
CASE Stage OF
0:
    Buffer.ActiveSlot:=1; Buffer.LayoutValid:=TRUE; Buffer.SamplingGeneration:=1;
    Buffer.Configs[1].Generation:=1; Buffer.Configs[1].GatewayId:='test-gw'; Buffer.Configs[1].CaptureBootId:='test-boot';
    Buffer.Configs[1].Config.Version:=13; Buffer.Configs[1].Config.DeviceCount:=1;
    Buffer.Configs[1].Config.PointCount:=1; Buffer.Configs[1].Config.Devices[1].deviceId:='device';
    Buffer.Configs[1].Config.Devices[1].PointStart:=1; Buffer.Configs[1].Config.Devices[1].PointCount:=1;
    Buffer.Configs[1].Config.Points[1].pointId:='point'; Buffer.Configs[1].Config.Points[1].reportMode:='cyclic';
    Buffer.Configs[1].Config.Points[1].reportIntervalMs:=5000; Buffer.Cursors[1].Enabled:=TRUE;
    Buffer.AuditEnabled:=TRUE; Buffer.LayoutBytes:=SIZEOF(Buffer); Buffer.RecordBytes:=SIZEOF(Buffer.Scratch);
    Diagnostics(BootId:='test-boot',GatewayId:='test-gw',NowMs:=ULINT#1000,Force:=TRUE,Buffer:=Buffer);
    Checks[1]:=Buffer.Diagnostics.RestartLossUnknown AND NOT Buffer.Diagnostics.AccountingComplete AND (Buffer.Diagnostics.Totals[16]=1) AND NOT Buffer.Diagnostics.LastGapCountKnown;
    Checks[2]:=NOT Buffer.Diagnostics.HasPendingAge AND (Buffer.Diagnostics.PendingEvents=0) AND (Buffer.Diagnostics.Revision MOD 2=0);
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#12.5,NowMs:=ULINT#10,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1000,Buffer:=Buffer);
    Checks[3]:=(Buffer.AuditWriteSeq=1) AND (Buffer.AuditEvents[1].Event.Value=LREAL#12.5) AND (Buffer.AuditEvents[1].Decision=0) AND (Buffer.Configs[1].References=2);
    Buffer.AuditAckBootId:='test-boot'; Buffer.AuditAckSeq:=1; Drain(BootId:='test-boot',Buffer:=Buffer);
    Checks[4]:=(Buffer.AuditReadSeq=0) AND (Buffer.Configs[1].References=2);
    Policy(Buffer:=Buffer);
    Checks[5]:=(Buffer.AuditEvents[1].Decision=2) AND (Buffer.OwnedCount=1) AND (Buffer.Configs[1].References=2);
    Buffer.AuditAckBootId:='old-boot'; Drain(BootId:='test-boot',Buffer:=Buffer);
    Checks[6]:=(Buffer.AuditReadSeq=0) AND (Buffer.Configs[1].References=2);
    Buffer.AuditAckBootId:='test-boot'; Drain(BootId:='test-boot',Buffer:=Buffer);
    Checks[7]:=(Buffer.AuditReadSeq=1) AND (Buffer.Configs[1].References=1) AND (Buffer.OwnedCount=1);
    Drain(BootId:='test-boot',Buffer:=Buffer);
    Checks[8]:=(Buffer.Configs[1].References=1);
    Buffer.BatchOwners[1].ConfigSlot:=1; Buffer.BatchOwners[1].Count:=1;
    Buffer.BatchOwners[1].Category:=2; Buffer.BatchOwners[1].Digest:='frozen-hash';
    Buffer.BatchRefs[1]:=1; Buffer.BatchGenerations[1]:=7;
    Associate(Slot:=UINT#1,MessageId:='frozen-message',Buffer:=Buffer);
    Checks[9]:=(Buffer.AssociationWriteSeq=1) AND (Buffer.Associations[1].SampleSeqs[1]=1) AND (Buffer.Associations[1].BatchGeneration=7) AND (Buffer.Configs[1].References=2);
    Buffer.BatchRefs[1]:=0; Buffer.BatchOwners[1].Digest:='changed';
    Checks[10]:=(Buffer.Associations[1].SampleSeqs[1]=1) AND (Buffer.Associations[1].Digest='frozen-hash');
    Buffer.AssociationAckBootId:='test-boot'; Buffer.AssociationAckSeq:=1; Drain(BootId:='test-boot',Buffer:=Buffer);
    Checks[11]:=(Buffer.AssociationReadSeq=1) AND (Buffer.Configs[1].References=1);
    Stage:=1;
1:
    (* Fill the evidence ring independently of business owners. The following
       cyclic events are filtered: only the audit ring remains pinned. *)
    FOR i:=1 TO 64 DO
        Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#12.5,NowMs:=ULINT#100,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1100,Buffer:=Buffer);
    END_FOR;
    Policy(Buffer:=Buffer);
    IF Buffer.AuditWriteSeq>=513 THEN Stage:=2; END_IF;
2:
    Capture(PointIndex:=UINT#1,Kind:=USINT#1,Quality:=USINT#2,Value:=LREAL#12.5,NowMs:=ULINT#100,NominalDueMs:=ULINT#0,SystemUtcMs:=ULINT#1100,Buffer:=Buffer);
    Policy(Buffer:=Buffer);
    Checks[12]:=(Buffer.AuditDropped=1) AND NOT Buffer.EvidenceComplete AND (Buffer.OwnedCount=1) AND (Buffer.KnownUnsentEventsTotal=0) AND (Buffer.UndecidedLostEventsTotal=0);
    Checks[13]:=(Buffer.AuditReadSeq=2) AND (Buffer.Configs[1].References=513) AND (Buffer.AuditEvents[2].Event.SampleSeq=514);
    Diagnostics(BootId:='test-boot',GatewayId:='test-gw',NowMs:=ULINT#2000,Force:=TRUE,Buffer:=Buffer);
    Checks[14]:=(Buffer.Diagnostics.Totals[1]=514) AND (Buffer.Diagnostics.Totals[2]=1) AND (Buffer.Diagnostics.Totals[3]=513) AND (Buffer.Diagnostics.AuditDropped=1) AND (Buffer.Diagnostics.PendingEvents=1);
    Buffer.IngressCount:=2; Buffer.DeadRetainedEvents:=1; Buffer.OwnedCount:=3; Buffer.UncertainRetainedEvents:=1;
    Diagnostics(BootId:='test-boot',GatewayId:='test-gw',NowMs:=ULINT#3000,Force:=TRUE,Buffer:=Buffer);
    Checks[15]:=(Buffer.Diagnostics.PendingEvents=3) AND (Buffer.Diagnostics.DeadEvents=1) AND (Buffer.Diagnostics.UncertainRetainedEvents=1);
    Checks[16]:=(Buffer.Diagnostics.Revision MOD 2=0) AND (Buffer.Diagnostics.AllocatedBytes=SIZEOF(Buffer)) AND (Buffer.Diagnostics.MaxBytes=4194304);
    FOR i:=1 TO 16 DO IF Checks[i] THEN Passed:=Passed+1; ELSE FailedChecks:=FailedChecks+1; END_IF; END_FOR;
    Done:=TRUE;
END_CASE;
END_PROGRAM
