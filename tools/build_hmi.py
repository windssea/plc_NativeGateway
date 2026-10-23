"""Generate native Engineer HMI objects from its own page templates."""
from pathlib import Path
import copy
import zipfile
import xml.etree.ElementTree as E

ROOT=Path(__file__).resolve().parents[1]
XSI='http://www.w3.org/2001/XMLSchema-instance'
E.register_namespace('xsi',XSI)
TYPE='{'+XSI+'}type'
APP='PROJECT/Hardware/CFG_B6361CC005D54E9BB94A1EF86E276BF6/HMI_Server/Application'
def build():
    with zipfile.ZipFile(ROOT/'reference/NativeGateway.before-implementation.pcwex') as z:
        template=E.fromstring(z.read(APP+'/Login.hmi/Definition.hmipagedef'))
    templates={}
    for o in template.findall('./Layers/Layer/Objects/HmiObject'):
        templates.setdefault(o.attrib[TYPE],o)
    page=E.Element('HmiPage',Name='Gateway',BorderWidth='0')
    objects=E.SubElement(E.SubElement(E.SubElement(page,'Layers'),'Layer'),'Objects')
    counter=0
    def obj(kind,x,y,w,h,text='',color='#FF182B3A',fill='#00FFFFFF',size=17):
        nonlocal counter
        counter+=1
        o=copy.deepcopy(templates[kind]);o.set('ID','GW'+str(counter));o.set('Text',text)
        o.set('FontFamily','Microsoft YaHei');o.set('FontSize',str(size));o.set('FontColor',color);o.set('TabOrder',str(counter));o.set('LineWidth','1' if kind!='HmiText' else '0')
        for el in list(o):
            if el.tag in ('Dynamic','Action'):o.remove(el)
        for field in ('Origin','Location'):
            o.find(field+'/X').text=str(x);o.find(field+'/Y').text=str(y)
        o.find('Size/Width').text=str(w);o.find('Size/Height').text=str(h)
        o.find('Fill').set('Color',fill)
        objects.append(o)
        return o
    def text(x,y,w,h,label,size=17,fill='#00FFFFFF',color='#FF182B3A'):
        return obj('HmiText',x,y,w,h,label,color,fill,size)
    def bind(o,field):
        dy=E.SubElement(o,'Dynamic',{TYPE:'TextDynamic','TargetProperty':'Text'})
        E.SubElement(E.SubElement(dy,'VariableInstance'),'Name').text='HMI.'+field
        E.SubElement(E.SubElement(dy,'Expression',{TYPE:'SimpleSTExpression'}),'ExpressionLine').text='HMI.'+field
    def input(x,y,label,field,width=270):
        text(x,y,width,26,label,16)
        o=obj('TextInput',x,y+28,width,38,'',fill='#FFFFFFFF',size=17);bind(o,field)
        if field=='Password':o.find('PasswordInputType').text='true'
    def value(x,y,w,label,field):
        text(x,y,w,24,label,15,color='#FF516778')
        o=text(x,y+27,w,34,'',21);bind(o,field)
    def button(x,y,w,label,field,primary=False):
        o=obj('Button',x,y,w,44,label,'#FFFFFFFF' if primary else '#FF143A4A','#FF007F86' if primary else '#FFE4EEF1',16)
        a=E.SubElement(o,'Action',{TYPE:'WriteValueAction','Gesture':'Click','ID':'A0','SourceType':'Constant','SourceConstant':'TRUE'})
        o.set('IsDefault','false')
        E.SubElement(E.SubElement(a,'DestinationVariableInstance'),'Name').text='GW_'+field
    text(0,0,1440,80,'   NativeGateway  /  PLCnext 原生采集网关',26,fill='#FF143A4A',color='#FFFFFFFF')
    value(30,98,250,'网关身份','GatewayId');value(320,98,230,'MQTT 连接','Connection');value(580,98,160,'活动版本','ActiveVersion');value(770,98,150,'设备数量','DeviceCount');value(950,98,170,'待确认批次','QueueCount');value(1150,98,230,'丢弃 / 永久拒收','Dropped')
    text(30,178,1380,48,'',16,fill='#FFE9F2F4');bind(objects[-1],'Status')
    text(30,245,420,38,'01  设备连接',22);text(510,245,420,38,'02  采集点表',22);text(990,245,420,38,'03  MQTT 与网关',22)
    device=[('设备序号（1–8）','DeviceIndex'),('设备 ID','DeviceId'),('设备名称','DeviceName'),('启用（true / false）','DeviceEnabled'),('电表 IPv4 地址','Host'),('TCP 端口','Port'),('Modbus Unit ID','UnitId'),('连接超时（ms）','ConnectTimeoutMs'),('请求超时（ms）','RequestTimeoutMs'),('重试次数','RetryCount')]
    for i,(label,field) in enumerate(device):input(30,300+i*73,label,field,420)
    points=[('点序号（1–32）','PointIndex'),('点 ID','PointId'),('点名称','PointName'),('启用 true / false','PointEnabled'),('类型 bool/int16/uint16/int32/uint32/float32','DataType'),('区域 coil/discrete_input/holding_register/input_register','Area'),('零基寄存器地址','Address'),('字节序 AB/BA/ABCD/BADC/CDAB/DCBA','ByteOrder'),('采集周期 ms','PollIntervalMs'),('倍率','Scale'),('偏移','Offset'),('单位','Unit'),('上报 cyclic/change/change_or_cyclic','ReportMode'),('上报周期 ms','ReportIntervalMs'),('变化死区','Deadband'),('过期时间 ms','StaleAfterMs')]
    for i,(label,field) in enumerate(points):input(510+(i%2)*225,300+(i//2)*89,label,field,205)
    broker=[('Broker URI（tcp://主机:端口）','BrokerUri'),('Client ID（Broker 内唯一）','ClientId'),('用户名（匿名可留空）','UserName'),('密码（写入后清空）','Password'),('RTC 时区偏移（分钟）','UtcOffsetMinutes'),('采集总开关（true / false）','Enabled'),('组批周期（ms）','BatchIntervalMs'),('每批点数上限（自动分包）','MaxBatchPoints')]
    for i,(label,field) in enumerate(broker):input(990,300+i*73,label,field,420)
    button(30,1054,200,'载入活动配置','Load');button(250,1054,200,'保存设备到草稿','SaveDevice');button(30,1110,200,'从草稿移除设备','RemoveDevice')
    button(510,1054,205,'载入草稿点位','LoadPoint');button(735,1054,205,'保存点位到草稿','SavePoint');button(510,1110,205,'从草稿移除点位','RemovePoint')
    button(990,920,420,'保存 MQTT 设置并重连','SaveBroker');button(990,1054,420,'校验并应用完整草稿','Apply',True)
    text(990,1110,420,64,'先保存设备与点位草稿，再应用。\nMQTT 更新活动版本后，旧草稿会被拒绝。',16)
    value(30,1190,200,'所选设备状态','DeviceStatus');value(270,1190,240,'所选点最新值','LastValue');value(550,1190,220,'质量','LastQuality');value(810,1190,250,'UTC Unix 时间戳（ms）','LastTimestamp')
    text(30,1280,1380,36,'',16);bind(objects[-1],'ConfigResult')
    text(30,1330,1380,42,'原生 IEC/ST  ·  Modbus 只读  ·  每设备 32 点 / 最多 8 台  ·  配置 ACK 在保存并回读校验后发送',16,color='#FF516778')
    s=E.SubElement(page,'Size');E.SubElement(s,'Width').text='1440';E.SubElement(s,'Height').text='1390'
    E.SubElement(page,'MarginColorString').text='#FFF4F7F8'
    for k,v in [('AvailableSecurityScope','Always'),('AvailableSecurityScopeOperator','Equal'),('AvailableSecurityScopeLevel','0')]:E.SubElement(page,k).text=v
    E.SubElement(page,'Fill',{TYPE:'SolidFill','Color':'#FFF4F7F8'})
    out=ROOT/'hmi'/APP/'Gateway.hmi/Definition.hmipagedef';out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(E.tostring(page,encoding='utf-8',xml_declaration=True))
    print('Generated native HMI objects:',counter)
if __name__=='__main__':build()
