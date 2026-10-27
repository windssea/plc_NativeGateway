FUNCTION_BLOCK NG_Mqtt
VAR_INPUT
    Enable : BOOL;
    BootId : NG_Id;
    Reconnect : BOOL;
    NowMs : ULINT;
    Bootstrap : NG_Bootstrap;
    TxRequest : BOOL;
    TxTopic : STRING[200];
    TxLength : UDINT;
    TxRetain : BOOL;
    RxAccept : BOOL;
    PlatformTime : BOOL;
    TxKind : INT;
    TxClockRevision : ULINT;
    TxBootId : NG_Id;
    TxConnectionRevision : ULINT;
    ClockRevision : ULINT;
    ConnectionRevision : ULINT;
    SnapshotMonoMs : ULINT;
    ControlAllowed : BOOL;
    SendAllowed : BOOL;
    TimeRequestId : NG_Id;
END_VAR
VAR_IN_OUT
    TxBuffer : NG_Bytes;
    RxBuffer : NG_Bytes;
END_VAR
VAR_OUTPUT
    Connected : BOOL;
    TxBusy : BOOL;
    TxDone : BOOL;
    RxReady : BOOL;
    RxTopic : STRING[500];
    RxLength : UDINT;
    RxRetained : BOOL;
    ErrorText : NG_Text;
    SessionCount : UDINT;
    WillCapacity : UDINT;
    WillEnabled : BOOL;
    DebugState : INT;
    TxInvoked : BOOL;
    TxSubmitted : BOOL;
    TxRejected : BOOL;
    SubmittedKind : INT;
    TxSubmitMonoMs : ULINT;
    RxReceivedMonoMs : ULINT;
END_VAR
VAR
    Client : IIoT_MqttClient_6;
    Options : MQTT_UDT_CONNECT_OPTIONS;
    ConnectStatus : MQTT_UDT_METHOD_STATUS;
    ConsumeStatus : MQTT_UDT_METHOD_STATUS;
    SubscribeStatus : MQTT_UDT_METHOD_STATUS;
    PublishStatus : MQTT_UDT_METHOD_STATUS;
    ReceiveStatus : MQTT_UDT_METHOD_STATUS;
    CheckStatus : MQTT_UDT_METHOD_STATUS;
    Info : MQTT_UDT_MESSAGE_INFO;
    State : INT;
    SubscribeIndex : INT;
    Filter : STRING[200];
    Prefix : STRING[150];
    server : STRING[200];
    id : STRING[128];
    user : STRING;
    password : STRING;
    ReadyClient : BOOL;
    NewMessage : BOOL;
    ConnectedResult : BOOL;
    ConsumeReq : BOOL;
    CheckReq : BOOL;
    PublishReq : BOOL;
    LastCheck : ULINT;
    RetryAt : ULINT;
    Deadline : ULINT;
    PrevTx : BOOL;
    WillSession : NG_Id;
    WillPayload : STRING[512];
    PublishPulse : BOOL;
    PublishLength : UDINT;
    TimePayload : STRING[512];
    TimeCopy : STRING_TO_BUF;
    TimePermit : NG_TimePermit;
END_VAR
TxDone := FALSE;
TxInvoked:=FALSE; TxSubmitted:=FALSE; TxRejected:=FALSE;
IF RxAccept THEN RxReady := FALSE; END_IF;
IF Reconnect OR NOT Enable THEN State := 900; END_IF;
IF State = 0 THEN
    server := Bootstrap.BrokerUri; id := Bootstrap.ClientId;
    user := Bootstrap.UserName; password := Bootstrap.Password;
    Prefix := CONCAT('iot/v1/gateway/',Bootstrap.GatewayId,'/');
    Options.diConnectTimeout := 5; Options.diKeepAliveInterval := 20;
    Options.xCleanSession := TRUE; Options.diMqttVersion := 4;
    Options.diMaxInflight := 4; Options.xAutomaticReconnect := FALSE;
    WillSession:=CONCAT(BootId,'-',TO_STRING(SessionCount+1,'{0:d}'));
    WillCapacity:=80; (* Vendor field is IecString80; SIZEOF also includes terminator/header. *)
    WillPayload:=CONCAT('{"schemaVersion":1,"gatewayId":',NG_Quote(Bootstrap.GatewayId),',"timestamp":null,"sessionId":',NG_Quote(WillSession),',"online":false,"reason":"connection_lost"}');
    WillEnabled:=(TO_UDINT(LEN(WillPayload))<=WillCapacity) AND (LEN(Prefix)+6<=80);
    Options.xUseWillOptions:=WillEnabled;
    IF WillEnabled THEN
        Options.udtWill.strTopic:=CONCAT(Prefix,'status'); Options.udtWill.strPayload:=WillPayload;
    ELSE Options.udtWill.strTopic:=''; Options.udtWill.strPayload:=''; END_IF;
    Options.udtWill.diQos:=1; Options.udtWill.xRetained:=TRUE;
    ErrorText := ''; Connected := FALSE; Deadline := NowMs + 15000;
    State := 5;
END_IF;
Client(EN := Enable AND (State < 900), strServerUri := server, strClientId := id, strPersistDir := '', diMaxBufferedMessages := DINT#0, ENO => ReadyClient);
Client.Connect(State = 10, user, password, Options, ConnectStatus);
Client.StartConsuming(State = 20, ConsumeStatus);
Client.Subscribe(State = 30, Filter, DINT#1, SubscribeStatus);
(* This is the library request entry, one scan after Main's TxRequest.
   Encode m1 here so local publisher waiting is never excluded from RTT. *)
PublishPulse:=PublishReq;
IF PublishPulse AND PlatformTime THEN
    IF TxKind=8 THEN
        TxSubmitMonoMs:=NowMs;
        TimePayload:=CONCAT('{"schemaVersion":1,"gatewayId":',NG_Quote(Bootstrap.GatewayId),',"requestId":',NG_Quote(TimeRequestId),',"bootId":',NG_Quote(BootId),',"sessionId":',NG_Quote(WillSession),',"clientMonoMs":',TO_STRING(TxSubmitMonoMs,'{0:d}'),'}');
        TimeCopy(REQ:=FALSE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(TimePayload),SRC:=TimePayload,BUFFER:=TxBuffer);
        TimeCopy(REQ:=TRUE,BUF_FORMAT:=FALSE,BUF_OFFS:=0,BUF_CNT:=LEN(TimePayload),SRC:=TimePayload,BUFFER:=TxBuffer);
        PublishPulse:=TimeCopy.DONE AND NG_ValidId(TimeRequestId) AND (NowMs<=ULINT#9007199254740991);
    ELSE
        TimePermit(Purpose:=USINT#3,TokenBootId:=TxBootId,CurrentBootId:=BootId,NowMs:=NowMs,TokenMonoMs:=SnapshotMonoMs,
            TokenClockRevision:=TxClockRevision,TokenConnectionRevision:=TxConnectionRevision,
            CurrentClockRevision:=ClockRevision,CurrentConnectionRevision:=ConnectionRevision,
            EnqueueAllowed:=FALSE,ControlAllowed:=ControlAllowed,SendAllowed:=SendAllowed,AckApplyAllowed:=Connected);
        PublishPulse:=TimePermit.Allowed;
        IF (TxKind=5) OR (TxKind=6) THEN PublishPulse:=PublishPulse AND SendAllowed; END_IF;
    END_IF;
    IF NOT PublishPulse THEN TxRejected:=TRUE; TxBusy:=FALSE; END_IF;
END_IF;
IF PublishPulse AND (TxKind=5) AND NOT SendAllowed THEN
    PublishPulse:=FALSE; TxRejected:=TRUE; TxBusy:=FALSE;
END_IF;
IF PublishPulse THEN TxInvoked:=TRUE; TxSubmitMonoMs:=NowMs; SubmittedKind:=TxKind; END_IF;
PublishLength:=TxLength;
IF PlatformTime AND (TxKind=8) THEN PublishLength:=TO_UDINT(LEN(TimePayload)); END_IF;
Client.Publish(PublishPulse,TxTopic,TxBuffer,PublishLength,DINT#1,TxRetain,PublishStatus);
IF PublishPulse THEN
    (* Busy proves the asynchronous method accepted the request. Done is also
       sufficient; no PUBACK is required to create the Busy submission fact. *)
    TxSubmitted:=NOT PublishStatus.xError AND (PublishStatus.xBusy OR PublishStatus.xDone);
    IF PublishStatus.xError THEN TxRejected:=TRUE; TxBusy:=FALSE; END_IF;
END_IF;
NewMessage := Client.TryConsumeMessage(ConsumeReq, RxTopic, RxBuffer, Info, ReceiveStatus);
ConnectedResult := Client.IsConnected(CheckReq, CheckStatus);
PublishReq := FALSE;
CASE State OF
5:
    IF Client.xError THEN ErrorText := 'MQTT_CLIENT_ERROR'; State := 900;
    ELSIF ReadyClient THEN State := 10;
    END_IF;
10: State := 11;
11:
    IF ConnectStatus.xError THEN ErrorText := 'MQTT_CONNECT_ERROR'; State := 900;
    ELSIF ConnectStatus.xDone THEN State := 20; END_IF;
20: State := 21;
21:
    IF ConsumeStatus.xError THEN ErrorText := 'MQTT_CONSUME_ERROR'; State := 900;
    ELSIF ConsumeStatus.xDone THEN SubscribeIndex := 1; State := 25; END_IF;
25:
    CASE SubscribeIndex OF
        1: Filter := CONCAT(Prefix,'config/set');
        2: Filter := CONCAT(Prefix,'config/patch');
        3: Filter := CONCAT(Prefix,'data/ack');
        4: Filter := CONCAT(Prefix,'time/response');
    END_CASE;
    State := 30;
30: State := 31;
31:
    IF SubscribeStatus.xError THEN ErrorText := 'MQTT_SUBSCRIBE_ERROR'; State := 900;
    ELSIF SubscribeStatus.xDone THEN
        IF (SubscribeIndex < 3) OR (PlatformTime AND (SubscribeIndex<4)) THEN SubscribeIndex := SubscribeIndex+1; State := 25;
        ELSE Connected := TRUE; ErrorText := ''; SessionCount := SessionCount+1; State := 100; END_IF;
    END_IF;
100:
    IF TxRequest AND NOT PrevTx AND NOT TxBusy THEN TxBusy := TRUE; PublishReq := TRUE; END_IF;
    IF TxBusy THEN
        IF PublishStatus.xDone THEN TxBusy := FALSE; TxDone := TRUE;
        ELSIF PublishStatus.xError THEN ErrorText := 'MQTT_PUBLISH_ERROR'; State := 900; END_IF;
    END_IF;
    IF NOT RxReady THEN
        IF ReceiveStatus.xDone THEN
            IF NewMessage THEN
                RxLength := Info.udiLength; RxRetained := Info.xRetained; RxReady := TRUE;
                (* Earliest ST-visible receive boundary. Queue/scan delay remains
                   inside complete request-to-dequeue RTT and asymmetry bound. *)
                RxReceivedMonoMs:=NowMs;
            END_IF;
            ConsumeReq := FALSE;
        ELSIF NOT ReceiveStatus.xBusy THEN ConsumeReq := NOT ConsumeReq; END_IF;
    ELSE ConsumeReq := FALSE;
    END_IF;
    IF ReceiveStatus.xError THEN
        (* Hub clears retained config/set with a zero-byte publication before a patch.
           IIoT 5.3 reports this as diagnostic 10 / Null message received. Keep
           consuming so the following patch is preserved; IsConnected still
           detects a real connection loss. All other receive errors reconnect. *)
        IF NOT ((ReceiveStatus.udtDiag.wDiagCode=WORD#10) AND
                (ReceiveStatus.udtDiag.strDiagMsg='Null message received')) THEN
            ErrorText := CONCAT('MQTT_RECEIVE_ERROR: ',ReceiveStatus.udtDiag.strDiagMsg); State := 900;
        END_IF;
    END_IF;
    IF CheckStatus.xDone THEN
        CheckReq := FALSE; LastCheck := NowMs;
        IF NOT ConnectedResult THEN ErrorText := 'MQTT_DISCONNECTED'; State := 900; END_IF;
    ELSIF (NowMs > LastCheck + 2000) AND NOT CheckStatus.xBusy THEN CheckReq := TRUE; END_IF;
900:
    Connected := FALSE; TxBusy := FALSE; ConsumeReq := FALSE; CheckReq := FALSE; PublishReq := FALSE;
    RetryAt := NowMs + 3000; State := 910;
910:
    IF NOT ReadyClient AND NOT Client.xBusy AND Enable AND NOT Reconnect AND (NowMs >= RetryAt) THEN State := 0; END_IF;
END_CASE;
IF (State > 0) AND (State < 100) AND (NowMs >= Deadline) THEN ErrorText := 'MQTT_TIMEOUT'; State := 900; END_IF;
PrevTx := TxRequest;
DebugState:=State;
END_FUNCTION_BLOCK
