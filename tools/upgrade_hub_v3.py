"""One-time source migration to native-0.3.0. Does not download or contact PLC."""
from pathlib import Path
import re

root=Path(__file__).resolve().parents[1]

def edit(name, old, new, count=1):
    p=root/name; s=p.read_text(encoding='utf-8-sig')
    assert s.count(old)>=count, (name,old[:90])
    p.write_text(s.replace(old,new,count),encoding='utf-8')

types=(root/'src/NG_Types.dt').read_text(encoding='utf-8-sig')
assert 'NG2_Durable' not in types
legacy=re.search(r'    NG_Durable : STRUCT.*?    NG_Hmi : STRUCT',types,re.S).group(0).split('    NG_Hmi')[0]
legacy=legacy.replace('NG_Durable','NG2_Durable').replace('NG_File','NG2_File')
types=types.replace('        Text : NG_Text;', '        Text : STRING[512];')
types=types.replace('    NG_Durable : STRUCT\n        Generation : ULINT;', '    NG_Durable : STRUCT\n        Generation : ULINT;\n        Managed : BOOL := TRUE;\n        BootCounter : ULINT;')
types=types.replace('    NG_Hmi : STRUCT',legacy+'    NG_Hmi : STRUCT')
types=types.replace('        Navigation : STRING[16];','        Navigation : STRING[16];\n        ManagementMode : STRING[16] := \'HUB_MANAGED\';\n        ConfigSource : STRING[80];\n        BrokerGatewayId : NG_Id;\n        ActiveMessageId : NG_Id;\n        InvalidAcks : UDINT;\n        DeadBatches : STRING[12];')
types=types.replace('        LastSentMs : ULINT;','        LastSentMs : ULINT;\n        RetryAtMs : ULINT;\n        WasSent : BOOL;\n        Dead : BOOL;\n        LastError : NG_Text;')
(root/'src/NG_Types.dt').write_text(types,encoding='utf-8')
edit('src/NG_JsonParse.st','    Text : NG_Text;','    Text : STRING[512];')
edit('src/NG_JsonParse.st','LEN(Text) >= 256','LEN(Text) >= 512')
edit('src/NG_JsonParse.st','LEN(Text) > 256','LEN(Text) > 512',2)

p=root/'src/NG_Store.st'; s=p.read_text(encoding='utf-8-sig')
s=s.replace('    LegacyRecord : NG1_File;', '    LegacyRecord : NG1_File;\n    V2Record : NG2_File;\n    V2 : BOOL;')
s=s.replace("ELSE\n    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-v2-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-v2-B.bin'; END_IF;", "ELSIF V2 THEN\n    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-v2-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-v2-B.bin'; END_IF;\n    StateLength := SIZEOF(V2Record.State);\nELSE\n    IF Slot = 1 THEN Name := '/opt/plcnext/NativeGateway-v3-A.bin'; ELSE Name := '/opt/plcnext/NativeGateway-v3-B.bin'; END_IF;")
s=s.replace('ELSE\n    ReadFile(Execute := (Stage = 20)', 'ELSIF V2 THEN\n    ReadFile(Execute := Stage = 20, Handle := Handle, MaxLength := SIZEOF(V2Record), Buffer := V2Record);\nELSE\n    ReadFile(Execute := (Stage = 20)')
s=s.replace('ELSE\n    CopyBytes(REQ := (Stage = 35)', 'ELSIF V2 THEN\n    CopyBytes(REQ := Stage = 35, BUF_FORMAT := FALSE, BUF_OFFS := 0, BUF_CNT := StateLength, BUFFER := V2Record.State, DST := Bytes);\nELSE\n    CopyBytes(REQ := (Stage = 35)')
s=s.replace('ELSE Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(Record)) AND (Record.Magic = DWORD#16#4E475732) AND (Record.FormatVersion = 2); END_IF;', 'ELSIF V2 THEN Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(V2Record)) AND (V2Record.Magic = DWORD#16#4E475732) AND (V2Record.FormatVersion = 2);\n        ELSE Valid := ReadFile.Done AND (ReadFile.LengthRead = SIZEOF(Record)) AND (Record.Magic = DWORD#16#4E475733) AND (Record.FormatVersion = 3); END_IF;')
s=s.replace('Active.Generation := LegacyRecord.State.Generation;', 'Active.Managed := FALSE; Active.BootCounter := 0;\n                Active.Generation := LegacyRecord.State.Generation;')
s=s.replace("        ELSIF (Hash.Digest = Record.Digest)", "        ELSIF V2 THEN\n            IF (Hash.Digest = V2Record.Digest) AND (V2Record.State.Generation > Active.Generation) THEN\n                Active.Generation := V2Record.State.Generation; Active.Bootstrap := V2Record.State.Bootstrap;\n                Active.Config := V2Record.State.Config; Active.Requests := V2Record.State.Requests; Active.ReplayIndex := V2Record.State.ReplayIndex;\n                Active.Managed := FALSE; Active.BootCounter := 0; NeedsMigration := TRUE;\n            END_IF;\n        ELSIF (Hash.Digest = Record.Digest)",1)
s=s.replace("    ELSIF (Active.Generation = 0) AND NOT Legacy THEN Legacy := TRUE; Slot := 1; Stage := 10;", "    ELSIF (Active.Generation = 0) AND NOT Legacy AND NOT V2 THEN V2 := TRUE; Slot := 1; Stage := 10;\n    ELSIF (Active.Generation = 0) AND V2 THEN V2 := FALSE; Legacy := TRUE; Slot := 1; Stage := 10;")
s=s.replace('(Record.FormatVersion = 2)', '(Record.FormatVersion = 3)')
s=s.replace('        Legacy := FALSE;','        Legacy := FALSE; V2 := FALSE;')
s=s.replace('Record.Magic := DWORD#16#4E475732; Record.FormatVersion := 2;', 'Record.Magic := DWORD#16#4E475733; Record.FormatVersion := 3;')
p.write_text(s,encoding='utf-8')

edit('src/NG_HmiEdit.st','    Busy : BOOL;','    Busy : BOOL;\n    Managed : BOOL;')
edit('src/NG_HmiEdit.st','    NewBroker : NG_Bootstrap;','    NewBroker : NG_Bootstrap;\n    NewManaged : BOOL;')
edit('src/NG_HmiEdit.st',"Nav := Hmi.Navigation; Hmi.Navigation := '';", "Nav := Hmi.Navigation; Hmi.Navigation := '';\nIF Managed AND ((Nav='DEDIT') OR (Nav='PEDIT') OR (Nav='DNEW') OR (Nav='PNEW') OR (Nav='DDEL') OR (Nav='PDEL') OR (Nav='PERIOD') OR Hmi.SaveDevice OR Hmi.SavePoint OR Hmi.RemoveDevice OR Hmi.RemovePoint OR Hmi.Apply) THEN\n    Nav := ''; Hmi.SaveDevice:=FALSE; Hmi.SavePoint:=FALSE; Hmi.RemoveDevice:=FALSE; Hmi.RemovePoint:=FALSE; Hmi.Apply:=FALSE;\n    Hmi.View:=0; Hmi.Status:='HUB_MANAGED: publish device and point changes from Hub.';\nEND_IF;\nIF Managed THEN Hmi.ConfigSource:='HUB_MANAGED - local device/point changes blocked'; ELSE Hmi.ConfigSource:='STANDALONE - local maintenance enabled'; END_IF;")
edit('src/NG_HmiEdit.st',"IF NOT ValidBroker OR (LEN(Hmi.ClientId)=0)", "IF NOT ValidBroker OR NOT NG_ValidId(Hmi.BrokerGatewayId) OR ((Hmi.ManagementMode<>'HUB_MANAGED') AND (Hmi.ManagementMode<>'STANDALONE')) OR ((Managed<>(Hmi.ManagementMode='HUB_MANAGED')) AND (Hmi.BrokerGatewayId=Bootstrap.GatewayId)) OR (LEN(Hmi.ClientId)=0)")
edit('src/NG_HmiEdit.st',"Hmi.Status := 'Invalid broker URI, client ID or UTC offset.';", "Hmi.Status := 'Check broker/mode/ID. Mode change requires a new Gateway ID to isolate configuration history.';")
edit('src/NG_HmiEdit.st', 'NewBroker := Bootstrap; NewBroker.BrokerUri', "NewManaged := Hmi.ManagementMode='HUB_MANAGED'; NewBroker := Bootstrap; NewBroker.GatewayId:=Hmi.BrokerGatewayId; NewBroker.BrokerUri")
edit('src/NG_Command.st',"FOR i := 1 TO count DO IF seen[i] = id THEN RETURN; END_IF; END_FOR;", "FOR i := 1 TO count DO IF seen[i] = id THEN ErrorCode := 'OPERATION_CONFLICT'; RETURN; END_IF; END_FOR;")
edit('src/NG_Command.st',"IF NewDevice.deviceId <> id THEN RETURN; END_IF;", "IF NewDevice.deviceId <> id THEN ErrorCode := 'OPERATION_CONFLICT'; RETURN; END_IF;")

p=root/'src/Main.st'; s=p.read_text(encoding='utf-8-sig')
s=s.replace('    Initialized : BOOL;', '''    Initialized : BOOL;
    StartupReady : BOOL;
    StartupStage : INT;
    BootHash : NG_SHA256;
    BootNamespace : STRING[24];
    IdentityChanged : BOOL;
    BlankConfig : NG_Config;
    EmptyPacket : NG_Packet;
    AckReader : NG_ReadAck;
    WireError : NG_Text;
    DeviceEventPending : BOOL;
    DeviceEventIndex : INT;
    DeviceEventSignature : NG_Text;
    DeviceSignatures : ARRAY[1..50] OF NG_Text;
    EnabledPoints : INT;
    DeadCount : INT;''')
start=s.index('IF Store.Ready AND NOT Initialized THEN')
end=s.index('IF NOT Initialized THEN RETURN; END_IF;',start)
s=s[:start]+'''IF Store.Ready AND NOT Initialized THEN
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
''' +s[end:]
s=s.replace("    ELSIF SaveReason = 3 THEN Reconnect := TRUE; HMI.Status := 'Broker settings saved; reconnecting.';", '''    ELSIF SaveReason = 3 THEN
        IF IdentityChanged THEN
            Initialized:=FALSE; StartupReady:=FALSE; StartupStage:=0; ResetMeters:=TRUE;
            QueueCount:=0; Head:=1; Tail:=1; Sequence:=0; SessionSeen:=0; BatchSweep:=FALSE;
            FOR q:=1 TO 16 DO Outbox[q]:=EmptyPacket; END_FOR;
            FOR p:=1 TO 320 DO Samples[p]:=EmptySample; END_FOR;
            IdentityChanged:=FALSE;
        END_IF;
        Reconnect:=TRUE; HMI.Status:='Broker/mode saved; identity changes reset local baseline.';
    ELSIF SaveReason = 5 THEN
        BootId:=CONCAT('ng-',BootNamespace,'-',TO_STRING(Durable.BootCounter,'{0:d}'));
        SessionId:=BootId; StartupReady:=TRUE; StartupStage:=4; HMI.Status:='Startup identity persisted; MQTT starting.';''')
pos=s.index("Header := CONCAT(")
s=s[:pos]+'''BootHash(Execute:=StartupStage=2,Length:=TO_UDINT(LEN(Bootstrap.GatewayId)),Buffer:=Tx);
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
''' +s[pos:]
start=s.index("            IF NG_Allowed(1,'|schemaVersion|gatewayId|timestamp|messageId|status|errors|',Doc)")
end=s.index('            RxAccept := TRUE; RxStage := 0;',start)
s=s[:start]+'''            AckReader(GatewayId:=Bootstrap.GatewayId,Doc:=Doc);
            IF AckReader.Valid THEN
                FOR q:=1 TO 16 DO
                    IF (Outbox[q].MessageId=AckReader.MessageId) AND Outbox[q].WasSent AND NOT Outbox[q].Dead THEN
                        IF AckReader.Stored THEN
                            Outbox[q]:=EmptyPacket; QueueCount:=QueueCount-1; HMI.ConfirmedBatches:=HMI.ConfirmedBatches+1;
                        ELSIF AckReader.Retryable THEN
                            Outbox[q].RetryAtMs:=NowMs+60000; Outbox[q].LastError:=AckReader.Codes;
                            HMI.ConfigResult:=CONCAT('RETRY data/ack: ',AckReader.Codes);
                        ELSE
                            Outbox[q].Dead:=TRUE; Outbox[q].LastError:=AckReader.Codes;
                            HMI.ConfigResult:=CONCAT('DEAD data/ack: ',AckReader.Codes);
                        END_IF;
                        EXIT;
                    END_IF;
                END_FOR;
            ELSE HMI.InvalidAcks:=HMI.InvalidAcks+1; HMI.ConfigResult:='Invalid data/ack ignored.';
            END_IF;
''' +s[end:]
s=s.replace("IF ErrorCode <> '' THEN AckPayload := CONCAT(AckPayload,'{\"code\":',NG_Quote(ErrorCode)", "IF ErrorCode <> '' THEN WireError:=NG_WireCode(ErrorCode,IsPatch); AckPayload := CONCAT(AckPayload,'{\"code\":',NG_Quote(WireError)")
s=s.replace('Editor(Busy :=', 'Editor(Managed:=Durable.Managed, Busy :=')
s=s.replace('IF Editor.Submit AND (SaveReason = 0) THEN', 'IF Editor.Submit AND NOT Durable.Managed AND (SaveReason = 0) THEN')
s=s.replace('ELSIF Editor.SubmitBroker AND (SaveReason = 0) THEN Pending := Durable; Pending.Bootstrap := Editor.NewBroker; Save := TRUE; SaveReason := 3;', '''ELSIF Editor.SubmitBroker AND (SaveReason = 0) THEN
    Pending:=Durable; Pending.Bootstrap:=Editor.NewBroker; Pending.Managed:=Editor.NewManaged;
    IdentityChanged:=Pending.Bootstrap.GatewayId<>Bootstrap.GatewayId;
    IF IdentityChanged THEN
        Pending.Config:=BlankConfig; Pending.Config.batchIntervalMs:=1000; Pending.Config.maxBatchPoints:=32;
        Pending.ReplayIndex:=0; FOR i:=1 TO 32 DO Pending.Requests[i].MessageId:=''; END_FOR;
    END_IF;
    Save:=TRUE; SaveReason:=3;''')
s=s.replace("CONCAT('data-',BootId", "CONCAT('d-',BootId")
s=s.replace("1: AckPending := FALSE;", "1: AckPending := FALSE; GetPending:=TRUE;")
s=s.replace('5: Outbox[Head].LastSentMs := NowMs;', '5: Outbox[Head].LastSentMs := NowMs; Outbox[Head].WasSent:=TRUE;')
s=s.replace('6: ResourcesPending := FALSE;', '6: ResourcesPending := FALSE;\n            7: DeviceSignatures[DeviceEventIndex]:=DeviceEventSignature;')
s=s.replace('    ELSIF ResourcesPending THEN', '''    ELSIF DeviceEventPending THEN
        TxKind:=7; TxTopic:=CONCAT(Prefix,'device/status');
        TxPayload:=CONCAT(Header,',"sessionId":',NG_Quote(SessionId),',"configVersion":',TO_STRING(Active.Version,'{0:d}'),',"device":',DevicesJson,'}');
    ELSIF ResourcesPending THEN''')
s=s.replace("IF Outbox[Head].MessageId<>'' THEN", "IF (Outbox[Head].MessageId<>'') AND NOT Outbox[Head].Dead THEN")
s=s.replace("IF Outbox[Head].MessageId = '' THEN", "IF (Outbox[Head].MessageId = '') OR Outbox[Head].Dead THEN")
s=s.replace('(Outbox[Head].LastSentMs=0) OR (NowMs>=Outbox[Head].LastSentMs+5000)', '(NowMs>=Outbox[Head].RetryAtMs) AND NOT Outbox[Head].Dead AND ((Outbox[Head].LastSentMs=0) OR (NowMs>=Outbox[Head].LastSentMs+5000))')
s=s.replace('Bootstrap := Bootstrap, TxRequest', 'Bootstrap := Bootstrap, BootId:=BootId, TxRequest')
s=s.replace('native-0.2.0','native-0.3.0')
# Match source spelling if the final call has a newline between arguments.
s=s.replace('Mqtt(Enable := TRUE, Reconnect := Reconnect, NowMs := NowMs, Bootstrap := Bootstrap,', 'Mqtt(Enable := TRUE, Reconnect := Reconnect, NowMs := NowMs, Bootstrap := Bootstrap, BootId:=BootId,')
s=s.replace("HMI.ActiveVersion :=", "HMI.ActiveMessageId:=Active.MessageId;\nHMI.ActiveVersion :=")
# Device changes are emitted after the first heartbeat establishes the Hub session.
anchor='IF NOT TxActive AND Mqtt.Connected AND NOT Mqtt.TxBusy THEN'
insertion='''DeviceEventPending:=FALSE;
IF (Active.Version>0) AND NOT HeartbeatPending THEN
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
'''
s=s.replace(anchor,insertion+anchor)
# A disabled/no-point device must not appear as CONNECTING in heartbeat.
s=s.replace("Status := Meters[d].StateText; IF NOT Active.enabled OR NOT Active.Devices[d].enabled THEN Status := 'DISABLED'; END_IF;", "Status:=Meters[d].StateText; EnabledPoints:=0;\n            FOR p:=1 TO Active.Devices[d].PointCount DO IF Active.Points[Active.Devices[d].PointStart+p-1].enabled THEN EnabledPoints:=EnabledPoints+1; END_IF; END_FOR;\n            IF NOT Active.enabled OR NOT Active.Devices[d].enabled OR (EnabledPoints=0) THEN Status:='DISABLED'; END_IF;")
s=s.replace("            DevicesJson := CONCAT(DevicesJson", "            IF Status='DISABLED' THEN LastErrorJson:='null'; LastGoodJson:='null'; END_IF;\n            DevicesJson := CONCAT(DevicesJson")
p.write_text(s,encoding='utf-8')

edit('src/NG_Mqtt.st','    Enable : BOOL;', '    Enable : BOOL;\n    BootId : NG_Id;')
edit('src/NG_Mqtt.st', '    PrevTx : BOOL;', '    PrevTx : BOOL;\n    WillSession : NG_Id;')
edit('src/NG_Mqtt.st', '    Options.xUseWillOptions := FALSE;', '''    WillSession:=CONCAT(BootId,'-',TO_STRING(SessionCount+1,'{0:d}'));
    Options.xUseWillOptions:=TRUE;
    Options.udtWill.strTopic:=CONCAT(Prefix,'status');
    Options.udtWill.strPayload:=CONCAT('{"schemaVersion":1,"gatewayId":',NG_Quote(Bootstrap.GatewayId),',"timestamp":null,"sessionId":',NG_Quote(WillSession),',"online":false,"reason":"connection_lost"}');
    Options.udtWill.diQos:=1; Options.udtWill.xRetained:=TRUE;''')
print('Migrated sources to v3 / native-0.3.0; compile and runtime verification still required.')
