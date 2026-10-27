PROGRAM Main
VAR_EXTERNAL
    RTC : RTC_TYPE;
    HMI : NG_Hmi;
    GW_Load : BOOL;
    GW_LoadPoint : BOOL;
    GW_SaveDevice : BOOL;
    GW_SavePoint : BOOL;
    GW_RemoveDevice : BOOL;
    GW_RemovePoint : BOOL;
    GW_Apply : BOOL;
    GW_SaveBroker : BOOL;
    GW_Nav : INT;

END_VAR
VAR
    Store : NG_Store;
    CaptureBuffer : NG_Buffer;
    ReportPolicy : NG_ReportPolicy;
    BufferMaintenance : NG_BufferMaintenance;
    BatchBuilder : NG_BatchBuilder;
    Delivery : NG_DeliveryParallel;
    AuditDrain : NG_AuditDrain;
    Diagnostics : NG_Diagnostics;
    CheckCounters : NG_CheckCounters;
    DataGate : BOOL;
    PipelinePhase : USINT;
    SubmitDataAck : BOOL;
    DataAckId : NG_Id;
    DataAckStored : BOOL;
    DataAckRetryable : BOOL;
    DataAckCodes : NG_Text;
    TxBatchGeneration : UDINT;
    CaptureCompare : NG_SameConfig;
    CaptureConfigSelector : NG_ConfigSlot;
    CaptureSlot : UINT;
    ReservedCaptureSlot : UINT;
    CaptureConfigChanged : BOOL;
    CaptureReady : BOOL;
    CaptureExtraBytes : UDINT;
    CaptureState : NG_SourceState;
    CaptureActivation : NG_SourceStateCore;
    CaptureSourceEnabled : BOOL;
    CaptureLivenessStart : ULINT;
    CaptureIgnored : BOOL;
    Pending : NG_Durable;
    Durable : NG_Durable;
    Active : NG_Config;
    Bootstrap : NG_Bootstrap;
    Initialized : BOOL;
    StartupReady : BOOL;
    StartupStage : INT;
    BootHash : NG_SHA256;
    BootNamespace : STRING[24];
    IdentityChanged : BOOL;
    ProtocolConfig : NG_Config;
    HubActiveVersion : ULINT;
    HubActiveMessageId : NG_Id;
    TelemetryAllowed : BOOL;
    AckMessage : STRING[160];
    BlankConfig : NG_Config;
    EmptyPacket : NG_Packet;
    AckReader : NG_ReadAck;
    WireError : NG_Text;
    DeviceEventPending : BOOL;
    DeviceEventIndex : INT;
    DeviceEventSignature : NG_Text;
    DeviceSignatures : ARRAY[1..50] OF NG_Text;
    HeartbeatSignatures : ARRAY[1..50] OF NG_Text;
    EnabledPoints : INT;
    DeadCount : INT;
    InFlightCount : INT;
    AckWaitMs : ULINT;
    EventTxIndex : INT;
    EventTxSignature : NG_Text;
    GetSequence : ULINT;
    Save : BOOL;
    SaveReason : INT;
    Mqtt : NG_Mqtt;
    NativeClock : NG_PlatformTime;
    TimeChecks : NG_PlatformTimeChecks;
    TimeReader : NG_TimeResponse;
    TimeMode : BOOL; (* Explicit candidate profile; legacy default is SYSTEM_RTC. *)
    TimeBasis : NG_Id := 'site-hub-1';
    TimeDriftPpm : LREAL := 1000;
    TimeDriftEvidence : NG_Text;
    TimeBootSeen : NG_Id;
    TimeReset : BOOL;
    SystemUnixMs : ULINT;
    SnapshotMonoMs : ULINT;
    TimeResponsePending : BOOL;
    TimeResponseT2 : ULINT;
    TimeResponseT3 : ULINT;
    TimeResponseM1 : ULINT;
    TimeResponseM4 : ULINT;
    RxReceivedMonoMs : ULINT;
    EnqueueGate : BOOL;
    SdkSendGate : BOOL;
    TxClockRevision : ULINT;
    TxTokenMonoMs : ULINT;
    TxBootId : NG_Id;
    TxConnectionRevision : ULINT;
    AckActiveVersion : ULINT;
    AckActiveMessageId : NG_Id;
    Resources : NG_Resources;
    ResourcesPending : BOOL;
    ResourcesPayload : STRING[2048];
    QueueBytes : UDINT;
    Meters : ARRAY[1..50] OF NG_MeterState;
    Samples : ARRAY[1..320] OF NG_Sample;

    Meter1 : NG_Modbus;
    Meter2 : NG_Modbus;
    Meter3 : NG_Modbus;
    Meter4 : NG_Modbus;
    Meter5 : NG_Modbus;
    Meter6 : NG_Modbus;
    Meter7 : NG_Modbus;
    Meter8 : NG_Modbus;
    Meter9 : NG_Modbus;
    Meter10 : NG_Modbus;
    Meter11 : NG_Modbus;
    Meter12 : NG_Modbus;
    Meter13 : NG_Modbus;
    Meter14 : NG_Modbus;
    Meter15 : NG_Modbus;
    Meter16 : NG_Modbus;
    Meter17 : NG_Modbus;
    Meter18 : NG_Modbus;
    Meter19 : NG_Modbus;
    Meter20 : NG_Modbus;
    Meter21 : NG_Modbus;
    Meter22 : NG_Modbus;
    Meter23 : NG_Modbus;
    Meter24 : NG_Modbus;
    Meter25 : NG_Modbus;
    Meter26 : NG_Modbus;
    Meter27 : NG_Modbus;
    Meter28 : NG_Modbus;
    Meter29 : NG_Modbus;
    Meter30 : NG_Modbus;
    Meter31 : NG_Modbus;
    Meter32 : NG_Modbus;
    Meter33 : NG_Modbus;
    Meter34 : NG_Modbus;
    Meter35 : NG_Modbus;
    Meter36 : NG_Modbus;
    Meter37 : NG_Modbus;
    Meter38 : NG_Modbus;
    Meter39 : NG_Modbus;
    Meter40 : NG_Modbus;
    Meter41 : NG_Modbus;
    Meter42 : NG_Modbus;
    Meter43 : NG_Modbus;
    Meter44 : NG_Modbus;
    Meter45 : NG_Modbus;
    Meter46 : NG_Modbus;
    Meter47 : NG_Modbus;
    Meter48 : NG_Modbus;
    Meter49 : NG_Modbus;
    Meter50 : NG_Modbus;

    Editor : NG_HmiEdit;
    Parser : NG_JsonParse;
    Hash : NG_SHA256;
    Command : NG_Command;
    Doc : NG_Document;
    Rx : NG_Bytes;
    Tx : NG_Bytes;
    RxAccept : BOOL;
    RxStage : INT;
    IsPatch : BOOL;
    RxLength : UDINT;
    RxRetain : BOOL;
    RxTopic : STRING[500];
    RequestId : NG_Id;
    RequestVersion : ULINT;
    Result : STRING[16];
    ErrorCode : NG_Text;
    Replay : BOOL;
    AckPending : BOOL;
    AckPayload : NG_Json;
    AckTopic : STRING[200];
    Reconnect : BOOL;
    ResetMeters : BOOL;
    TxRequest : BOOL;
    TxActive : BOOL;
    TxKind : INT;
    TxBatchId : NG_Id;
    TxTopic : STRING[200];
    TxPayload : NG_Json;
    TxLength : UDINT;
    TxRetain : BOOL;
    CopyString : STRING_TO_BUF;
    Prefix : STRING[150];
    Header : STRING[512];
    SessionId : NG_Id;
    BootId : NG_Id;
    SessionSeen : UDINT;
    Sequence : ULINT;
    Clock : TON;
    Epoch : ULINT;
    NowMs : ULINT;
    UnixMs : ULINT;
    LastGet : ULINT;
    LastHeartbeat : ULINT;
    LastBatch : ULINT;
    GetPending : BOOL;
    StatusPending : BOOL;
    HeartbeatPending : BOOL;
    Outbox : ARRAY[1..16] OF NG_Packet;
    Head : INT := 1;
    Tail : INT := 1;
    QueueCount : INT;
    Dropped : UDINT;
    Values : NG_Json;
    Item : STRING[1024];
    DevicesJson : NG_Json;
    JsonValue : STRING[80];
    Quality : STRING[24];
    Status : STRING[16];
    StateName : STRING[24];
    LastErrorJson : STRING[300];
    LastGoodJson : STRING[24];
    EmptySample : NG_Sample;
    d : INT;
    p : INT;
    i : INT;
    t : INT;
    q : INT;
    Total : INT;
    GoodCount : INT;
    BatchCount : INT;
    Due : BOOL;
    Changed : BOOL;
    BatchSweep : BOOL;
    BatchFull : BOOL;
    SweepDevice : INT;
    SweepPoint : INT;
    FirstPoint : INT;
    point : NG_Point;
    sample : NG_Sample;
END_VAR
Clock(IN := NOT Clock.Q, PT := T#20d);
NowMs := Epoch + TO_ULINT(TO_DINT(Clock.ET));
IF Clock.Q THEN Epoch := Epoch + ULINT#1728000000; END_IF;
SystemUnixMs := NG_Unix(RTC,Bootstrap.UtcOffsetMinutes); UnixMs:=SystemUnixMs;
Reconnect := FALSE; ResetMeters := FALSE; TxRequest := FALSE; RxAccept := FALSE; SubmitDataAck:=FALSE;
Store(Save := Save, Candidate := Pending);
Save := FALSE;
(* Pure startup assertions reuse the existing parser document/byte buffer.
   They finish before identity persistence, acquisition or MQTT is enabled. *)
TimeChecks(Doc:=Doc,Bytes:=Rx);
IF NOT TimeChecks.Done THEN RETURN; END_IF;
IF (TimeChecks.FailedChecks<>0) OR (TimeChecks.WireFailed<>0) THEN
    HMI.Status:='TIME ASSERTIONS FAILED: no gateway traffic started.'; RETURN;
END_IF;
IF Store.Ready AND NOT Initialized THEN
    Durable:=Store.Active; Active:=Durable.Config; Bootstrap:=Durable.Bootstrap;
    IF Bootstrap.GatewayId='' THEN
        Bootstrap.GatewayId:='NG-HUB-2152-01'; Bootstrap.ClientId:='NG-HUB-2152-01-native';
        Bootstrap.BrokerUri:='tcp://192.168.0.5:1883'; Bootstrap.UtcOffsetMinutes:=0;
        Active.batchIntervalMs:=1000; Active.maxBatchPoints:=32; Durable.Managed:=TRUE;
    END_IF;
    Prefix:=CONCAT('iot/v1/gateway/',Bootstrap.GatewayId,'/');
    HMI.GatewayId:=Bootstrap.GatewayId; HMI.BrokerGatewayId:=Bootstrap.GatewayId;
    HMI.BrokerUri:=Bootstrap.BrokerUri; HMI.ClientId:=Bootstrap.ClientId; HMI.UserName:=Bootstrap.UserName;
    HMI.UtcOffsetMinutes:=TO_STRING(Bootstrap.UtcOffsetMinutes,'{0:d}');
    IF Durable.Managed THEN HMI.ManagementMode:='HUB_MANAGED'; ELSE HMI.ManagementMode:='STANDALONE'; END_IF;
    HMI.Status:='Persisting unique startup identity before MQTT...'; Initialized:=TRUE; StartupStage:=1;
END_IF;
IF NOT Initialized THEN RETURN; END_IF;
// Resources are sampled by the independent IDeviceStatusService test recorder.
IF Resources.Changed THEN ResourcesPending := TRUE; END_IF;
IF Store.Busy THEN HMI.Persistence := 'Saving / validating durable file...';
ELSIF Store.Error THEN HMI.Persistence := 'STORAGE ERROR: configuration not committed.';
ELSIF Store.NeedsMigration THEN HMI.Persistence := 'Migrating v1 configuration...';
ELSE HMI.Persistence := CONCAT('Persisted generation ',TO_STRING(Durable.Generation,'{0:d}'),' - auto-restore enabled'); END_IF;
HMI.ResourceStatus := 'CPU/RAM recorded externally; offline detected by Hub heartbeat timeout.';
IF Store.Done THEN
    CaptureCompare(A:=Active,B:=Store.Active.Config);
    CaptureConfigChanged:=NOT CaptureCompare.Equal OR (Bootstrap.GatewayId<>Store.Active.Bootstrap.GatewayId);
    Durable := Store.Active; Active := Durable.Config; Bootstrap := Durable.Bootstrap;
    IF ReservedCaptureSlot>0 THEN
        IF ReservedCaptureSlot<>CaptureBuffer.ActiveSlot THEN
            CaptureBuffer.ActiveSlot:=ReservedCaptureSlot;
            IF CaptureBuffer.SamplingGeneration>=ULINT#9007199254740991 THEN CaptureBuffer.CaptureStopped:=TRUE;
            ELSE CaptureBuffer.SamplingGeneration:=CaptureBuffer.SamplingGeneration+1; END_IF;
        END_IF;
        CaptureBuffer.Configs[ReservedCaptureSlot].Reserved:=FALSE; ReservedCaptureSlot:=0;
    END_IF;
    IF Durable.Managed THEN HMI.ManagementMode:='HUB_MANAGED'; ELSE HMI.ManagementMode:='STANDALONE'; END_IF;
    IF (SaveReason = 1) OR (SaveReason = 2) THEN
        ResetMeters := CaptureConfigChanged;
        BatchSweep := FALSE;
        IF CaptureConfigChanged THEN FOR p := 1 TO 320 DO Samples[p] := EmptySample; END_FOR; END_IF;
        HMI.Status := 'APPLIED: configuration saved and activated.'; HMI.ConfigResult := HMI.Status;
        HeartbeatPending:=TRUE;
        IF SaveReason = 1 THEN Result := 'APPLIED'; ErrorCode := ''; RxStage := 90; END_IF;
        GetPending := TRUE;
    ELSIF SaveReason = 3 THEN
        IF IdentityChanged THEN
            Initialized:=FALSE; StartupReady:=FALSE; StartupStage:=0; ResetMeters:=TRUE;
            RxStage:=0; AckPending:=FALSE; TxActive:=FALSE; GetPending:=TRUE; HeartbeatPending:=FALSE;
            LastGet:=0; LastHeartbeat:=0; LastBatch:=0;
            QueueCount:=0; Head:=1; Tail:=1; Sequence:=0; SessionSeen:=0; BatchSweep:=FALSE;
            FOR q:=1 TO 16 DO Outbox[q]:=EmptyPacket; END_FOR;
            FOR p:=1 TO 320 DO Samples[p]:=EmptySample; END_FOR;
            IdentityChanged:=FALSE;
        END_IF;
        Reconnect:=TRUE; HMI.Status:='Broker settings saved; configuration ownership is unchanged.';
    ELSIF SaveReason = 6 THEN
        ResetMeters := CaptureConfigChanged; BatchSweep := FALSE;
        IF CaptureConfigChanged THEN FOR p := 1 TO 320 DO Samples[p] := EmptySample; END_FOR; END_IF;
        HeartbeatPending := TRUE; GetPending := TRUE;
        HMI.Status := 'Management mode saved. Check the ownership guidance above.';
    ELSIF SaveReason = 5 THEN
        BootId:=CONCAT('ng-',BootNamespace,'-',TO_STRING(Durable.BootCounter,'{0:d}'));
        SessionId:=BootId; StartupReady:=TRUE; StartupStage:=4; HMI.Status:='Startup identity persisted; MQTT starting.';
    END_IF;
    SaveReason := 0;
ELSIF Store.Error AND (SaveReason <> 0) THEN
    IF ReservedCaptureSlot>0 THEN CaptureBuffer.Configs[ReservedCaptureSlot].Reserved:=FALSE; ReservedCaptureSlot:=0; END_IF;
    HMI.Status := 'STORAGE_ERROR: active configuration unchanged.';
    IF SaveReason = 1 THEN Result := 'FAILED'; ErrorCode := 'STORAGE_ERROR'; RxStage := 90; END_IF;
    SaveReason := 0;
END_IF;
BootHash(Execute:=StartupStage=2,Length:=TO_UDINT(LEN(Bootstrap.GatewayId)),Buffer:=Tx);
IF NOT StartupReady THEN
    IF StartupStage=1 THEN
        CopyString(REQ:=FALSE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(Bootstrap.GatewayId),SRC:=Bootstrap.GatewayId,BUFFER:=Tx);
        CopyString(REQ:=TRUE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(Bootstrap.GatewayId),SRC:=Bootstrap.GatewayId,BUFFER:=Tx);
        IF CopyString.DONE THEN StartupStage:=2; END_IF;
    ELSIF (StartupStage=2) AND BootHash.Done THEN
        IF Durable.BootCounter>=ULINT#9007199254740990 THEN HMI.Status:='BOOT COUNTER EXHAUSTED: maintenance required.';
        ELSE
            BootNamespace:=LEFT(BootHash.Digest,24); Pending:=Durable;
            Pending.Config:=Active; Pending.Bootstrap:=Bootstrap; Pending.BootCounter:=Durable.BootCounter+1;
            Save:=TRUE; SaveReason:=5; StartupStage:=3;
        END_IF;
    END_IF;
    Mqtt(Enable:=FALSE,Reconnect:=TRUE,NowMs:=NowMs,Bootstrap:=Bootstrap,BootId:=BootId,TxRequest:=FALSE,TxTopic:='',TxLength:=0,TxRetain:=FALSE,RxAccept:=FALSE,TxBuffer:=Tx,RxBuffer:=Rx);
    RETURN;
END_IF;
TelemetryAllowed := NOT Durable.LocalChanges OR NOT Durable.HasHubBaseline;
HubActiveVersion := Active.Version; HubActiveMessageId := Active.MessageId;
IF Durable.LocalChanges AND Durable.HasHubBaseline THEN HubActiveVersion := 0; HubActiveMessageId := ''; END_IF;
IF Durable.Managed AND NOT Durable.HasHubBaseline AND Durable.LocalChanges THEN HubActiveVersion := 0; HubActiveMessageId := ''; TelemetryAllowed := FALSE; END_IF;
IF RxStage=30 THEN
    ProtocolConfig := Active;
    IF Durable.Managed AND NOT Durable.HasHubBaseline AND Durable.LocalChanges THEN ProtocolConfig := BlankConfig; END_IF;
END_IF;
IF Mqtt.SessionCount <> SessionSeen THEN
    SessionSeen := Mqtt.SessionCount; SessionId := CONCAT(BootId,'-',TO_STRING(SessionSeen, '{0:d}')); StatusPending := TRUE; GetPending := TRUE; LastHeartbeat := 0; HeartbeatPending:=TRUE;
    (* Retry deadlines and attempts survive reconnect; no burst/reset. *)
END_IF;
TimeReset:=TimeBootSeen<>BootId; TimeBootSeen:=BootId; SnapshotMonoMs:=NowMs;
NativeClock(Reset:=TimeReset,PlatformMode:=TimeMode,Connected:=Mqtt.Connected,SessionId:=SessionId,NowMs:=NowMs,SystemUtcMs:=SystemUnixMs,
    TimeBasisRef:=TimeBasis,DriftBoundPpm:=TimeDriftPpm,DriftEvidence:=TimeDriftEvidence,HistoryBasisRef:='',HistoryUtcLowerMs:=0,
    RequestSubmitted:=Mqtt.TxSubmitted AND (Mqtt.SubmittedKind=8),RequestSubmittedMonoMs:=Mqtt.TxSubmitMonoMs,
    ResponseReady:=TimeResponsePending,ResponseClientMonoMs:=TimeResponseM1,ResponseReceivedMonoMs:=TimeResponseM4,
    ServerReceivedMs:=TimeResponseT2,ServerSentMs:=TimeResponseT3,
    HeartbeatSubmitted:=Mqtt.TxSubmitted AND (Mqtt.SubmittedKind=4),ConfigGetSubmitted:=Mqtt.TxSubmitted AND (Mqtt.SubmittedKind=2));
TimeResponsePending:=FALSE;
IF TimeMode THEN UnixMs:=NativeClock.UtcMs; END_IF;
CaptureBuffer.PlatformTime:=TimeMode; CaptureBuffer.TimeValid:=NativeClock.TimeValid; CaptureBuffer.ClockRevision:=NativeClock.ClockRevision;
CaptureBuffer.DecisionSnapshotMonoMs:=NowMs;
(* Charge an attempt at actual library invocation, including uncertain SDK
   outcomes. A proven Busy/Done submission separately opens control gates. *)
IF Mqtt.TxInvoked AND (Mqtt.SubmittedKind=5) AND (Head>=1) AND (Head<=16) THEN
    IF (CaptureBuffer.BatchGenerations[Head]=TxBatchGeneration) AND (Outbox[Head].MessageId=TxBatchId) THEN
        Outbox[Head].WasSent:=TRUE;
        IF Outbox[Head].Attempts<UDINT#4294967295 THEN Outbox[Head].Attempts:=Outbox[Head].Attempts+1; END_IF;
        AckWaitMs:=60000; IF Outbox[Head].Attempts=1 THEN AckWaitMs:=30000; END_IF;
        Outbox[Head].LastSentMs:=Mqtt.TxSubmitMonoMs; Outbox[Head].RetryAtMs:=Mqtt.TxSubmitMonoMs+AckWaitMs+TO_ULINT(Head)*17;
        CaptureBuffer.NextSendAt:=Mqtt.TxSubmitMonoMs+334;
        CaptureBuffer.PreferSend:=USINT#3-CaptureBuffer.BatchOwners[Head].Category;
    END_IF;
END_IF;
Header := CONCAT('{"schemaVersion":1,"gatewayId":',NG_Quote(Bootstrap.GatewayId),',"timestamp":',TO_STRING(UnixMs, '{0:d}'));
IF (RxStage = 0) AND Mqtt.RxReady AND NOT Store.Busy AND (SaveReason = 0) THEN
    RxTopic := Mqtt.RxTopic; RxLength := Mqtt.RxLength; RxRetain := Mqtt.RxRetained;
    RxReceivedMonoMs:=Mqtt.RxReceivedMonoMs;
    IF AckPending AND (RxTopic<>CONCAT(Prefix,'data/ack')) AND (RxTopic<>CONCAT(Prefix,'time/response')) THEN
        (* One bounded pending config ACK. Never block TIME/ACK behind another
           command while unsynced; Hub retry/config-get will reconcile it. *)
        RxAccept:=TRUE; GetPending:=TRUE;
    ELSIF (RxTopic=CONCAT(Prefix,'time/response')) AND ((NOT TimeMode) OR (RxLength>2048)) THEN RxAccept:=TRUE;
    ELSIF (RxLength = 0) OR (RxLength > 131071) THEN RxAccept := TRUE; HMI.ConfigResult := 'PAYLOAD_TOO_LARGE';
    ELSE IsPatch := RxTopic = CONCAT(Prefix,'config/patch'); RxStage := 10;
    END_IF;
END_IF;
Parser(Execute := RxStage = 10, Length := RxLength, Buffer := Rx, Doc := Doc);
Hash(Execute := RxStage = 20, Length := RxLength, Buffer := Rx);
Command(Execute := RxStage = 30, IsPatch := IsPatch, Retained := RxRetain, GatewayId := Bootstrap.GatewayId, Doc := Doc, Active := ProtocolConfig);
CASE RxStage OF
10:
    IF Parser.Error THEN HMI.ConfigResult := Parser.ErrorText; RxAccept := TRUE; RxStage := 0;
    ELSIF Parser.Done THEN
        IF RxTopic=CONCAT(Prefix,'time/response') THEN
            TimeReader(Length:=RxLength,Retained:=RxRetain,GatewayId:=Bootstrap.GatewayId,BootId:=BootId,SessionId:=SessionId,
                RequestId:=NativeClock.RequestId,ClientMonoMs:=NativeClock.RequestClientMonoMs,Doc:=Doc,Bytes:=Rx);
            IF TimeMode AND TimeReader.Valid AND NativeClock.PendingRequest THEN
                TimeResponseT2:=TimeReader.ServerReceivedMs; TimeResponseT3:=TimeReader.ServerSentMs;
                TimeResponseM1:=NativeClock.RequestClientMonoMs; TimeResponseM4:=RxReceivedMonoMs; TimeResponsePending:=TRUE;
            END_IF;
            RxAccept:=TRUE; RxStage:=0;
        ELSIF RxTopic = CONCAT(Prefix,'data/ack') THEN
            AckReader(GatewayId:=Bootstrap.GatewayId,Doc:=Doc);
            IF AckReader.Valid AND NOT RxRetain THEN
                IF NOT Delivery.AckBusy THEN
                    SubmitDataAck:=TRUE; DataAckId:=AckReader.MessageId;
                    DataAckStored:=AckReader.Stored; DataAckRetryable:=AckReader.Retryable; DataAckCodes:=AckReader.Codes;
                    RxAccept:=TRUE; RxStage:=0;
                END_IF;
            ELSE HMI.InvalidAcks:=HMI.InvalidAcks+1; HMI.ConfigResult:='Invalid data/ack ignored.';
                RxAccept:=TRUE; RxStage:=0;
            END_IF;
        ELSE RxStage := 20; END_IF;
    END_IF;
20: IF Hash.Done THEN RxStage := 30; END_IF;
30:
    IF Command.Done THEN
        RequestId := Command.RequestId; RequestVersion := Command.RequestVersion; ErrorCode := Command.ErrorCode;
        Result := 'REJECTED'; Replay := FALSE; AckMessage := 'Configuration rejected; inspect HMI diagnostics.'; HMI.ReceivedConfigs := HMI.ReceivedConfigs+1;
        IF NOT Durable.Managed THEN
            ErrorCode := 'VERSION_CONFLICT'; AckMessage := 'Local maintenance is active. Configuration was not applied. Return ownership to Hub, then retry this release.';
        ELSE
        FOR i := 1 TO 32 DO
            IF (RequestId <> '') AND (Durable.Requests[i].MessageId = RequestId) THEN
                IF (Durable.Requests[i].Digest = Hash.Digest) AND (Durable.Requests[i].IsPatch = IsPatch) AND (Durable.Requests[i].Version = RequestVersion) THEN
                    IF IsPatch OR (Active.Version = RequestVersion) THEN Replay := TRUE; Result := 'APPLIED'; ErrorCode := '';
                    ELSE ErrorCode := 'STALE_VERSION'; END_IF;
                ELSE ErrorCode := 'VERSION_CONFLICT'; END_IF;
                EXIT;
            END_IF;
        END_FOR;
        IF NOT Replay AND (ErrorCode = '') THEN
            IF RequestVersion < ProtocolConfig.Version THEN ErrorCode := 'STALE_VERSION';
            ELSIF RequestVersion = ProtocolConfig.Version THEN ErrorCode := 'VERSION_CONFLICT'; END_IF;
        END_IF;
        END_IF;
        IF (ErrorCode = '') AND NOT Replay THEN
            Pending := Durable; Pending.Config := Command.Candidate;
            Pending.HubConfig := Pending.Config; Pending.HasHubBaseline := TRUE; Pending.LocalChanges := FALSE;
            Pending.ReplayIndex := Pending.ReplayIndex+1; IF Pending.ReplayIndex > 32 THEN Pending.ReplayIndex := 1; END_IF;
            i := Pending.ReplayIndex; Pending.Requests[i].MessageId := RequestId; Pending.Requests[i].Version := RequestVersion; Pending.Requests[i].Digest := Hash.Digest; Pending.Requests[i].IsPatch := IsPatch;
            Save := TRUE; SaveReason := 1; RxStage := 40;
        ELSE RxStage := 90; END_IF;
    END_IF;
40: (* Wait for the durable commit. *)
90:
    IF (RequestId <> '') AND (RequestVersion > 0) THEN
        AckPayload := CONCAT(',"messageId":',NG_Quote(RequestId),',"configVersion":',TO_STRING(RequestVersion, '{0:d}'),',"activeConfigVersion":',TO_STRING(HubActiveVersion, '{0:d}'),',"status":',NG_Quote(Result),',"errors":[');
        IF ErrorCode <> '' THEN WireError:=NG_WireCode(ErrorCode,IsPatch); AckPayload := CONCAT(AckPayload,'{"code":',NG_Quote(WireError),',"path":"/","message":',NG_Quote(AckMessage),'}'); END_IF;
        AckPayload := CONCAT(AckPayload,']');
        IF IsPatch THEN
            AckTopic := CONCAT(Prefix,'config/patch/ack');
            IF Result = 'APPLIED' THEN AckPayload := CONCAT(AckPayload,',"appliedConfigVersion":',TO_STRING(RequestVersion, '{0:d}')); ELSE AckPayload := CONCAT(AckPayload,',"appliedConfigVersion":null'); END_IF;
            AckPayload := CONCAT(AckPayload,',"activeMessageId":');
            IF HubActiveVersion > 0 THEN AckPayload := CONCAT(AckPayload,NG_Quote(HubActiveMessageId)); ELSE AckPayload := CONCAT(AckPayload,'null'); END_IF;
        ELSE AckTopic := CONCAT(Prefix,'config/ack'); END_IF;
        AckPayload := CONCAT(AckPayload,'}'); AckPending := TRUE;
        AckActiveVersion:=HubActiveVersion; AckActiveMessageId:=HubActiveMessageId;
    END_IF;
    HMI.ConfigResult := CONCAT(Result,': ',ErrorCode); RxAccept := TRUE; RxStage := 0;
END_CASE;
HMI.Load := HMI.Load OR GW_Load; GW_Load := FALSE;
CASE GW_Nav OF
1: HMI.Navigation := 'LIST';
2: HMI.Navigation := 'MQTT';
3: HMI.Navigation := 'DEDIT';
4: HMI.Navigation := 'PEDIT';
5: HMI.Navigation := 'DPREV';
6: HMI.Navigation := 'DNEXT';
7: HMI.Navigation := 'PPREV';
8: HMI.Navigation := 'PNEXT';
9: HMI.Navigation := 'DDEL';
10: HMI.Navigation := 'PDEL';
11: HMI.Navigation := 'CANCEL';
12: HMI.Navigation := 'DNEW';
13: HMI.Navigation := 'PNEW';
14: HMI.Navigation := 'PERIOD';
15: HMI.Navigation := 'D1';
16: HMI.Navigation := 'D2';
17: HMI.Navigation := 'D3';
18: HMI.Navigation := 'D4';
19: HMI.Navigation := 'D5';
20: HMI.Navigation := 'D6';
21: HMI.Navigation := 'D7';
22: HMI.Navigation := 'D8';
23: HMI.Navigation := 'P1';
24: HMI.Navigation := 'P2';
25: HMI.Navigation := 'P3';
26: HMI.Navigation := 'P4';
27: HMI.Navigation := 'P5';
28: HMI.Navigation := 'P6';
29: HMI.Navigation := 'P7';
30: HMI.Navigation := 'P8';
31: HMI.Navigation := 'ZH';
32: HMI.Navigation := 'EN';
33: HMI.Navigation := 'REFRESH';
34: HMI.Navigation := 'DISCARD';
35: HMI.Navigation := 'REVIEW';
36: HMI.Navigation := 'COMMIT';
37: HMI.Navigation := 'DEVON';
38: HMI.Navigation := 'DEVOFF';
39: HMI.Navigation := 'POINTON';
40: HMI.Navigation := 'POINTOFF';
41: HMI.Navigation := 'MODEHUB';
42: HMI.Navigation := 'MODELOCAL';
43: HMI.Navigation := 'CYCLIC';
44: HMI.Navigation := 'CHANGE';
45: HMI.Navigation := 'BOTH';
46: HMI.Navigation := 'HOLDING';
47: HMI.Navigation := 'INPUT';
48: HMI.Navigation := 'COIL';
49: HMI.Navigation := 'DISCRETE';
50: HMI.Navigation := 'UINT16';
51: HMI.Navigation := 'INT16';
52: HMI.Navigation := 'UINT32';
53: HMI.Navigation := 'INT32';
54: HMI.Navigation := 'FLOAT32';
55: HMI.Navigation := 'BOOL';
56: HMI.Navigation := 'ADVANCED';
57: HMI.Navigation := 'BROKERREVIEW';
58: HMI.Navigation := 'BROKERCOMMIT';
59: HMI.Navigation := 'HELP';
60: HMI.Navigation := 'TYPEPICK';
61: HMI.Navigation := 'AREAPICK';
62: HMI.Navigation := 'REPORTPICK';
63: HMI.Navigation := 'GATEWAY';
64: HMI.Navigation := 'POINTBACK';
65: HMI.Navigation := 'MODEPAGE';
66: HMI.Navigation := 'MODEKEEP';
67: HMI.Navigation := 'MODECLEAR';
68: HMI.Navigation := 'MODECOMMIT';
END_CASE; GW_Nav := 0;
HMI.LoadPoint := HMI.LoadPoint OR GW_LoadPoint; GW_LoadPoint := FALSE;
HMI.SaveDevice := HMI.SaveDevice OR GW_SaveDevice; GW_SaveDevice := FALSE;
HMI.SavePoint := HMI.SavePoint OR GW_SavePoint; GW_SavePoint := FALSE;
HMI.RemoveDevice := HMI.RemoveDevice OR GW_RemoveDevice; GW_RemoveDevice := FALSE;
HMI.RemovePoint := HMI.RemovePoint OR GW_RemovePoint; GW_RemovePoint := FALSE;
HMI.Apply := HMI.Apply OR GW_Apply; GW_Apply := FALSE;
HMI.SaveBroker := HMI.SaveBroker OR GW_SaveBroker; GW_SaveBroker := FALSE;
Editor(Managed:=Durable.Managed, LocalRevision:=Durable.LocalRevision, Busy := Store.Busy OR (RxStage <> 0) OR AckPending OR (SaveReason <> 0), NowMs := NowMs, Hmi := HMI, Active := Active, Bootstrap := Bootstrap, States := Meters, Samples := Samples);
IF Editor.Submit AND NOT Durable.Managed AND (SaveReason = 0) THEN
    Pending := Durable; Pending.Config := Editor.Draft;
    Pending.LocalRevision := Durable.LocalRevision+1; Pending.LocalChanges := TRUE;
    IF NOT Durable.HasHubBaseline THEN
        Pending.Config.Version := Active.Version+1; Pending.Config.MessageId := CONCAT('hmi-',TO_STRING(Pending.LocalRevision,'{0:d}'),'-',TO_STRING(UnixMs,'{0:d}'));
    END_IF;
    Save := TRUE; SaveReason := 2;
ELSIF Editor.SubmitMode AND (SaveReason = 0) THEN
    Pending := Durable; Pending.Managed := Editor.NewManaged;
    IF Pending.Managed THEN
        IF Durable.HasHubBaseline THEN Pending.Config := Durable.HubConfig; Pending.LocalChanges := FALSE;
        ELSE
            Pending.LocalChanges := TRUE; Pending.ReplayIndex := 0;
            FOR i := 1 TO 32 DO Pending.Requests[i].MessageId := ''; END_FOR;
        END_IF;
    ELSIF Durable.Managed THEN
        IF NOT Durable.LocalChanges AND (Active.Version > 0) THEN Pending.HubConfig := Active; Pending.HasHubBaseline := TRUE; END_IF;
        IF Editor.ClearConfig THEN
            Pending.Config := BlankConfig; Pending.Config.Version := Active.Version; Pending.Config.MessageId := Active.MessageId;
            Pending.Config.batchIntervalMs := 1000; Pending.Config.maxBatchPoints := 32; Pending.LocalChanges := TRUE;
        END_IF;
    END_IF;
    Pending.LocalRevision := Durable.LocalRevision+1; Save := TRUE; SaveReason := 6;
ELSIF Editor.SubmitBroker AND (SaveReason = 0) THEN
    Pending:=Durable; Pending.Bootstrap:=Editor.NewBroker;
    IdentityChanged:=Pending.Bootstrap.GatewayId<>Bootstrap.GatewayId;
    IF IdentityChanged THEN
        Pending.HubConfig:=BlankConfig; Pending.HasHubBaseline:=FALSE; Pending.LocalChanges:=FALSE; Pending.LocalRevision:=0;
        Pending.Config:=BlankConfig; Pending.Config.batchIntervalMs:=1000; Pending.Config.maxBatchPoints:=32;
        Pending.ReplayIndex:=0; FOR i:=1 TO 32 DO Pending.Requests[i].MessageId:=''; END_FOR;
    END_IF;
    IF IdentityChanged THEN
        HMI.Status:='IDENTITY_CHANGE_REQUIRES_MAINTENANCE: preserve RAM ownership; restart through controlled maintenance.';
        IdentityChanged:=FALSE;
    ELSE Save:=TRUE; SaveReason:=3; END_IF;
END_IF;
(* P01 resource fence: actual IEC SIZEOF including existing packet/materialization
   copies and source FB growth; fixed scratch reserve covers call temporaries.
   NG_Durable and the on-disk v4 layout are unchanged. *)
CaptureBuffer.RecordBytes:=SIZEOF(CaptureBuffer.Scratch);
CaptureExtraBytes:=SIZEOF(Outbox)+SIZEOF(Samples)+SIZEOF(Values)+SIZEOF(Item)+SIZEOF(TxPayload)+SIZEOF(EmptyPacket)+SIZEOF(sample)+SIZEOF(point)+SIZEOF(Tx)+SIZEOF(Rx)+SIZEOF(DevicesJson)+SIZEOF(Header)+UDINT#16384+UDINT#135680+UDINT#65536+UDINT#16384+SIZEOF(CaptureSourceEnabled)+SIZEOF(CaptureLivenessStart)+SIZEOF(PipelinePhase)+UDINT#2048; (* audit-v2 FB-instance growth bound; checked against finalized native types *)
CaptureBuffer.LayoutBytes:=SIZEOF(CaptureBuffer)+CaptureExtraBytes;
CaptureBuffer.LayoutValid:=(CaptureBuffer.LayoutBytes<=UDINT#4194304);
IF CaptureBuffer.ActiveSlot=0 THEN
    CaptureConfigSelector(GatewayId:=Bootstrap.GatewayId,CaptureBootId:=BootId,Config:=Active,Buffer:=CaptureBuffer);
    CaptureSlot:=CaptureConfigSelector.Slot;
    IF CaptureSlot>0 THEN
        CaptureBuffer.ActiveSlot:=CaptureSlot; CaptureBuffer.Configs[CaptureSlot].Reserved:=FALSE;
        CaptureBuffer.SamplingGeneration:=1;
    END_IF;
END_IF;
(* An identity change persists a new boot before capture restarts. Its reserved
   empty configuration slot has no source events and may be rebound in place. *)
IF CaptureBuffer.ActiveSlot>0 THEN
IF CaptureBuffer.Configs[CaptureBuffer.ActiveSlot].CaptureBootId<>BootId THEN
    IF CaptureBuffer.Configs[CaptureBuffer.ActiveSlot].References=0 THEN
        CaptureBuffer.Configs[CaptureBuffer.ActiveSlot].CaptureBootId:=BootId;
        IF CaptureBuffer.SamplingGeneration>=ULINT#9007199254740991 THEN CaptureBuffer.CaptureStopped:=TRUE;
        ELSE CaptureBuffer.SamplingGeneration:=CaptureBuffer.SamplingGeneration+1; END_IF;
    ELSE CaptureBuffer.CaptureStopped:=TRUE;
    END_IF;
END_IF;
END_IF;
(* Reserve a dictionary slot before the next scan submits the durable save.
   On full dictionary keep both current configuration and captured history. *)
IF Save AND ((SaveReason=1) OR (SaveReason=2) OR (SaveReason=6) OR ((SaveReason=3) AND IdentityChanged)) THEN
    CaptureConfigSelector(GatewayId:=Pending.Bootstrap.GatewayId,CaptureBootId:=BootId,Config:=Pending.Config,Buffer:=CaptureBuffer);
    ReservedCaptureSlot:=CaptureConfigSelector.Slot;
    IF ReservedCaptureSlot=0 THEN
        Save:=FALSE; HMI.Status:='RESOURCE_LIMIT: capture configuration dictionary full.';
        IF SaveReason=1 THEN Result:='FAILED'; ErrorCode:='RESOURCE_LIMIT'; RxStage:=90; END_IF;
        SaveReason:=0;
    END_IF;
END_IF;
CaptureBuffer.AuditEnabled:=TRUE;
CaptureBuffer.SourceWorkUs:=0; CaptureBuffer.WorkDeadlineUs:=0;
CaptureBuffer.PipelineMarkUs:=GET_MICROSECONDS(TRUE);
AuditDrain(BootId:=BootId,Buffer:=CaptureBuffer);
CaptureBuffer.SourceWorkUs:=GET_MICROSECONDS(TRUE)-CaptureBuffer.PipelineMarkUs;
CaptureReady:=CaptureBuffer.LayoutValid AND NOT CaptureBuffer.CaptureStopped AND (CaptureBuffer.ActiveSlot>0);
(* Initialize all active sources before dispatch; one global timing bracket
   avoids charging hundreds of clock calls against the actual capture work. *)
CaptureBuffer.PipelineMarkUs:=GET_MICROSECONDS(TRUE);
IF NOT ResetMeters AND CaptureReady AND
   ((CaptureBuffer.SourceSweepGeneration<>CaptureBuffer.SamplingGeneration) OR
    (CaptureBuffer.SourceSweepEnabled<>Active.enabled)) THEN
    CaptureBuffer.StaleCheckAt:=ULINT#9007199254740991;
    FOR i:=1 TO Active.DeviceCount DO
        FOR p:=Active.Devices[i].PointStart TO Active.Devices[i].PointStart+Active.Devices[i].PointCount-1 DO
            CaptureSourceEnabled:=Active.enabled AND Active.Devices[i].enabled AND Active.Points[p].enabled;
            (* The core owns the same activation/disable guards. Bind the
               checked point references once instead of repeating the guards
               and wrapper/array lookups for every point in this bulk scan. *)
            CaptureActivation(Index:=TO_UINT(p),Enabled:=CaptureSourceEnabled,NowMs:=NowMs,UnixMs:=UnixMs,
                StaleAfterMs:=Active.Points[p].staleAfterMs,CheckStale:=FALSE,
                Cursor:=CaptureBuffer.Cursors[p],Sample:=Samples[p],Buffer:=CaptureBuffer);
        END_FOR;
    END_FOR;
    CaptureBuffer.SourceSweepGeneration:=CaptureBuffer.SamplingGeneration;
    CaptureBuffer.SourceSweepEnabled:=Active.enabled;
END_IF;
CaptureBuffer.SourceWorkUs:=CaptureBuffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-CaptureBuffer.PipelineMarkUs;
(* At most two new connections per 20 ms scan: spread 50 activations over
   500 ms, within the frozen 5 s grid. Active I/O/final results stay immediate. *)
CaptureBuffer.ConnectBudget:=2;
(* Start up to 100 point reads/s, twice the frozen 50/s input load. Limit
   new reads only; nominal grids and already-completed results are unchanged. *)
CaptureBuffer.PollStartBudget:=2;
Meter1(Enable := (1 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[1], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[1].StateText, LastError => Meters[1].LastError, LastGoodTimestamp => Meters[1].LastGoodTimestamp, Completed => Meters[1].Completed);
Meter2(Enable := (2 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[2], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[2].StateText, LastError => Meters[2].LastError, LastGoodTimestamp => Meters[2].LastGoodTimestamp, Completed => Meters[2].Completed);
Meter3(Enable := (3 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[3], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[3].StateText, LastError => Meters[3].LastError, LastGoodTimestamp => Meters[3].LastGoodTimestamp, Completed => Meters[3].Completed);
Meter4(Enable := (4 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[4], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[4].StateText, LastError => Meters[4].LastError, LastGoodTimestamp => Meters[4].LastGoodTimestamp, Completed => Meters[4].Completed);
Meter5(Enable := (5 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[5], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[5].StateText, LastError => Meters[5].LastError, LastGoodTimestamp => Meters[5].LastGoodTimestamp, Completed => Meters[5].Completed);
Meter6(Enable := (6 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[6], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[6].StateText, LastError => Meters[6].LastError, LastGoodTimestamp => Meters[6].LastGoodTimestamp, Completed => Meters[6].Completed);
Meter7(Enable := (7 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[7], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[7].StateText, LastError => Meters[7].LastError, LastGoodTimestamp => Meters[7].LastGoodTimestamp, Completed => Meters[7].Completed);
Meter8(Enable := (8 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[8], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[8].StateText, LastError => Meters[8].LastError, LastGoodTimestamp => Meters[8].LastGoodTimestamp, Completed => Meters[8].Completed);
Meter9(Enable := (9 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[9], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[9].StateText, LastError => Meters[9].LastError, LastGoodTimestamp => Meters[9].LastGoodTimestamp, Completed => Meters[9].Completed);
Meter10(Enable := (10 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[10], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[10].StateText, LastError => Meters[10].LastError, LastGoodTimestamp => Meters[10].LastGoodTimestamp, Completed => Meters[10].Completed);
Meter11(Enable := (11 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[11], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[11].StateText, LastError => Meters[11].LastError, LastGoodTimestamp => Meters[11].LastGoodTimestamp, Completed => Meters[11].Completed);
Meter12(Enable := (12 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[12], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[12].StateText, LastError => Meters[12].LastError, LastGoodTimestamp => Meters[12].LastGoodTimestamp, Completed => Meters[12].Completed);
Meter13(Enable := (13 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[13], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[13].StateText, LastError => Meters[13].LastError, LastGoodTimestamp => Meters[13].LastGoodTimestamp, Completed => Meters[13].Completed);
Meter14(Enable := (14 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[14], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[14].StateText, LastError => Meters[14].LastError, LastGoodTimestamp => Meters[14].LastGoodTimestamp, Completed => Meters[14].Completed);
Meter15(Enable := (15 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[15], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[15].StateText, LastError => Meters[15].LastError, LastGoodTimestamp => Meters[15].LastGoodTimestamp, Completed => Meters[15].Completed);
Meter16(Enable := (16 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[16], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[16].StateText, LastError => Meters[16].LastError, LastGoodTimestamp => Meters[16].LastGoodTimestamp, Completed => Meters[16].Completed);
Meter17(Enable := (17 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[17], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[17].StateText, LastError => Meters[17].LastError, LastGoodTimestamp => Meters[17].LastGoodTimestamp, Completed => Meters[17].Completed);
Meter18(Enable := (18 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[18], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[18].StateText, LastError => Meters[18].LastError, LastGoodTimestamp => Meters[18].LastGoodTimestamp, Completed => Meters[18].Completed);
Meter19(Enable := (19 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[19], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[19].StateText, LastError => Meters[19].LastError, LastGoodTimestamp => Meters[19].LastGoodTimestamp, Completed => Meters[19].Completed);
Meter20(Enable := (20 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[20], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[20].StateText, LastError => Meters[20].LastError, LastGoodTimestamp => Meters[20].LastGoodTimestamp, Completed => Meters[20].Completed);
Meter21(Enable := (21 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[21], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[21].StateText, LastError => Meters[21].LastError, LastGoodTimestamp => Meters[21].LastGoodTimestamp, Completed => Meters[21].Completed);
Meter22(Enable := (22 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[22], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[22].StateText, LastError => Meters[22].LastError, LastGoodTimestamp => Meters[22].LastGoodTimestamp, Completed => Meters[22].Completed);
Meter23(Enable := (23 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[23], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[23].StateText, LastError => Meters[23].LastError, LastGoodTimestamp => Meters[23].LastGoodTimestamp, Completed => Meters[23].Completed);
Meter24(Enable := (24 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[24], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[24].StateText, LastError => Meters[24].LastError, LastGoodTimestamp => Meters[24].LastGoodTimestamp, Completed => Meters[24].Completed);
Meter25(Enable := (25 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[25], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[25].StateText, LastError => Meters[25].LastError, LastGoodTimestamp => Meters[25].LastGoodTimestamp, Completed => Meters[25].Completed);
Meter26(Enable := (26 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[26], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[26].StateText, LastError => Meters[26].LastError, LastGoodTimestamp => Meters[26].LastGoodTimestamp, Completed => Meters[26].Completed);
Meter27(Enable := (27 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[27], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[27].StateText, LastError => Meters[27].LastError, LastGoodTimestamp => Meters[27].LastGoodTimestamp, Completed => Meters[27].Completed);
Meter28(Enable := (28 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[28], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[28].StateText, LastError => Meters[28].LastError, LastGoodTimestamp => Meters[28].LastGoodTimestamp, Completed => Meters[28].Completed);
Meter29(Enable := (29 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[29], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[29].StateText, LastError => Meters[29].LastError, LastGoodTimestamp => Meters[29].LastGoodTimestamp, Completed => Meters[29].Completed);
Meter30(Enable := (30 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[30], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[30].StateText, LastError => Meters[30].LastError, LastGoodTimestamp => Meters[30].LastGoodTimestamp, Completed => Meters[30].Completed);
Meter31(Enable := (31 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[31], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[31].StateText, LastError => Meters[31].LastError, LastGoodTimestamp => Meters[31].LastGoodTimestamp, Completed => Meters[31].Completed);
Meter32(Enable := (32 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[32], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[32].StateText, LastError => Meters[32].LastError, LastGoodTimestamp => Meters[32].LastGoodTimestamp, Completed => Meters[32].Completed);
Meter33(Enable := (33 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[33], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[33].StateText, LastError => Meters[33].LastError, LastGoodTimestamp => Meters[33].LastGoodTimestamp, Completed => Meters[33].Completed);
Meter34(Enable := (34 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[34], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[34].StateText, LastError => Meters[34].LastError, LastGoodTimestamp => Meters[34].LastGoodTimestamp, Completed => Meters[34].Completed);
Meter35(Enable := (35 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[35], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[35].StateText, LastError => Meters[35].LastError, LastGoodTimestamp => Meters[35].LastGoodTimestamp, Completed => Meters[35].Completed);
Meter36(Enable := (36 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[36], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[36].StateText, LastError => Meters[36].LastError, LastGoodTimestamp => Meters[36].LastGoodTimestamp, Completed => Meters[36].Completed);
Meter37(Enable := (37 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[37], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[37].StateText, LastError => Meters[37].LastError, LastGoodTimestamp => Meters[37].LastGoodTimestamp, Completed => Meters[37].Completed);
Meter38(Enable := (38 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[38], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[38].StateText, LastError => Meters[38].LastError, LastGoodTimestamp => Meters[38].LastGoodTimestamp, Completed => Meters[38].Completed);
Meter39(Enable := (39 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[39], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[39].StateText, LastError => Meters[39].LastError, LastGoodTimestamp => Meters[39].LastGoodTimestamp, Completed => Meters[39].Completed);
Meter40(Enable := (40 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[40], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[40].StateText, LastError => Meters[40].LastError, LastGoodTimestamp => Meters[40].LastGoodTimestamp, Completed => Meters[40].Completed);
Meter41(Enable := (41 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[41], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[41].StateText, LastError => Meters[41].LastError, LastGoodTimestamp => Meters[41].LastGoodTimestamp, Completed => Meters[41].Completed);
Meter42(Enable := (42 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[42], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[42].StateText, LastError => Meters[42].LastError, LastGoodTimestamp => Meters[42].LastGoodTimestamp, Completed => Meters[42].Completed);
Meter43(Enable := (43 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[43], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[43].StateText, LastError => Meters[43].LastError, LastGoodTimestamp => Meters[43].LastGoodTimestamp, Completed => Meters[43].Completed);
Meter44(Enable := (44 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[44], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[44].StateText, LastError => Meters[44].LastError, LastGoodTimestamp => Meters[44].LastGoodTimestamp, Completed => Meters[44].Completed);
Meter45(Enable := (45 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[45], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[45].StateText, LastError => Meters[45].LastError, LastGoodTimestamp => Meters[45].LastGoodTimestamp, Completed => Meters[45].Completed);
Meter46(Enable := (46 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[46], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[46].StateText, LastError => Meters[46].LastError, LastGoodTimestamp => Meters[46].LastGoodTimestamp, Completed => Meters[46].Completed);
Meter47(Enable := (47 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[47], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[47].StateText, LastError => Meters[47].LastError, LastGoodTimestamp => Meters[47].LastGoodTimestamp, Completed => Meters[47].Completed);
Meter48(Enable := (48 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[48], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[48].StateText, LastError => Meters[48].LastError, LastGoodTimestamp => Meters[48].LastGoodTimestamp, Completed => Meters[48].Completed);
Meter49(Enable := (49 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[49], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[49].StateText, LastError => Meters[49].LastError, LastGoodTimestamp => Meters[49].LastGoodTimestamp, Completed => Meters[49].Completed);
Meter50(Enable := (50 <= Active.DeviceCount) AND Active.enabled AND CaptureReady, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[50], Points := Active.Points, Samples := Samples, Buffer := CaptureBuffer, StateText => Meters[50].StateText, LastError => Meters[50].LastError, LastGoodTimestamp => Meters[50].LastGoodTimestamp, Completed => Meters[50].Completed);
(* Same-scan final physical results win over stale transitions. *)
CaptureBuffer.PipelineMarkUs:=GET_MICROSECONDS(TRUE);
IF NOT ResetMeters AND CaptureReady AND (NowMs>=CaptureBuffer.StaleCheckAt) THEN
    CaptureBuffer.StaleCheckAt:=ULINT#9007199254740991;
    FOR p:=1 TO Active.PointCount DO
        CaptureLivenessStart:=CaptureBuffer.SourceStaleDue[p];
        IF CaptureLivenessStart>0 THEN
            IF NowMs>=CaptureLivenessStart THEN
                CaptureState(Index:=TO_UINT(p),Enabled:=CaptureBuffer.Cursors[p].Enabled,NowMs:=NowMs,UnixMs:=UnixMs,
                    StaleAfterMs:=Active.Points[p].staleAfterMs,CheckStale:=TRUE,Samples:=Samples,Buffer:=CaptureBuffer);
                CaptureLivenessStart:=CaptureBuffer.SourceStaleDue[p];
            END_IF;
            IF (CaptureLivenessStart>0) AND (CaptureLivenessStart<CaptureBuffer.StaleCheckAt) THEN
                CaptureBuffer.StaleCheckAt:=CaptureLivenessStart;
            END_IF;
        END_IF;
    END_FOR;
END_IF;
CaptureBuffer.SourceWorkUs:=CaptureBuffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-CaptureBuffer.PipelineMarkUs;
IF NowMs >= LastGet+30000 THEN GetPending := TRUE; END_IF;
(* Match IoT's 30-second heartbeat in Hub mode. A 50-device heartbeat causes
   50 state writes in Hub; sending it every five seconds starves telemetry. *)
IF (Durable.Managed AND (NowMs>=LastHeartbeat+30000)) OR
   (NOT Durable.Managed AND (NowMs>=LastHeartbeat+5000)) THEN HeartbeatPending:=TRUE; END_IF;
(* ENQUEUE and SEND are separate. Already admitted histories survive time loss. *)
DataGate:=Mqtt.Connected AND TelemetryAllowed AND (UnixMs>0) AND NOT CaptureBuffer.CaptureStopped;
EnqueueGate:=TelemetryAllowed AND (UnixMs>0) AND NOT CaptureBuffer.CaptureStopped;
IF TimeMode THEN
    EnqueueGate:=EnqueueGate AND NativeClock.EnqueueAllowed;
    DataGate:=DataGate AND NativeClock.SendAllowed;
END_IF;
(* Mandatory physical capture is never delayed. Share the remaining 825 us.
   Builder plus its first hash consumes about three fifths of isolated cost.
   Five scans grant three builder-first turns and two delivery-first turns;
   the inner two-call priority hold gives send and ACK equal delivery turns. *)
CaptureBuffer.PipelineMarkUs:=GET_MICROSECONDS(TRUE);
CaptureBuffer.WorkDeadlineUs:=CaptureBuffer.PipelineMarkUs+ULINT#1;
IF CaptureBuffer.SourceWorkUs<ULINT#825 THEN CaptureBuffer.WorkDeadlineUs:=CaptureBuffer.WorkDeadlineUs+ULINT#825-CaptureBuffer.SourceWorkUs; END_IF;
PipelinePhase:=TO_USINT(PipelinePhase+1); IF PipelinePhase>5 THEN PipelinePhase:=1; END_IF;
CaptureBuffer.WorkTurn:=(PipelinePhase<>2) AND (PipelinePhase<>4);
BufferMaintenance(GateOpen:=DataGate,NowMs:=NowMs,Buffer:=CaptureBuffer,Packets:=Outbox);
ReportPolicy(DeferCapacity:=TRUE,Buffer:=CaptureBuffer);
IF CaptureBuffer.WorkTurn THEN
BatchBuilder(GateOpen:=EnqueueGate,NowMs:=NowMs,UnixMs:=UnixMs,GatewayId:=Bootstrap.GatewayId,BootId:=BootId,BatchIntervalMs:=Active.batchIntervalMs,Buffer:=CaptureBuffer,Packets:=Outbox,Sequence:=Sequence);
Delivery(GateOpen:=DataGate,NowMs:=NowMs,GatewayId:=Bootstrap.GatewayId,BootId:=BootId,
    SubmitAck:=SubmitDataAck,AckMessageId:=DataAckId,AckStored:=DataAckStored,AckRetryable:=DataAckRetryable,AckCodes:=DataAckCodes,
    Buffer:=CaptureBuffer,Packets:=Outbox);
ELSE
Delivery(GateOpen:=DataGate,NowMs:=NowMs,GatewayId:=Bootstrap.GatewayId,BootId:=BootId,
    SubmitAck:=SubmitDataAck,AckMessageId:=DataAckId,AckStored:=DataAckStored,AckRetryable:=DataAckRetryable,AckCodes:=DataAckCodes,
    Buffer:=CaptureBuffer,Packets:=Outbox);
BatchBuilder(GateOpen:=EnqueueGate,NowMs:=NowMs,UnixMs:=UnixMs,GatewayId:=Bootstrap.GatewayId,BootId:=BootId,BatchIntervalMs:=Active.batchIntervalMs,Buffer:=CaptureBuffer,Packets:=Outbox,Sequence:=Sequence);
END_IF;
QueueCount:=0;
CheckCounters(Buffer:=CaptureBuffer);
Diagnostics(BootId:=BootId,GatewayId:=Bootstrap.GatewayId,NowMs:=NowMs,Force:=FALSE,Buffer:=CaptureBuffer);
HMI.ResourceStatus:=CaptureBuffer.Diagnostics.HmiSummary;
CaptureBuffer.WorkLastUs:=CaptureBuffer.SourceWorkUs+GET_MICROSECONDS(TRUE)-CaptureBuffer.PipelineMarkUs;
CaptureBuffer.WorkMaxUs:=MAX(CaptureBuffer.WorkMaxUs,CaptureBuffer.WorkLastUs);
FOR q:=1 TO 16 DO IF CaptureBuffer.BatchOwners[q].State>=2 THEN QueueCount:=QueueCount+1; END_IF; END_FOR;
HMI.ConfirmedBatches:=TO_UDINT(MIN(CaptureBuffer.StoredBatchesTotal,ULINT#4294967295));
IF TxActive THEN
    IF Mqtt.TxRejected THEN TxActive:=FALSE;
    ELSIF Mqtt.TxDone THEN
        TxActive := FALSE;
        CASE TxKind OF
            1: AckPending := FALSE; GetPending:=TRUE;
            2: GetPending := FALSE; LastGet := NowMs;
            3: StatusPending := FALSE;
            4:
                HeartbeatPending := FALSE; LastHeartbeat := NowMs;
                (* Heartbeat already carries these device states. Emit
                   device/status only for changes after that snapshot. *)
                DeviceSignatures:=HeartbeatSignatures;
            5:
                (* PUBACK is transport completion only; deadline starts at SDK submission. *)
                HMI.PublishedBatches := HMI.PublishedBatches+1;
            6: ResourcesPending := FALSE;
            7: DeviceSignatures[EventTxIndex]:=EventTxSignature;
        END_CASE;
    ELSIF NOT Mqtt.Connected THEN TxActive := FALSE; END_IF;
END_IF;
DeviceEventPending:=FALSE;
IF TelemetryAllowed AND (Active.Version>0) AND NOT HeartbeatPending THEN
    FOR d:=1 TO Active.DeviceCount DO
        Status:=Meters[d].StateText; EnabledPoints:=0;
        FOR p:=1 TO Active.Devices[d].PointCount DO IF Active.Points[Active.Devices[d].PointStart+p-1].enabled THEN EnabledPoints:=EnabledPoints+1; END_IF; END_FOR;
        IF NOT Active.enabled OR NOT Active.Devices[d].enabled OR (EnabledPoints=0) THEN Status:='DISABLED'; END_IF;
        DeviceEventSignature:=CONCAT(SessionId,'/',TO_STRING(Active.Version,'{0:d}'),'/',Status,'/',Meters[d].LastError);
        IF DeviceSignatures[d]<>DeviceEventSignature THEN
            DeviceEventPending:=TRUE; DeviceEventIndex:=d;
            LastErrorJson:='null'; LastGoodJson:='null';
            IF Status<>'DISABLED' THEN
                IF Meters[d].LastError<>'' THEN LastErrorJson:=NG_Quote(Meters[d].LastError); END_IF;
                IF Meters[d].LastGoodTimestamp>0 THEN LastGoodJson:=TO_STRING(Meters[d].LastGoodTimestamp,'{0:d}'); END_IF;
            END_IF;
            DevicesJson:=CONCAT('{"deviceId":',NG_Quote(Active.Devices[d].deviceId),',"status":',NG_Quote(Status),',"lastError":',LastErrorJson,',"lastGoodTimestamp":',LastGoodJson,'}');
            EXIT;
        END_IF;
    END_FOR;
END_IF;
DeadCount:=0; FOR q:=1 TO 16 DO IF Outbox[q].Dead THEN DeadCount:=DeadCount+1; END_IF; END_FOR;
HMI.DeadBatches:=TO_STRING(DeadCount,'{0:d}');
IF NOT TxActive AND Mqtt.Connected AND NOT Mqtt.TxBusy THEN
    TxKind := 0; TxRetain := FALSE;
    IF AckPending AND ((AckActiveVersion<>HubActiveVersion) OR (AckActiveMessageId<>HubActiveMessageId)) THEN
        AckPending:=FALSE; GetPending:=TRUE;
    END_IF;
    IF TimeMode AND NativeClock.RequestWanted THEN
        TxKind:=8; TxTopic:=CONCAT(Prefix,'time/request'); TxPayload:='{}';
    ELSIF TimeMode AND NOT NativeClock.ControlAllowed THEN TxKind:=0;
    ELSIF TimeMode AND NOT NativeClock.HeartbeatReady THEN HeartbeatPending:=TRUE;
    ELSIF TimeMode AND NOT NativeClock.ConfigGetReady THEN GetPending:=TRUE; HeartbeatPending:=FALSE;
    END_IF;
    IF (TxKind=0) AND (NOT TimeMode OR NativeClock.ControlAllowed) THEN
    IF AckPending AND (NOT TimeMode OR NativeClock.ConfigGetReady) THEN TxKind := 1; TxPayload := CONCAT(Header,AckPayload); TxTopic := AckTopic;
    ELSIF GetPending AND Durable.Managed AND NOT HeartbeatPending THEN
        TxKind := 2; TxTopic := CONCAT(Prefix,'config/get');
        GetSequence:=GetSequence+1;
        TxPayload := CONCAT(Header,',"messageId":',NG_Quote(CONCAT('g-',BootNamespace,'-',TO_STRING(Durable.BootCounter,'{0:d}'),'-',TO_STRING(GetSequence,'{0:d}'))),',"activeConfigVersion":',TO_STRING(HubActiveVersion, '{0:d}'),',"sessionId":',NG_Quote(SessionId),',"configCapabilities":["devicePatchV1"],"activeMessageId":');
        IF HubActiveVersion = 0 THEN TxPayload := CONCAT(TxPayload,'null}'); ELSE TxPayload := CONCAT(TxPayload,NG_Quote(HubActiveMessageId),'}'); END_IF;
    ELSIF StatusPending AND NOT HeartbeatPending AND (NOT TimeMode OR NativeClock.ConfigGetReady) THEN
        TxKind := 3; TxTopic := CONCAT(Prefix,'status'); TxRetain := TRUE;
        TxPayload := CONCAT(Header,',"online":true,"reason":"connected","sessionId":',NG_Quote(SessionId),'}');
    ELSIF HeartbeatPending THEN
        QueueBytes := 0; FOR q := 1 TO 16 DO IF Outbox[q].MessageId <> '' THEN QueueBytes := QueueBytes+Outbox[q].Length; END_IF; END_FOR;
        TxKind := 4; TxTopic := CONCAT(Prefix,'heartbeat'); DevicesJson := ''; Total := 0; GoodCount := 0;
        IF TelemetryAllowed THEN
        FOR d := 1 TO Active.DeviceCount DO
            IF d>1 THEN DevicesJson := CONCAT(DevicesJson,','); END_IF;
            Status:=Meters[d].StateText; EnabledPoints:=0;
            FOR p:=1 TO Active.Devices[d].PointCount DO IF Active.Points[Active.Devices[d].PointStart+p-1].enabled THEN EnabledPoints:=EnabledPoints+1; END_IF; END_FOR;
            IF NOT Active.enabled OR NOT Active.Devices[d].enabled OR (EnabledPoints=0) THEN Status:='DISABLED'; END_IF;
            HeartbeatSignatures[d]:=CONCAT(SessionId,'/',TO_STRING(Active.Version,'{0:d}'),'/',Status,'/',Meters[d].LastError);
            LastErrorJson := 'null'; IF Meters[d].LastError <> '' THEN LastErrorJson := NG_Quote(Meters[d].LastError); END_IF;
            LastGoodJson := 'null'; IF Meters[d].LastGoodTimestamp>0 THEN LastGoodJson := TO_STRING(Meters[d].LastGoodTimestamp, '{0:d}'); END_IF;
            IF Status='DISABLED' THEN LastErrorJson:='null'; LastGoodJson:='null'; END_IF;
            DevicesJson := CONCAT(DevicesJson,'{"deviceId":',NG_Quote(Active.Devices[d].deviceId),',"status":',NG_Quote(Status),',"lastError":',LastErrorJson,',"lastGoodTimestamp":',LastGoodJson,'}');
            IF Active.enabled AND Active.Devices[d].enabled THEN
                FOR p := 1 TO Active.Devices[d].PointCount DO IF Active.Points[Active.Devices[d].PointStart+p-1].enabled THEN Total := Total+1; IF Samples[Active.Devices[d].PointStart+p-1].Quality='GOOD' THEN GoodCount := GoodCount+1; END_IF; END_IF; END_FOR;
            END_IF;
        END_FOR;
        END_IF;
        IF NOT TelemetryAllowed OR (Active.Version=0) THEN StateName := 'WAITING_CONFIG'; ELSIF Active.enabled THEN StateName := 'RUNNING'; ELSE StateName := 'DISABLED'; END_IF;
        TxPayload := CONCAT(Header,',"sessionId":',NG_Quote(SessionId),',"bootId":',NG_Quote(BootId),',"agentVersion":"native-0.7.1-audit-candidate.2","activeConfigVersion":',TO_STRING(HubActiveVersion, '{0:d}'),',"uptimeSeconds":',TO_STRING(NowMs/1000, '{0:d}'),',"agentState":',NG_Quote(StateName),',"devices":[',DevicesJson,'],"points":{"total":',TO_STRING(Total, '{0:d}'),',"good":',TO_STRING(GoodCount, '{0:d}'),',"bad":',TO_STRING(Total-GoodCount, '{0:d}'),'},"queue":{"batches":',TO_STRING(QueueCount, '{0:d}'),',"payloadBytes":',TO_STRING(QueueBytes, '{0:d}'),',"droppedBatches":',TO_STRING(Dropped, '{0:d}'),'}}');
    ELSIF DeviceEventPending AND (NOT TimeMode OR NativeClock.ConfigGetReady) THEN
        TxKind:=7; TxTopic:=CONCAT(Prefix,'device/status');
        EventTxIndex:=DeviceEventIndex; EventTxSignature:=DeviceEventSignature;
        TxPayload:=CONCAT(Header,',"sessionId":',NG_Quote(SessionId),',"configVersion":',TO_STRING(Active.Version,'{0:d}'),',"device":',DevicesJson,'}');
    ELSIF ResourcesPending AND (NOT TimeMode OR NativeClock.SendAllowed) THEN
        TxKind := 6; TxTopic := CONCAT(Prefix,'diagnostics/resources');
        TxPayload := CONCAT(Header,',"bootId":',NG_Quote(BootId),',"uptimeMs":',TO_STRING(NowMs,'{0:d}'),',"memoryValid":',NG_Bool(Resources.MemoryValid),',"cpuValid":',NG_Bool(Resources.CpuValid),',"processValid":',NG_Bool(Resources.ProcessValid),',"totalKiB":',TO_STRING(Resources.TotalKiB,'{0:d}'),',"availableKiB":',TO_STRING(Resources.AvailableKiB,'{0:d}'),',"rssKiB":',TO_STRING(Resources.RssKiB,'{0:d}'),',"cpuPercent":',TO_STRING(TO_LREAL(Resources.CpuPermille)/10.0,'{0:F1}'),',"processName":',NG_Quote(Resources.ProcessName),',"error":',NG_Quote(Resources.ErrorText),',"configBytes":',TO_STRING(SIZEOF(Active),'{0:d}'),',"devices":',TO_STRING(Active.DeviceCount,'{0:d}'),',"points":',TO_STRING(Active.PointCount,'{0:d}'),'}');
    ELSIF DataGate AND (Delivery.SendSlot>0) THEN
        Head:=TO_INT(Delivery.SendSlot);
        IF (CaptureBuffer.BatchGenerations[Head]=Delivery.SendGeneration) AND
           (Outbox[Head].MessageId=Delivery.SendMessageId) AND (CaptureBuffer.BatchOwners[Head].State=2) AND
           (NowMs>=CaptureBuffer.NextSendAt) AND (NowMs>=Outbox[Head].RetryAtMs) THEN
            TxKind:=5; TxPayload:=Outbox[Head].Payload; TxTopic:=CONCAT(Prefix,'data');
            TxBatchGeneration:=Delivery.SendGeneration;
        END_IF;
    END_IF;
    END_IF;
    IF TxKind<>0 THEN
        CopyString(REQ := FALSE,BUF_FORMAT := FALSE,BUF_OFFS := 0,BUF_CNT := LEN(TxPayload),SRC := TxPayload,BUFFER := Tx);
        CopyString(REQ := TRUE,BUF_FORMAT := FALSE,BUF_OFFS := 0,BUF_CNT := LEN(TxPayload),SRC := TxPayload,BUFFER := Tx);
        IF CopyString.DONE AND ((TxKind<>5) OR (DataGate AND (CaptureBuffer.BatchGenerations[Head]=TxBatchGeneration) AND (CaptureBuffer.BatchOwners[Head].State=2))) THEN
            TxLength := TO_UDINT(LEN(TxPayload)); TxRequest := TRUE; TxActive := TRUE;
            TxClockRevision:=NativeClock.ClockRevision; TxConnectionRevision:=NativeClock.ConnectionRevision;
            TxTokenMonoMs:=NowMs; TxBootId:=BootId;
            (* A fast committed business ACK may precede the library PublishDone. *)
            IF TxKind=5 THEN
                TxBatchId:=Outbox[Head].MessageId;
            END_IF;
        END_IF;
    END_IF;
END_IF;
SdkSendGate:=NOT TimeMode OR NativeClock.SendAllowed;
IF TxKind=5 THEN
    SdkSendGate:=DataGate AND (Head>=1) AND (Head<=16);
    IF SdkSendGate THEN SdkSendGate:=(CaptureBuffer.BatchGenerations[Head]=TxBatchGeneration)
        AND (CaptureBuffer.BatchOwners[Head].State=2) AND (Outbox[Head].MessageId=TxBatchId); END_IF;
END_IF;
Mqtt(Enable := Initialized AND StartupReady,Reconnect := Reconnect,NowMs := NowMs,Bootstrap := Bootstrap,BootId:=BootId,TxRequest := TxRequest,TxTopic := TxTopic,TxLength := TxLength,TxRetain := TxRetain,RxAccept := RxAccept,TxBuffer := Tx,RxBuffer := Rx,
    PlatformTime:=TimeMode,TxKind:=TxKind,TxClockRevision:=TxClockRevision,TxConnectionRevision:=TxConnectionRevision,TxBootId:=TxBootId,
    ClockRevision:=NativeClock.ClockRevision,ConnectionRevision:=NativeClock.ConnectionRevision,SnapshotMonoMs:=TxTokenMonoMs,
    ControlAllowed:=NativeClock.ControlAllowed,SendAllowed:=SdkSendGate,TimeRequestId:=NativeClock.RequestId);
HMI.ActiveMessageId:=Active.MessageId;
IF Mqtt.Connected THEN HMI.ProtocolStatus:='CONNECTED'; ELSE HMI.ProtocolStatus:=Mqtt.ErrorText; END_IF;
IF TimeMode THEN
    HMI.ProtocolStatus:=CONCAT(HMI.ProtocolStatus,' HUB time state=',TO_STRING(NativeClock.State,'{0:d}'),' valid=',NG_Bool(NativeClock.TimeValid),' utc=',TO_STRING(NativeClock.UtcMs,'{0:d}'),' error=',TO_STRING(NativeClock.UncertaintyMs,'{0:d}'),' age=',TO_STRING(NativeClock.SyncAgeMs,'{0:d}'),' basis=',TimeBasis);
END_IF;
HMI.ActiveVersion := TO_STRING(Active.Version, '{0:d}'); HMI.DeviceCount := TO_STRING(Active.DeviceCount, '{0:d}'); HMI.QueueCount := TO_STRING(QueueCount, '{0:d}'); HMI.Dropped := TO_STRING(Dropped, '{0:d}');
IF Mqtt.Connected THEN HMI.Connection := 'CONNECTED'; ELSE HMI.Connection := 'CONNECTING'; END_IF;
IF Mqtt.ErrorText<>'' THEN HMI.Connection := LEFT(Mqtt.ErrorText,MIN(LEN(Mqtt.ErrorText),24)); END_IF;
IF NG_Range(HMI.DeviceIndex,1,50,TRUE) AND NG_Range(HMI.PointIndex,1,32,TRUE) THEN
    d := TO_INT(HMI.DeviceIndex); p := TO_INT(HMI.PointIndex);
    IF (d <= Active.DeviceCount) AND (p <= Active.Devices[d].PointCount) THEN
        HMI.LastValue := TO_STRING(Samples[Active.Devices[d].PointStart+p-1].Value,'{0:F6}'); HMI.LastQuality := Samples[Active.Devices[d].PointStart+p-1].Quality; HMI.LastTimestamp := TO_STRING(Samples[Active.Devices[d].PointStart+p-1].Timestamp, '{0:d}'); HMI.DeviceStatus := Meters[d].StateText;
    ELSE HMI.LastValue := ''; HMI.LastQuality := 'UNKNOWN'; HMI.LastTimestamp := ''; HMI.DeviceStatus := 'UNCONFIGURED'; END_IF;
END_IF;
HMI.UiStatus:=NG_UiText(HMI.Status,HMI.English);
HMI.UiConnection:=NG_UiText(HMI.Connection,HMI.English);
HMI.UiQuality:=NG_UiText(HMI.LastQuality,HMI.English);
IF Store.Busy THEN HMI.UiPersistence:=NG_UiText('Saving / validating durable file...',HMI.English);
ELSIF Store.Error THEN HMI.UiPersistence:=NG_UiText('STORAGE ERROR: configuration not committed.',HMI.English);
ELSIF HMI.English THEN HMI.UiPersistence:=NG_UiJoin("Saved to controller · generation ",TO_WSTRING(Durable.Generation,"{0:d}")," · restores automatically after restart","","","","","");
ELSE HMI.UiPersistence:=NG_UiJoin("已保存到控制器 · 保存序号 ",TO_WSTRING(Durable.Generation,"{0:d}")," · 重启后自动恢复","","","","",""); END_IF;
IF NOT StartupReady THEN HMI.UiLiveStatus:=NG_UiText('Restoring saved configuration...',HMI.English);
ELSIF NOT Mqtt.Connected THEN HMI.UiLiveStatus:=NG_UiText('Broker unavailable. Retrying automatically; local acquisition continues.',HMI.English);
ELSIF NOT TelemetryAllowed THEN HMI.UiLiveStatus:=NG_UiText('Local changes active. Acquisition continues; Hub data reporting is paused.',HMI.English);
ELSIF HMI.English THEN HMI.UiLiveStatus:=NG_UiJoin("Connected · collecting ",TO_WSTRING(HMI.TotalPoints,"")," points · awaiting storage ACK: ",TO_WSTRING(HMI.QueueCount,""),"","","","");
ELSE HMI.UiLiveStatus:=NG_UiJoin("已连接 · 正在采集 ",TO_WSTRING(HMI.TotalPoints,"")," 个点位 · 待平台入库确认 ",TO_WSTRING(HMI.QueueCount,"")," 批","","",""); END_IF;
HMI.LocalChanges := Durable.LocalChanges;
HMI.LocalRevision := TO_STRING(Durable.LocalRevision,'{0:d}');
HMI.HubBaselineVersion := TO_STRING(Durable.HubConfig.Version,'{0:d}');
IF Durable.Managed AND NOT Durable.HasHubBaseline AND Durable.LocalChanges THEN HMI.UiMaintenance := NG_UiText('Waiting for initial Hub configuration. Existing local acquisition is retained.',HMI.English);
ELSIF Durable.Managed THEN HMI.UiMaintenance := NG_UiText('Hub owns configuration. Local maintenance requires manual confirmation.',HMI.English);
ELSIF Durable.HasHubBaseline AND Durable.LocalChanges THEN HMI.UiMaintenance := NG_UiText('Local changes active. Acquisition continues; Hub data reporting is paused.',HMI.English);
ELSE HMI.UiMaintenance := NG_UiText('Local maintenance active. Hub configuration is locked until you return ownership.',HMI.English); END_IF;
END_PROGRAM
