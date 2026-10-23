"""One-time migration from the backed-up v1 sources to a shared 320-point pool."""
from pathlib import Path
import re
R=Path(__file__).resolve().parents[1]/'src'
def edit(name,fn):
    p=R/(name+'.st');p.write_text(fn(p.read_text()),encoding='utf-8')
edit('NG_ReadDevice',lambda s:s.replace('    Device : NG_Device;','    Device : NG_Device;\n    Points : ARRAY[1..32] OF NG_Point;').replace('Device.Points[Device.PointCount]','Points[Device.PointCount]'))
def readconfig(s):
    s=s.replace('    ReadDevice : NG_ReadDevice;','    ReadDevice : NG_ReadDevice;\n    Change : NG_EditDevice;\n    Device : NG_Device;\n    Points : ARRAY[1..32] OF NG_Point;')
    s=s.replace('Config.DeviceCount := 0;','Config.DeviceCount := 0; Config.PointCount := 0;')
    s=s.replace('Config.DeviceCount >= 8','Config.DeviceCount >= 50')
    s=s.replace('    Config.DeviceCount := Config.DeviceCount + 1;\n','')
    s=s.replace('Device := Config.Devices[Config.DeviceCount]','Device := Device, Points := Points')
    s=s.replace('    d := Doc.Tokens[d].NextToken;','    Change(DeviceIndex := Config.DeviceCount+1, Remove := FALSE, Replacement := Device, Config := Config, Points := Points);\n    IF Change.ErrorText <> \'\' THEN ErrorText := Change.ErrorText; RETURN; END_IF;\n    d := Doc.Tokens[d].NextToken;')
    return s
edit('NG_ReadConfig',readconfig)
def check(s):
    s=s.replace('Config.DeviceCount > 8','Config.DeviceCount > 50')
    s=s.replace('point := Config.Devices[d].Points[p]','point := Config.Points[Config.Devices[d].PointStart+p-1]')
    s=s.replace('Config.Devices[d].Points[i].pointId','Config.Points[Config.Devices[d].PointStart+i-1].pointId')
    s=s.replace("NG_CheckConfig := 'SCHEMA_INVALID';","NG_CheckConfig := 'SCHEMA_INVALID';\nIF (Config.PointCount < 0) OR (Config.PointCount > 320) THEN RETURN; END_IF;")
    return s
edit('NG_CheckConfig',check)
def command(s):
    s=s.replace('    ReadDevice : NG_ReadDevice;','    ReadDevice : NG_ReadDevice;\n    Change : NG_EditDevice;\n    NewDevice : NG_Device;\n    NewPoints : ARRAY[1..32] OF NG_Point;')
    s=s.replace('ARRAY[1..8]','ARRAY[1..50]').replace('count >= 8','count >= 50').replace('Candidate.DeviceCount >= 8','Candidate.DeviceCount >= 50')
    s=s.replace('Candidate.DeviceCount := Candidate.DeviceCount+1; d := Candidate.DeviceCount;','d := Candidate.DeviceCount+1;')
    s=s.replace('            FOR i := d TO Candidate.DeviceCount-1 DO Candidate.Devices[i] := Candidate.Devices[i+1]; END_FOR;\n            Candidate.DeviceCount := Candidate.DeviceCount-1;',"            Change(DeviceIndex := d, Remove := TRUE, Replacement := NewDevice, Config := Candidate, Points := NewPoints);\n            IF Change.ErrorText <> '' THEN ErrorCode := Change.ErrorText; RETURN; END_IF;")
    s=s.replace('Device := Candidate.Devices[d]','Device := NewDevice, Points := NewPoints')
    s=s.replace('IF Candidate.Devices[d].deviceId <> id','IF NewDevice.deviceId <> id')
    s=s.replace('        op := Doc.Tokens[op].NextToken;',"        IF mode <> 'remove' THEN\n            Change(DeviceIndex := d, Remove := FALSE, Replacement := NewDevice, Config := Candidate, Points := NewPoints);\n            IF Change.ErrorText <> '' THEN ErrorCode := Change.ErrorText; RETURN; END_IF;\n        END_IF;\n        op := Doc.Tokens[op].NextToken;")
    return s
edit('NG_Command',command)
def modbus(s):
    s=s.replace('    Samples : ARRAY[1..32] OF NG_Sample;','    Points : ARRAY[1..320] OF NG_Point;\n    Samples : ARRAY[1..320] OF NG_Sample;')
    s=re.sub(r'Device\.Points\[([^\]]+)\]',r'Points[Device.PointStart+\1-1]',s)
    s=re.sub(r'Samples\[([^\]]+)\]',r'Samples[Device.PointStart+\1-1]',s)
    return s
edit('NG_Modbus',modbus)
def main(s):
    s=s.replace('    Meters : ARRAY[1..8] OF NG_MeterState;','    Meters : ARRAY[1..50] OF NG_MeterState;\n    Samples : ARRAY[1..320] OF NG_Sample;')
    s=re.sub(r'    Meter[1-8] : NG_Modbus;\n','',s)
    s=s.replace('    Editor : NG_HmiEdit;',''.join(f'    Meter{i} : NG_Modbus;\n' for i in range(1,51))+'\n    Editor : NG_HmiEdit;')
    s=s.replace('FOR d := 1 TO 8 DO FOR p := 1 TO 32 DO Meters[d].Samples[p] := EmptySample; END_FOR; END_FOR;','FOR p := 1 TO 320 DO Samples[p] := EmptySample; END_FOR;')
    calls='\n'.join(f'Meter{i}(Enable := ({i} <= Active.DeviceCount) AND Active.enabled, Reset := ResetMeters, NowMs := NowMs, UnixMs := UnixMs, Device := Active.Devices[{i}], Points := Active.Points, Samples := Samples, StateText => Meters[{i}].StateText, LastError => Meters[{i}].LastError, LastGoodTimestamp => Meters[{i}].LastGoodTimestamp, Completed => Meters[{i}].Completed);' for i in range(1,51))
    s=re.sub(r'Meter1\(Enable :=.*?Meter8\(Enable :=[^\n]+',calls,s,flags=re.S)
    s=re.sub(r'Active\.Devices\[d\]\.Points\[p\]',r'Active.Points[Active.Devices[d].PointStart+p-1]',s)
    s=re.sub(r'Meters\[d\]\.Samples\[p\]',r'Samples[Active.Devices[d].PointStart+p-1]',s)
    s=s.replace('NG_Range(HMI.DeviceIndex,1,8,TRUE)','NG_Range(HMI.DeviceIndex,1,50,TRUE)')
    s=s.replace('Ready. Capacity: 8 devices, 32 points per device.','Ready: 50 devices, 320 shared points, 32 points/device.')
    s=s.replace('native-0.1.2','native-0.2.0')
    return s
edit('Main',main)
print('Migrated read/config/command/Modbus/Main sources to shared point pool.')
