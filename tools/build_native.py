"""Package editable IEC source files into the saved Engineer project.

No PLC download or network activity. The original project is kept in reference/.
Source edits are reapplied from src/, so the resulting archive stays reproducible.
"""
from pathlib import Path
import re
import uuid
import zipfile
import copy
import xml.etree.ElementTree as E

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / 'reference/NativeGateway.before-implementation.pcwex'
NS = 'http://schemas.microsoft.com/developer/msbuild/2003'
E.register_namespace('', NS)
def uid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, 'nativegateway/' + name))
def tag(name):
    return '{' + NS + '}' + name

def build():
    with zipfile.ZipFile(BASE) as z:
        files = {n:z.read(n) for n in z.namelist()}
    proj = E.fromstring(files['PROJECT/PROJECT.proj'])
    # Preserve the genuine user-supplied brand image imported by Engineer.
    with zipfile.ZipFile(ROOT/'reference/NativeGateway.logo-import.pcwex') as logo_archive:
        logo_project=E.fromstring(logo_archive.read('PROJECT/PROJECT.proj'))
        assets=E.SubElement(proj,tag('ItemGroup'))
        for asset in logo_project.iter():
            if asset.tag in (tag('Image'),tag('ImageSource'),tag('ImageThumbnail')) and 'codex-clipboard-2b444731' in asset.get('Include',''):
                brand=copy.deepcopy(asset)
                if brand.tag==tag('Image'):
                    brand.find(tag('DisplayName')).text='Phoenix Contact Logo'
                    brand.find(tag('ImageWidth')).text='95'
                    brand.find(tag('ImageHeight')).text='30'
                assets.append(brand)
    group = E.SubElement(proj, tag('ItemGroup'))
    def item(kind, path, **props):
        el = E.SubElement(group,tag(kind),Include=path)
        E.SubElement(el,tag('Id')).text = uid(kind+path)
        for k,v in props.items(): E.SubElement(el,tag(k)).text = str(v)
        return el
    for p in sorted((ROOT/'src').glob('*.dt')):
        dest = 'Logical Elements\\'+p.name
        files['PROJECT/'+dest.replace('Logical Elements','Logical%20Elements').replace('\\','/')] = p.read_bytes()
        item('DataTypeWorksheet',dest,ParentIndex=20)
    for p in sorted((ROOT/'src').glob('*.st')):
        text = p.read_text(encoding='utf-8-sig')
        match = re.match(r'(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s+(\w+)(?:\s*:\s*([^\n]+))?\s*\n', text)
        if not match: raise ValueError(p)
        kind,name,result = match.groups()
        rest = text[match.end():]
        end = list(re.finditer(r'\bEND_VAR\b',rest))
        split = end[-1].end() if end else 0
        variables, code = rest[:split], rest[split:]
        code = re.sub(r'\s*END_(PROGRAM|FUNCTION_BLOCK|FUNCTION)\s*$', '', code).strip()+'\n'
        folder='Logical Elements\\'+name+'.pou'
        arc='PROJECT/'+folder.replace('Logical Elements','Logical%20Elements').replace('\\','/')+'/'
        # Keep the existing Main instance identity/task configuration.
        if name=='Main':
            meta=E.fromstring(files[arc+'Metadata.meta'])
            old=meta.find('ItemGroup')
            for e in list(old):
                if e.tag=='CodeWorksheet': old.remove(e)
            varid=old.find('VariableWorksheet/Id').text
        else:
            meta=E.Element('Metadata')
            for k,v in [('FolderType','PouFolder'),('ContentType',{'FUNCTION':'Function','FUNCTION_BLOCK':'FunctionBlock','PROGRAM':'Program'}[kind]),('Kind',{'FUNCTION':'Function','FUNCTION_BLOCK':'FunctionBlock','PROGRAM':'Program'}[kind]),('Id',uid(name))]:E.SubElement(meta,k).text=v
            if result: E.SubElement(meta,'ReturnType').text=result.strip()
            old=E.SubElement(meta,'ItemGroup');varid=uid(name+'/vars')
            E.SubElement(E.SubElement(old,'VariableWorksheet'),'Id').text=varid
            item('Folder',folder,FolderType='PouFolder',ParentIndex=20).find(tag('Id')).text=uid(name)
            item('MetadataDocument',folder+'\\Metadata.meta',Extension='.meta',ParentIndex=0)
            item('VariableWorksheet',folder+'\\Variables.var',Extension='.var',ParentIndex=1).find(tag('Id')).text=varid
        cw=E.SubElement(old,'CodeWorksheet',Include='Code.st')
        for k,v in [('Id',uid(name+'/code')),('Extension','.st'),('Type','.st'),('ParentIndex','2')]:E.SubElement(cw,k).text=v
        files[arc+'Metadata.meta']=E.tostring(meta,encoding='utf-8',xml_declaration=True)
        files[arc+'Variables.var']=variables.encode('utf-8')
        files[arc+'Code.st']=code.encode('utf-8')
        item('CodeWorksheet',folder+'\\Code.st',Extension='.st',Type='.st',ParentIndex=2).find(tag('Id')).text=uid(name+'/code')
    for el in proj.iter(tag('SolutionReference')):
        if el.attrib.get('Include')=='IIoT_Library': el.find(tag('HintPath')).text=str(ROOT/'reference/IIoT_Library.pcwlx')
    # Expose only the HMI data model. Internal buffers and broker credentials are
    # not published as implicit process tags.
    gv=next(n for n in files if n.endswith('/GlobalVariables.var'))
    files[gv] += ("\nVAR_GLOBAL\n    HMI : NG_Hmi {Id('"+uid('hmi-global')+"')};\nEND_VAR\n").encode()
    dlname=next(n for n in files if n.endswith('/DataList.dl'))
    dl=E.fromstring(files[dlname]); datalist=dl.find('DataList')
    source=datalist.find('Datum/Role').attrib['SourceId']
    datum=E.SubElement(datalist,'Datum',Uuid=uid('hmi-datum')); E.SubElement(datum,'FunctionText')
    role=E.SubElement(datum,'Role',TypeName='Variable',ObjectId=uid('hmi-global'),SourceId=source)
    for k,v in [('Address',''),('Comment','Native gateway Web HMI'),('DataType','NG_Hmi'),('InitValue',''),('IsConstant','False'),('IsHmi','False'),('IsOpc','False'),('IsProficloud','False'),('IsRedundant','False'),('IsRetain','False'),('Name','HMI'),('Usage','Global')]:E.SubElement(role,k).text=v
    hmirole=E.SubElement(datum,'Role',TypeName='HmiTag',ObjectId=uid('hmi-tag'),SourceId='')
    E.SubElement(hmirole,'IsReadOnly').text='False';E.SubElement(hmirole,'Name').text='HMI'
    for command in ('Load','LoadPoint','SaveDevice','SavePoint','RemoveDevice','RemovePoint','Apply','SaveBroker'):
        name='GW_'+command
        files[gv] += ("\nVAR_GLOBAL\n    "+name+" : BOOL {Id('"+uid(name)+"')};\nEND_VAR\n").encode()
        commanddatum=E.SubElement(datalist,'Datum',Uuid=uid(name+'/datum'));E.SubElement(commanddatum,'FunctionText')
        commandrole=E.SubElement(commanddatum,'Role',TypeName='Variable',ObjectId=uid(name),SourceId=source)
        for k,v in [('Address',''),('Comment','HMI command'),('DataType','BOOL'),('InitValue','FALSE'),('IsConstant','False'),('IsHmi','False'),('IsOpc','False'),('IsProficloud','False'),('IsRedundant','False'),('IsRetain','False'),('Name',name),('Usage','Global')]:E.SubElement(commandrole,k).text=v
        commandtag=E.SubElement(commanddatum,'Role',TypeName='HmiTag',ObjectId=uid(name+'/tag'),SourceId='')
        E.SubElement(commandtag,'IsReadOnly').text='False';E.SubElement(commandtag,'Name').text=name
    # HmiTag is the primary role for a connected tag datum in Engineer's format.
    for tagdatum in datalist.findall('Datum'):
        tagrole=tagdatum.find("Role[@TypeName='HmiTag']")
        if tagrole is not None:
            varrole=tagdatum.find("Role[@TypeName='Variable']")
            E.SubElement(varrole,'Constraint',TypeName='Ade.DataList.Constraints.EditableAttributes, Ade.DataListImpl',Parameters='Name,Usage,DataType,InitValue,IsRetain,Comment,IsOpc,IsConstant,IsHmi,IsProficloud,IsRedundant')
    files[dlname]=E.tostring(dl,encoding='utf-8',xml_declaration=True)
    if (ROOT/'reference/NativeGateway.DataList.dl').exists():
        files[dlname]=(ROOT/'reference/NativeGateway.DataList.dl').read_bytes()
    # WriteValueAction targets whole HMI tags. Copy the editor's connected role
    # structure for the string navigation command rather than targeting a member.
    files[gv] += ("\nVAR_GLOBAL\n    GW_Nav : INT {Id('"+uid('GW_Nav')+"')};\nEND_VAR\n").encode()
    connected=E.fromstring(files[dlname]); rows=connected.find('DataList')
    for original in list(rows):
        if not any(n.text=='GW_Load' for n in original.findall('./Role/Name')):continue
        row=copy.deepcopy(original);row.set('Uuid',uid('GW_Nav/'+original.attrib['Uuid']))
        for role in row.findall('Role'):
            role.set('ObjectId',uid('GW_Nav/tag') if role.attrib['TypeName']=='HmiTag' else uid('GW_Nav'))
            role.find('Name').text='GW_Nav'
            for field in ('DataType','PortDataType'):
                if role.find(field) is not None:role.find(field).text='INT'
            if role.find('InitValue') is not None:role.find('InitValue').text='0'
        rows.append(row)
    files[dlname]=E.tostring(connected,encoding='utf-8',xml_declaration=True)
    # The network warning was only an engineering range mismatch; preserve the
    # physical controller IP while aligning the offline project range.
    for n,b in list(files.items()):
        if n.endswith('.ds'):
            document=E.fromstring(b)
            changed=False
            for value in document.iter():
                if 'HMI:AccessRights' in value.attrib.get('xPath',''):
                    value.text='0';changed=True
            if changed:files[n]=E.tostring(document,encoding='utf-8',xml_declaration=True)
        if n.endswith(('.projset','.Transport')):
            encoding='utf-16' if b.startswith(b'\xff\xfe') else 'utf-8'
            files[n]=b.decode(encoding).replace('192.168.1.2','192.168.0.2').replace('192.168.1.254','192.168.0.254').encode(encoding)
        if n.endswith('ResourceSettings.set'):
            files[n]=b.replace(b'INTERVAL := T#100ms',b'INTERVAL := T#20ms').replace(b'Watchdog(T#100ms)',b'Watchdog(T#500ms)')
        if n.endswith('EsmConfiguration.esmc'):
            files[n]=b.replace(b'intervalTime="100000000"',b'intervalTime="20000000"').replace(b'watchdogTime="100000000"',b'watchdogTime="500000000"')
    for e in proj.iter(tag('HmiPage')):
        if e.attrib['Include'].endswith('Gateway.hmi'):e.find(tag('StartPage')).text='True'
    files['PROJECT/PROJECT.proj']=E.tostring(proj,encoding='utf-8',xml_declaration=True)
    # Optional HMI source overlays use project-relative archive names.
    hmi=ROOT/'hmi'
    if hmi.exists():
        for p in hmi.rglob('*'):
            if p.is_file():files[p.relative_to(hmi).as_posix()]=p.read_bytes()
    dest=ROOT/'NativeGateway.pcwex'
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED) as z:
        for n,data in files.items():z.writestr(n,data)
    print(f'Built {dest} ({dest.stat().st_size} bytes)')

if __name__=='__main__':build()
