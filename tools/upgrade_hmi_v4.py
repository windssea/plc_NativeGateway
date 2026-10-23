"""One-time UI-only migration; durable and MQTT data structures stay unchanged."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'src/NG_HmiEdit.st';s=p.read_text(encoding='utf-8-sig')
s=s.replace("Nav := Hmi.Navigation; Hmi.Navigation := '';", """Nav := Hmi.Navigation; Hmi.Navigation := '';
IF Nav='ZH' THEN Hmi.English:=FALSE;
ELSIF Nav='EN' THEN Hmi.English:=TRUE;
ELSIF Nav='REFRESH' THEN IF Dirty THEN Hmi.View:=5; ELSE Hmi.Load:=TRUE; END_IF;
ELSIF Nav='DISCARD' THEN Hmi.Load:=TRUE; Hmi.View:=0;
ELSIF Nav='REVIEW' THEN Hmi.View:=6;
ELSIF Nav='COMMIT' THEN Hmi.Apply:=TRUE;
ELSIF Nav='DEVON' THEN Hmi.DeviceEnabled:='true';
ELSIF Nav='DEVOFF' THEN Hmi.DeviceEnabled:='false';
ELSIF Nav='POINTON' THEN Hmi.PointEnabled:='true';
ELSIF Nav='POINTOFF' THEN Hmi.PointEnabled:='false';
ELSIF Nav='MODEHUB' THEN Hmi.ManagementMode:='HUB_MANAGED';
ELSIF Nav='MODELOCAL' THEN Hmi.ManagementMode:='STANDALONE';
ELSIF Nav='CYCLIC' THEN Hmi.ReportMode:='cyclic';
ELSIF Nav='CHANGE' THEN Hmi.ReportMode:='change';
ELSIF Nav='BOTH' THEN Hmi.ReportMode:='change_or_cyclic';
ELSIF Nav='HOLDING' THEN Hmi.Area:='holding_register';
ELSIF Nav='INPUT' THEN Hmi.Area:='input_register';
ELSIF Nav='COIL' THEN Hmi.Area:='coil';
ELSIF Nav='DISCRETE' THEN Hmi.Area:='discrete_input';
ELSIF Nav='UINT16' THEN Hmi.DataType:='uint16'; Hmi.ByteOrder:='AB';
ELSIF Nav='INT16' THEN Hmi.DataType:='int16'; Hmi.ByteOrder:='AB';
ELSIF Nav='UINT32' THEN Hmi.DataType:='uint32'; Hmi.ByteOrder:='ABCD';
ELSIF Nav='INT32' THEN Hmi.DataType:='int32'; Hmi.ByteOrder:='ABCD';
ELSIF Nav='FLOAT32' THEN Hmi.DataType:='float32'; Hmi.ByteOrder:='ABCD';
ELSIF Nav='BOOL' THEN Hmi.DataType:='bool'; Hmi.ByteOrder:=''; Hmi.Scale:='1'; Hmi.Offset:='0'; Hmi.Deadband:='0';
ELSIF Nav='ADVANCED' THEN Hmi.Advanced:=NOT Hmi.Advanced;
ELSIF Nav='BROKERREVIEW' THEN Hmi.View:=7;
ELSIF Nav='BROKERCOMMIT' THEN Hmi.SaveBroker:=TRUE;
END_IF;""")
s=s.replace("IF Hmi.Load AND NOT Busy THEN Reload := TRUE; Hmi.Status := 'Loaded persisted active configuration.'; END_IF;", "IF Hmi.Load AND NOT Busy THEN Reload := TRUE; Hmi.View:=0; Hmi.Status := 'Display refreshed from active configuration. Unapplied draft discarded.'; END_IF;")
s=s.replace("IF Dirty THEN Hmi.DraftState", "Hmi.UiStatus:=NG_UiText(Hmi.Status,Hmi.English);\nHmi.UiDeviceEnabled:=NG_UiText(Hmi.DeviceEnabled,Hmi.English); Hmi.UiPointEnabled:=NG_UiText(Hmi.PointEnabled,Hmi.English);\nHmi.UiArea:=NG_UiText(Hmi.Area,Hmi.English); Hmi.UiReportMode:=NG_UiText(Hmi.ReportMode,Hmi.English); Hmi.UiManagementMode:=NG_UiText(Hmi.ManagementMode,Hmi.English);\nIF Dirty THEN Hmi.DraftState")
s=s.replace("Hmi.TotalPoints :=", "Hmi.UiDraftState:=NG_UiText(Hmi.DraftState,Hmi.English);\nHmi.UiConfigSource:=NG_UiText(Hmi.ConfigSource,Hmi.English);\nHmi.TotalPoints :=")
s=s.replace("rows[row] := CONCAT(marker,NG_Clip(device.deviceId),' | ',TO_STRING(device.PointCount,'{0:d}'),' points | ',status,'\\n',device.host,':',TO_STRING(device.port,'{0:d}'),' / Unit ',TO_STRING(device.unitId,'{0:d}'),' / ',NG_Clip(device.name));", """IF Hmi.English THEN
            rows[row] := CONCAT(marker,NG_Clip(device.name),' | ',NG_UiText(status,TRUE),'\\n',device.host,':',TO_STRING(device.port,'{0:d}'),'  /  Unit ',TO_STRING(device.unitId,'{0:d}'),'  /  ',TO_STRING(device.PointCount,'{0:d}'),' points');
        ELSE
            rows[row] := CONCAT(marker,NG_Clip(device.name),' | ',NG_UiText(status,FALSE),'\\n',device.host,':',TO_STRING(device.port,'{0:d}'),'  /  站号 ',TO_STRING(device.unitId,'{0:d}'),'  /  ',TO_STRING(device.PointCount,'{0:d}'),' 个点位');
        END_IF;""")
s=s.replace("Hmi.SelectedDevice := 'No device selected'; Hmi.SelectedPoint := 'No point selected';", "Hmi.SelectedDevice := NG_UiText('No device selected',Hmi.English); Hmi.SelectedPoint := NG_UiText('No point selected',Hmi.English);")
s=s.replace("CONCAT(Draft.Devices[d].deviceId,' / ',Draft.Devices[d].name)","Draft.Devices[d].name")
s=s.replace("CONCAT(point.pointId,' / ',point.name)","NG_UiText(point.name,Hmi.English)")
s=s.replace("rows[row] := CONCAT(marker,NG_Clip(point.pointId),' | ',point.dataType,' | ',status,' | ',value,' ',point.unit,'\\n',point.area,' @',TO_STRING(point.address,'{0:d}'),' | poll ',TO_STRING(point.pollIntervalMs,'{0:d}'),' / report ',TO_STRING(point.reportIntervalMs,'{0:d}'),' ms');", """IF Hmi.English THEN
                rows[row] := CONCAT(marker,NG_UiText(point.name,TRUE),'  |  ',value,' ',point.unit,'  |  ',NG_UiText(status,TRUE),'\\n',NG_UiText(point.area,TRUE),' @',TO_STRING(point.address,'{0:d}'),'  /  Poll ',TO_STRING(point.pollIntervalMs,'{0:d}'),' / Send ',TO_STRING(point.reportIntervalMs,'{0:d}'),' ms');
            ELSE
                rows[row] := CONCAT(marker,NG_UiText(point.name,FALSE),'  |  ',value,' ',point.unit,'  |  ',NG_UiText(status,FALSE),'\\n',NG_UiText(point.area,FALSE),' @',TO_STRING(point.address,'{0:d}'),'  /  采集 ',TO_STRING(point.pollIntervalMs,'{0:d}'),' / 上报 ',TO_STRING(point.reportIntervalMs,'{0:d}'),' 毫秒');
            END_IF;""")
p.write_text(s,encoding='utf-8')
p=ROOT/'src/Main.st';s=p.read_text(encoding='utf-8-sig').replace('native-0.3.1','native-0.4.0')
navs=['ZH','EN','REFRESH','DISCARD','REVIEW','COMMIT','DEVON','DEVOFF','POINTON','POINTOFF','MODEHUB','MODELOCAL','CYCLIC','CHANGE','BOTH','HOLDING','INPUT','COIL','DISCRETE','UINT16','INT16','UINT32','INT32','FLOAT32','BOOL','ADVANCED','BROKERREVIEW','BROKERCOMMIT']
s=s.replace('END_CASE; GW_Nav := 0;', '\n'.join(f"{i}: HMI.Navigation := '{n}';" for i,n in enumerate(navs,31))+'\nEND_CASE; GW_Nav := 0;')
s=s.replace('END_PROGRAM',"""HMI.UiStatus:=NG_UiText(HMI.Status,HMI.English);
HMI.UiConnection:=NG_UiText(HMI.Connection,HMI.English);
HMI.UiQuality:=NG_UiText(HMI.LastQuality,HMI.English);
IF Store.Busy THEN HMI.UiPersistence:=NG_UiText('Saving / validating durable file...',HMI.English);
ELSIF Store.Error THEN HMI.UiPersistence:=NG_UiText('STORAGE ERROR: configuration not committed.',HMI.English);
ELSIF HMI.English THEN HMI.UiPersistence:=CONCAT('Saved to controller · generation ',TO_STRING(Durable.Generation,'{0:d}'),' · restored automatically after restart');
ELSE HMI.UiPersistence:=CONCAT('已保存到控制器 · 保存序号 ',TO_STRING(Durable.Generation,'{0:d}'),' · 重启后自动恢复'); END_IF;
IF NOT StartupReady THEN HMI.UiLiveStatus:=NG_UiText('Restoring saved configuration...',HMI.English);
ELSIF NOT Mqtt.Connected THEN HMI.UiLiveStatus:=NG_UiText('Broker unavailable. Retrying automatically; local acquisition continues.',HMI.English);
ELSIF HMI.English THEN HMI.UiLiveStatus:=CONCAT('Connected · collecting ',HMI.TotalPoints,' points · waiting for storage ACK: ',HMI.QueueCount);
ELSE HMI.UiLiveStatus:=CONCAT('已连接 · 正在采集 ',HMI.TotalPoints,' 个点位 · 待平台入库确认 ',HMI.QueueCount,' 批'); END_IF;
END_PROGRAM""")
p.write_text(s,encoding='utf-8')
print('UI state and navigation upgraded; durable layout unchanged')
