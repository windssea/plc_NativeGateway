FUNCTION_BLOCK NG_BatchBuilder
VAR_INPUT
    GateOpen : BOOL;
    NowMs : ULINT;
    UnixMs : ULINT;
    GatewayId : NG_Id;
    BootId : NG_Id;
    BatchIntervalMs : UDINT;
END_VAR
VAR_IN_OUT
    Buffer : NG_Buffer;
    Packets : ARRAY[1..16] OF NG_Packet;
    Sequence : ULINT;
END_VAR
VAR_OUTPUT
    Busy : BOOL;
END_VAR
VAR
    Digest : NG_StringSHA256;
    Audit : NG_AuditAssociation;
    Stage : UINT;
    Slot : UINT;
    ConfigSlot : UINT;
    Category : UINT;
    q : UINT;
    r : UINT;
    j : UINT;
    offset : UINT;
    countHistory : UINT;
    countNew : UINT;
    n : INT;
    d : INT;
    deviceId : NG_Id;
    valueJson : STRING[80];
    item : STRING[1024];
    bytesNeeded : INT;
    duplicate : BOOL;
    finish : BOOL;
    lastStart : ULINT;
    first : BOOL := TRUE;
    MaterialClockRevision : ULINT;
    windowOpen : BOOL;
    generation : UDINT;
    seenEpoch : UDINT;
    seenPointEpoch : ARRAY[1..320] OF UDINT;
    pointIndex : UINT;
    HeaderUnixMs : ULINT;
    HeaderSequence : ULINT;
    DeviceQuoteSlot : UINT;
    DeviceQuoteGeneration : UDINT;
    DeviceQuoteEpoch : UDINT;
    DeviceQuoteSeen : ARRAY[1..50] OF UDINT;
    DeviceQuotes : ARRAY[1..50] OF STRING[132];
    QuotedDevice : STRING[132];
    ItemPhase : USINT;
    ItemRecord : UINT;
    ItemGeneration : UDINT;
    CachedUtc : ULINT;
    CachedUtcText : STRING[32];
    CachedQuality : USINT;
    CachedQualityText : STRING[40];
    HaveUtc : BOOL;
    HaveQuality : BOOL;
END_VAR
Busy:=Stage<>0;
IF Stage<>0 THEN
    IF (Buffer.BatchGenerations[Slot]<>generation) OR (Buffer.BatchOwners[Slot].State<>1) THEN Stage:=0; END_IF;
END_IF;
IF (Stage<>0) AND (NOT GateOpen OR (Buffer.PlatformTime AND (MaterialClockRevision<>Buffer.ClockRevision))) THEN
    Category:=TO_UINT(Buffer.BatchOwners[Slot].Category); offset:=(Slot-1)*64;
    FOR n:=TO_INT(Buffer.BatchOwners[Slot].Count) TO 1 BY -1 DO
        r:=Buffer.BatchRefs[offset+TO_UINT(n)];
        Buffer.RecordStates[r]:=1; Buffer.FreeSlots[r]:=Buffer.QueueHead[Category];
        Buffer.QueueHead[Category]:=r; IF Buffer.QueueTail[Category]=0 THEN Buffer.QueueTail[Category]:=r; END_IF;
        Buffer.BatchRefs[offset+TO_UINT(n)]:=0;
    END_FOR;
    Buffer.BatchOwners[Slot].State:=0; Buffer.BatchOwners[Slot].Count:=0;
    Packets[Slot].MessageId:=''; Packets[Slot].Payload:=''; Stage:=0;
END_IF;
IF Stage=0 THEN
    IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#180>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
    Digest(Execute:=FALSE,Length:=UDINT#0,Payload:=Packets[1].Payload);
    Busy:=FALSE;
    IF (Buffer.QueueHead[1]=0) AND (Buffer.QueueHead[2]=0) THEN windowOpen:=FALSE; END_IF;
    IF NOT GateOpen OR (UnixMs=0) OR (NOT windowOpen AND NOT first AND (NowMs<lastStart+TO_ULINT(BatchIntervalMs))) THEN RETURN; END_IF;
    countHistory:=0; countNew:=0; Slot:=0;
    FOR q:=1 TO 16 DO
        IF Buffer.BatchOwners[q].State=0 THEN IF Slot=0 THEN Slot:=q; END_IF;
        ELSIF Buffer.BatchOwners[q].State<>3 THEN
            IF Buffer.BatchOwners[q].Category=1 THEN countHistory:=countHistory+1; ELSE countNew:=countNew+1; END_IF;
        END_IF;
    END_FOR;
    IF Slot=0 THEN RETURN; END_IF;
    Category:=TO_UINT(Buffer.PreferMaterialize);
    IF ((Category=1) AND ((Buffer.QueueHead[1]=0) OR (countHistory>=7))) OR
       ((Category=2) AND ((Buffer.QueueHead[2]=0) OR (countNew>=7))) THEN Category:=UINT#3-Category; END_IF;
    IF ((Category=1) AND ((Buffer.QueueHead[1]=0) OR (countHistory>=7))) OR
       ((Category=2) AND ((Buffer.QueueHead[2]=0) OR (countNew>=7))) THEN RETURN; END_IF;
    r:=Buffer.QueueHead[Category]; ConfigSlot:=Buffer.Records[r].ConfigSlot;
    IF (Buffer.Configs[ConfigSlot].GatewayId<>GatewayId) OR (Buffer.Configs[ConfigSlot].CaptureBootId<>BootId) THEN RETURN; END_IF;
    (* Lazy bounded quote cache follows the pinned dictionary's slot AND generation.
       NG_Id has at most 64 characters; escaped JSON needs at most 130 characters. *)
    IF (DeviceQuoteSlot<>ConfigSlot) OR (DeviceQuoteGeneration<>Buffer.Configs[ConfigSlot].Generation) THEN
        IF DeviceQuoteEpoch=UDINT#4294967295 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
        DeviceQuoteEpoch:=DeviceQuoteEpoch+1;
        DeviceQuoteSlot:=ConfigSlot; DeviceQuoteGeneration:=Buffer.Configs[ConfigSlot].Generation;
    END_IF;
    IF (Sequence>=ULINT#9007199254740991) OR (Buffer.BatchGenerations[Slot]=UDINT#4294967295) THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
    IF seenEpoch=UDINT#4294967295 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
    seenEpoch:=seenEpoch+1;
    Sequence:=Sequence+1; Buffer.BatchGenerations[Slot]:=Buffer.BatchGenerations[Slot]+1; generation:=Buffer.BatchGenerations[Slot];
    Packets[Slot].MessageId:=CONCAT('d-',BootId,'-',TO_STRING(Sequence,'{0:d}'));
    IF LEN(Packets[Slot].MessageId)>64 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
    (* Freeze envelope values at reservation; quoting is split into bounded steps. *)
    HeaderUnixMs:=UnixMs; HeaderSequence:=Sequence; MaterialClockRevision:=Buffer.ClockRevision;
    Packets[Slot].Payload:='';
    Packets[Slot].WasSent:=FALSE; Packets[Slot].Attempts:=0; Packets[Slot].Dead:=FALSE;
    Packets[Slot].LastSentMs:=0; Packets[Slot].RetryAtMs:=0; Packets[Slot].LastError:='';
    Buffer.BatchOwners[Slot].State:=1; Buffer.BatchOwners[Slot].Count:=0;
    Buffer.BatchOwners[Slot].Category:=TO_USINT(Category); Buffer.BatchOwners[Slot].ConfigSlot:=ConfigSlot;
    Buffer.BatchOwners[Slot].OrderSeq:=Buffer.Records[r].SampleSeq;
    Buffer.BatchOwners[Slot].CreatedMs:=Buffer.Records[r].CompletedMonoMs;
    IF NOT windowOpen THEN lastStart:=NowMs; windowOpen:=TRUE; END_IF;
    first:=FALSE; Stage:=10; Busy:=TRUE; ItemPhase:=0;
END_IF;
(* Recheck the same absolute scan deadline before every envelope fragment.
   The dictionary stays pinned by queued records; identity is never read from
   a subsequently changed live configuration. No record is dequeued here. *)
IF Stage=10 THEN
    IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#240>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
    Packets[Slot].Payload:=CONCAT('{"schemaVersion":1,"gatewayId":',NG_Quote(Buffer.Configs[ConfigSlot].GatewayId),',"timestamp":',TO_STRING(HeaderUnixMs,'{0:d}'));
    Stage:=11;
END_IF;
IF Stage=11 THEN
    IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#240>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
    Packets[Slot].Payload:=CONCAT(Packets[Slot].Payload,',"messageId":',NG_Quote(Packets[Slot].MessageId),',"bootId":',NG_Quote(Buffer.Configs[ConfigSlot].CaptureBootId));
    Stage:=12;
END_IF;
IF Stage=12 THEN
    IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#180>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
    Packets[Slot].Payload:=CONCAT(Packets[Slot].Payload,',"sequence":',TO_STRING(HeaderSequence,'{0:d}'),',"configVersion":',TO_STRING(Buffer.Configs[ConfigSlot].Config.Version,'{0:d}'),',"values":[');
    Stage:=1;
END_IF;
IF Stage=1 THEN
    offset:=(Slot-1)*64; finish:=FALSE;
    FOR n:=1 TO 16 DO
        IF Buffer.WorkDeadlineUs=0 THEN IF n>4 THEN EXIT; END_IF;
        ELSIF GET_MICROSECONDS(TRUE)+ULINT#100>=Buffer.WorkDeadlineUs THEN EXIT; END_IF;
        r:=Buffer.QueueHead[Category];
        IF r=0 THEN finish:=TRUE; EXIT; END_IF;
        IF Buffer.Records[r].ConfigSlot<>ConfigSlot THEN finish:=TRUE; EXIT; END_IF;
        pointIndex:=Buffer.Records[r].PointIndex;
        IF (pointIndex<1) OR (pointIndex>320) THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
        (* Epochs replace the growing scan of batch references. This is still
           exact point-index deduplication within one frozen config/batch. *)
        duplicate:=seenPointEpoch[pointIndex]=seenEpoch;
        IF duplicate OR (Buffer.BatchOwners[Slot].Count>=64) OR
           (Buffer.BatchOwners[Slot].Count>=Buffer.Configs[ConfigSlot].Config.maxBatchPoints) THEN finish:=TRUE; EXIT; END_IF;
        (* Until append succeeds the source remains queued. Maintenance may
           expire/reuse its record between slices; never append a stale item. *)
        IF ItemPhase>0 THEN
            IF (ItemRecord<>r) OR (ItemGeneration<>Buffer.RecordGenerations[r]) THEN ItemPhase:=0; END_IF;
        END_IF;
        IF ItemPhase=0 THEN
        IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#180>=Buffer.WorkDeadlineUs THEN EXIT; END_IF; END_IF;
        d:=TO_INT(Buffer.Configs[ConfigSlot].PointDevices[Buffer.Records[r].PointIndex]);
        IF (d>0) AND (d<=Buffer.Configs[ConfigSlot].Config.DeviceCount) THEN
            deviceId:=Buffer.Configs[ConfigSlot].Config.Devices[d].deviceId;
        ELSE
        deviceId:='';
        FOR d:=1 TO Buffer.Configs[ConfigSlot].Config.DeviceCount DO
            IF (Buffer.Records[r].PointIndex>=TO_UINT(Buffer.Configs[ConfigSlot].Config.Devices[d].PointStart)) AND
               (Buffer.Records[r].PointIndex<TO_UINT(Buffer.Configs[ConfigSlot].Config.Devices[d].PointStart+Buffer.Configs[ConfigSlot].Config.Devices[d].PointCount)) THEN
                deviceId:=Buffer.Configs[ConfigSlot].Config.Devices[d].deviceId; EXIT;
            END_IF;
        END_FOR;
            IF deviceId<>'' THEN Buffer.Configs[ConfigSlot].PointDevices[Buffer.Records[r].PointIndex]:=TO_USINT(d); END_IF;
        END_IF;
        valueJson:='null';
        IF Buffer.Records[r].Quality=2 THEN
            IF Buffer.Configs[ConfigSlot].Config.Points[Buffer.Records[r].PointIndex].dataType='bool' THEN
                IF Buffer.Records[r].Value=LREAL#0.0 THEN valueJson:='false'; ELSE valueJson:='true'; END_IF;
            ELSE valueJson:=TO_STRING(Buffer.Records[r].Value,'{0:E16}'); END_IF;
        END_IF;
        IF (d>0) AND (d<=50) THEN
            IF DeviceQuoteSeen[d]<>DeviceQuoteEpoch THEN
                DeviceQuotes[d]:=NG_Quote(deviceId); DeviceQuoteSeen[d]:=DeviceQuoteEpoch;
            END_IF;
            QuotedDevice:=DeviceQuotes[d];
        ELSE QuotedDevice:=NG_Quote(deviceId); END_IF;
        (* Only numeric UTC and quality code determine these text fragments.
           Keys are the original frozen record values, never live time/state. *)
        IF NOT HaveUtc OR (CachedUtc<>Buffer.Records[r].CapturedUtcMs) THEN
            CachedUtc:=Buffer.Records[r].CapturedUtcMs;
            CachedUtcText:=TO_STRING(CachedUtc,'{0:d}'); HaveUtc:=TRUE;
        END_IF;
        IF NOT HaveQuality OR (CachedQuality<>Buffer.Records[r].Quality) THEN
            CachedQuality:=Buffer.Records[r].Quality;
            CachedQualityText:=NG_Quote(NG_QualityName(CachedQuality)); HaveQuality:=TRUE;
        END_IF;
        ItemRecord:=r; ItemGeneration:=Buffer.RecordGenerations[r]; ItemPhase:=1;
        END_IF;
        IF ItemPhase=1 THEN
        IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#180>=Buffer.WorkDeadlineUs THEN EXIT; END_IF; END_IF;
        item:=CONCAT('{"deviceId":',QuotedDevice,',"pointId":',NG_Quote(Buffer.Configs[ConfigSlot].Config.Points[pointIndex].pointId),',"value":',valueJson,',"quality":',CachedQualityText,',"timestamp":',CachedUtcText,'}');
        bytesNeeded:=LEN(Packets[Slot].Payload)+LEN(item)+2;
        IF Buffer.BatchOwners[Slot].Count>0 THEN bytesNeeded:=bytesNeeded+1; END_IF;
        IF bytesNeeded>16380 THEN finish:=TRUE; EXIT; END_IF;
        (* Prefix the small item so the growing full payload is copied once per value. *)
        IF Buffer.BatchOwners[Slot].Count>0 THEN item:=CONCAT(',',item); END_IF;
        ItemPhase:=2;
        END_IF;
        IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#100>=Buffer.WorkDeadlineUs THEN EXIT; END_IF; END_IF;
        Packets[Slot].Payload:=CONCAT(Packets[Slot].Payload,item);
        Buffer.BatchOwners[Slot].Count:=Buffer.BatchOwners[Slot].Count+1; j:=Buffer.BatchOwners[Slot].Count;
        seenPointEpoch[pointIndex]:=seenEpoch;
        Buffer.BatchRefs[offset+j]:=r; Buffer.BatchRefGenerations[offset+j]:=Buffer.RecordGenerations[r];
        Buffer.RecordStates[r]:=2;
        Buffer.QueueHead[Category]:=Buffer.FreeSlots[r]; IF Buffer.QueueHead[Category]=0 THEN Buffer.QueueTail[Category]:=0; END_IF;
        Buffer.FreeSlots[r]:=0;
        ItemPhase:=0;
    END_FOR;
    IF finish THEN
        IF Buffer.BatchOwners[Slot].Count=0 THEN Buffer.CaptureStopped:=TRUE; RETURN; END_IF;
        Packets[Slot].Payload:=CONCAT(Packets[Slot].Payload,']}'); Packets[Slot].Length:=TO_UDINT(LEN(Packets[Slot].Payload)); Stage:=2;
    END_IF;
END_IF;
IF Stage=2 THEN
    Digest(Execute:=TRUE,Length:=Packets[Slot].Length,DeadlineUs:=Buffer.WorkDeadlineUs,Payload:=Packets[Slot].Payload);
    IF Digest.Error THEN Buffer.CaptureStopped:=TRUE; Buffer.AccountingComplete:=FALSE; RETURN; END_IF;
    IF Digest.Done THEN
        IF Buffer.WorkDeadlineUs>0 THEN IF GET_MICROSECONDS(TRUE)+ULINT#100>=Buffer.WorkDeadlineUs THEN RETURN; END_IF; END_IF;
        Buffer.BatchOwners[Slot].Digest:=Digest.Digest; Buffer.BatchOwners[Slot].State:=2;
        Audit(Slot:=Slot,MessageId:=Packets[Slot].MessageId,Buffer:=Buffer);
        Buffer.PreferMaterialize:=TO_USINT(UINT#3-Category); Stage:=0;
    END_IF;
END_IF;
Busy:=Stage<>0;
END_FUNCTION_BLOCK
