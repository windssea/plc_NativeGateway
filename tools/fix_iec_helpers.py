from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]/'src'
for name in ('NG_Member','NG_Allowed','NG_CheckConfig'):
    p=root/(name+'.st');s=p.read_text(encoding='utf-8-sig').replace('VAR_IN_OUT','VAR_INPUT');p.write_text(s,encoding='utf-8')
for name in ('NG_ReadPoint','NG_ReadDevice','NG_ReadConfig'):
    p=root/(name+'.st');s=p.read_text(encoding='utf-8-sig')
    s=s.replace('FUNCTION '+name+' : NG_Text','FUNCTION_BLOCK '+name)
    s=s.replace('END_FUNCTION','END_FUNCTION_BLOCK')
    s=re.sub(r'\b'+name+r'\s*:=','ErrorText :=',s)
    at=s.index('\nVAR\n');s=s[:at]+'\nVAR_OUTPUT\n    ErrorText : NG_Text;\nEND_VAR'+s[at:]
    p.write_text(s,encoding='utf-8')
for p in root.glob('*.st'):
    s=p.read_text(encoding='utf-8-sig');instances=[]
    for name,param in [('NG_ReadPoint','Point'),('NG_ReadDevice','Device'),('NG_ReadConfig','Config')]:
        pattern=r'(?m)^(\s*)(\w+) := '+name+r'\(([^,\n]+),Doc,([^\n]+)\);'
        def replace(m):
            instance='Read'+param
            instances.append((instance,name))
            return f'{m[1]}{instance}(Node := {m[3]}, Doc := Doc, {param} := {m[4]});\n{m[1]}{m[2]} := {instance}.ErrorText;'
        s=re.sub(pattern,replace,s)
    if instances:
        s=s.replace('\nVAR\n','\nVAR\n'+''.join(f'    {instance} : {name};\n' for instance,name in sorted(set(instances))),1)
    p.write_text(s,encoding='utf-8')
p=root/'NG_Types.dt';s=p.read_text(encoding='utf-8-sig').replace('TYPE\n','TYPE\n    NG_Quoted : STRING[520];\n',1);p.write_text(s,encoding='utf-8')
p=root/'NG_Quote.st';s=p.read_text(encoding='utf-8-sig').replace('STRING[520]','NG_Quoted').replace('c = NG_Char(10)',"c = '\\n'").replace('c = NG_Char(13)','GET_CHAR(c,0) = BYTE#13').replace('c = NG_Char(9)',"c = '\\t'");p.write_text(s,encoding='utf-8')
