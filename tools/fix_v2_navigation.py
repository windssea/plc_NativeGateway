from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
navs=['LIST','MQTT','DEDIT','PEDIT','DPREV','DNEXT','PPREV','PNEXT','DDEL','PDEL','CANCEL','DNEW','PNEW','PERIOD']+[f'D{i}' for i in range(1,9)]+[f'P{i}' for i in range(1,9)]
p=root/'tools/build_hmi_v2.py';s=p.read_text(encoding='utf-8');s=s.replace("SourceConstant\':\"\'\"+nav+\"\'\" if nav else \'TRUE\'", "SourceConstant':str(NAVS.index(nav)+1) if nav else 'TRUE'")
s=s.replace("def build():",'NAVS='+repr(navs)+'\n\ndef build():');p.write_text(s,encoding='utf-8')
p=root/'tools/build_native.py';s=p.read_text(encoding='utf-8').replace('GW_Nav : STRING[16]','GW_Nav : INT').replace("role.find(field).text='STRING[16]'","role.find(field).text='INT'").replace('role.find(\'InitValue\').text="\'\'"',"role.find('InitValue').text='0'");p.write_text(s,encoding='utf-8')
p=root/'src/Main.st';s=p.read_text(encoding='utf-8').replace('GW_Nav : STRING[16]','GW_Nav : INT')
s=s.replace("IF GW_Nav <> '' THEN HMI.Navigation := GW_Nav; GW_Nav := ''; END_IF;",'CASE GW_Nav OF\n'+'\n'.join(f"{i+1}: HMI.Navigation := '{n}';" for i,n in enumerate(navs))+"\nEND_CASE; GW_Nav := 0;")
s=s.replace('Resources(NowMs := NowMs);','// Resources are sampled by the independent IDeviceStatusService test recorder.')
s=re.sub(r'IF Resources.MemoryValid AND Resources.CpuValid THEN.*?END_IF;',"HMI.ResourceStatus := 'CPU / RAM / IEC memory: controller status recorder, 10 s interval.';",s,flags=re.S)
p.write_text(s,encoding='utf-8')
p=root/'src/NG_Resources.st';s=p.read_text(encoding='utf-8');s=re.sub(r'\bFailed\b','ProcFailed',s);p.write_text(s,encoding='utf-8')
