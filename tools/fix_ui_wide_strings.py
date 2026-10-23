"""Engineer STRING is byte-based. Display-only WSTRING preserves Chinese text."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'src/NG_Types.dt';s=p.read_text(encoding='utf-8-sig')
s=s.replace('    NG_Hmi : STRUCT','    NG_UiLabel : WSTRING[256];\n    NG_Hmi : STRUCT')
s=re.sub(r'((?:Ui\w+|DeviceRow[1-8]|PointRow[1-8]|SelectedDevice|SelectedPoint)\s*:)\s*(?:NG_Text|STRING\[\d+\])',r'\1 NG_UiLabel',s)
p.write_text(s,encoding='utf-8')
p=ROOT/'tools/build_ui_strings.py';s=p.read_text(encoding='utf-8')
s=s.replace('def q(v):return "\'"+v.replace("\'","\'\'")+"\'"','def q(v):return "\'"+v.replace("\'","\'\'")+"\'"\ndef w(v):return chr(34)+v.replace(chr(34),\'$"\')+chr(34)')
s=s.replace("'FUNCTION NG_UiText : NG_Text'","'FUNCTION NG_UiText : NG_UiLabel'").replace("'NG_UiText:=Value;'","'NG_UiText:=TO_WSTRING(Value,\"\");'")
s=s.replace("q(zh)+';'","w(zh)+';'")
p.write_text(s,encoding='utf-8')
p=ROOT/'src/NG_HmiEdit.st';s=p.read_text(encoding='utf-8-sig').replace('rows : ARRAY[1..8] OF NG_Text','rows : ARRAY[1..8] OF NG_UiLabel')
start=s.index('        IF Hmi.English THEN\n            rows[row]')
end=s.index('\n        END_IF;',start)+len('\n        END_IF;')
s=s[:start]+'''        IF Hmi.English THEN
            rows[row]:=NG_UiJoin(TO_WSTRING(marker,""),TO_WSTRING(NG_Clip(device.name),"")," | ",NG_UiText(status,TRUE),"$N",TO_WSTRING(CONCAT(device.host,':',TO_STRING(device.port,'{0:d}')),""),TO_WSTRING(device.unitId," / Unit {0:d}"),TO_WSTRING(device.PointCount," / {0:d} points"));
        ELSE
            rows[row]:=NG_UiJoin(TO_WSTRING(marker,""),TO_WSTRING(NG_Clip(device.name),"")," | ",NG_UiText(status,FALSE),"$N",TO_WSTRING(CONCAT(device.host,':',TO_STRING(device.port,'{0:d}')),""),TO_WSTRING(device.unitId," / 站号 {0:d}"),TO_WSTRING(device.PointCount," / {0:d} 个点位"));
        END_IF;'''+s[end:]
s=s.replace('Hmi.SelectedDevice := Draft.Devices[d].name','Hmi.SelectedDevice := TO_WSTRING(Draft.Devices[d].name,"")')
start=s.index('            IF Hmi.English THEN\n                rows[row]');end=s.index('\n            END_IF;',start)+len('\n            END_IF;')
s=s[:start]+'''            rows[row]:=NG_UiJoin(TO_WSTRING(marker,""),NG_UiText(point.name,Hmi.English),"  |  ",TO_WSTRING(CONCAT(value,' ',point.unit),""),"  |  ",NG_UiText(status,Hmi.English),"$N",NG_UiText(point.area,Hmi.English));
            IF Hmi.English THEN
                rows[row]:=NG_UiJoin(rows[row],TO_WSTRING(point.address," @{0:d}"),TO_WSTRING(point.pollIntervalMs," / Poll {0:d}"),TO_WSTRING(point.reportIntervalMs," / Send {0:d} ms"),"","","","");
            ELSE
                rows[row]:=NG_UiJoin(rows[row],TO_WSTRING(point.address," @{0:d}"),TO_WSTRING(point.pollIntervalMs," / 采集 {0:d}"),TO_WSTRING(point.reportIntervalMs," / 上报 {0:d} 毫秒"),"","","","");
            END_IF;'''+s[end:]
p.write_text(s,encoding='utf-8')
p=ROOT/'src/Main.st';s=p.read_text(encoding='utf-8-sig')
s=s.replace("CONCAT('Saved to controller · generation ',TO_STRING(Durable.Generation,'{0:d}'),' · restored automatically after restart')",'NG_UiJoin("Saved to controller · generation ",TO_WSTRING(Durable.Generation,"{0:d}")," · restores automatically after restart","","","","","")')
s=s.replace("CONCAT('已保存到控制器 · 保存序号 ',TO_STRING(Durable.Generation,'{0:d}'),' · 重启后自动恢复')",'NG_UiJoin("已保存到控制器 · 保存序号 ",TO_WSTRING(Durable.Generation,"{0:d}")," · 重启后自动恢复","","","","","")')
s=s.replace("CONCAT('Connected · collecting ',HMI.TotalPoints,' points · waiting for storage ACK: ',HMI.QueueCount)",'NG_UiJoin("Connected · collecting ",TO_WSTRING(HMI.TotalPoints,"")," points · awaiting storage ACK: ",TO_WSTRING(HMI.QueueCount,""),"","","","")')
s=s.replace("CONCAT('已连接 · 正在采集 ',HMI.TotalPoints,' 个点位 · 待平台入库确认 ',HMI.QueueCount,' 批')",'NG_UiJoin("已连接 · 正在采集 ",TO_WSTRING(HMI.TotalPoints,"")," 个点位 · 待平台入库确认 ",TO_WSTRING(HMI.QueueCount,"")," 批","","","")')
p.write_text(s,encoding='utf-8')
