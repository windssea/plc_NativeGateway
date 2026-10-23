"""Engineer native bilingual HMI; no web sidecar or external runtime."""
from pathlib import Path
import copy,zipfile,xml.etree.ElementTree as E
ROOT=Path(__file__).resolve().parents[1]
TYPE='{http://www.w3.org/2001/XMLSchema-instance}type';E.register_namespace('xsi',TYPE[1:-5])
APP='PROJECT/Hardware/CFG_B6361CC005D54E9BB94A1EF86E276BF6/HMI_Server/Application'
NAVS=['LIST','MQTT','DEDIT','PEDIT','DPREV','DNEXT','PPREV','PNEXT','DDEL','PDEL','CANCEL','DNEW','PNEW','PERIOD']+[f'D{i}' for i in range(1,9)]+[f'P{i}' for i in range(1,9)]+['ZH','EN','REFRESH','DISCARD','REVIEW','COMMIT','DEVON','DEVOFF','POINTON','POINTOFF','MODEHUB','MODELOCAL','CYCLIC','CHANGE','BOTH','HOLDING','INPUT','COIL','DISCRETE','UINT16','INT16','UINT32','INT32','FLOAT32','BOOL','ADVANCED','BROKERREVIEW','BROKERCOMMIT','HELP','TYPEPICK','AREAPICK','REPORTPICK']
C={'ink':'#FF202629','muted':'#FF526365','bg':'#FFF3F6F5','white':'#FFFFFFFF','teal':'#FF007D80','light':'#FFE3F3F0','green':'#FF8AC640','line':'#FFD3DEDA','red':'#FFB43D37'}
NAVS+=['GATEWAY','POINTBACK']
def build():
    with zipfile.ZipFile(ROOT/'reference/NativeGateway.before-implementation.pcwex') as z:original=E.fromstring(z.read(APP+'/Login.hmi/Definition.hmipagedef'))
    templates={}
    for el in original.findall('./Layers/Layer/Objects/HmiObject'):templates.setdefault(el.attrib[TYPE],el)
    templates['HmiImage']=E.parse(ROOT/'reference/hmi-logo-template.xml').getroot()
    page=E.Element('HmiPage',Name='Gateway',BorderWidth='0');objects=E.SubElement(E.SubElement(E.SubElement(page,'Layers'),'Layer'),'Objects');number=0
    def obj(kind,x,y,w,h,label='',size=18,color=None,fill=None,view=None,hide=None,lang=None):
        nonlocal number
        number+=1;o=copy.deepcopy(templates[kind]);o.set('ID','NG4_'+str(number));o.set('Text',label)
        for ch in list(o):
            if ch.tag in ('Dynamic','Action'):o.remove(ch)
        for k,v in dict(FontFamily='Microsoft YaHei',FontSize=str(size),FontColor=color or C['ink'],TabOrder=str(number),LineWidth='1' if kind=='TextInput' else '0',LineColor=C['line']).items():o.set(k,v)
        if kind=='Button':o.set('IsDefault','false');o.find('FillWhenDown').set('Color',C['green'])
        for name in ('Location','Origin'):o.find(name+'/X').text=str(x);o.find(name+'/Y').text=str(y)
        o.find('Size/Width').text=str(w);o.find('Size/Height').text=str(h)
        if o.find('Fill') is not None:o.find('Fill').set('Color',fill or '#00FFFFFF')
        cond=[]
        if view is not None:cond.append('HMI.View <> '+str(view))
        if hide:cond.append(hide)
        if lang is not None:cond.append('NOT HMI.English' if lang else 'HMI.English')
        if cond:
            d=E.SubElement(o,'Dynamic',{TYPE:'VisibilityDynamic','ChangeWhen':'True'});E.SubElement(E.SubElement(d,'Expression',{TYPE:'SimpleSTExpression'}),'ExpressionLine').text=' OR '.join('('+v+')' for v in cond)
        objects.append(o);return o
    def bind(o,field):
        d=E.SubElement(o,'Dynamic',{TYPE:'TextDynamic','TargetProperty':'Text'});E.SubElement(E.SubElement(d,'VariableInstance'),'Name').text='HMI.'+field;E.SubElement(E.SubElement(d,'Expression',{TYPE:'SimpleSTExpression'}),'ExpressionLine').text='HMI.'+field
    def text(x,y,w,h,label='',size=18,field=None,**kw):
        if isinstance(label,tuple):return [text(x,y,w,h,v,size,lang=bool(i),**kw) for i,v in enumerate(label)]
        o=obj('HmiText',x,y,w,h,label,size,**kw)
        if field:bind(o,field)
        return o
    def box(x,y,w,h,view=None):return text(x,y,w,h,fill=C['white'],view=view)
    def button(x,y,w,label,nav=None,command=None,view=None,primary=False,danger=False,hide=None,lang=None):
        if nav in ['DNEW','PNEW','DDEL','PDEL','PERIOD','REVIEW','COMMIT','TYPEPICK','AREAPICK','REPORTPICK','DEVON','DEVOFF','POINTON','POINTOFF','GATEWAY'] or command in ['SaveDevice','SavePoint','RemoveDevice','RemovePoint']:
            hide='('+hide+') OR HMI.Managed' if hide else 'HMI.Managed'
        if isinstance(label,tuple):return [button(x,y,w,v,nav,command,view,primary,danger,hide,bool(i)) for i,v in enumerate(label)]
        o=obj('Button',x,y,w,44,label,17,C['white'] if primary or danger else C['ink'],C['red'] if danger else C['teal'] if primary else C['light'],view,hide,lang)
        o.find('FillWhenDown').set('Color','#FF942C2A' if danger else '#FF00676A' if primary else C['green'])
        a=E.SubElement(o,'Action',{TYPE:'WriteValueAction','Gesture':'Click','ID':'A0','SourceType':'Constant','SourceConstant':str(NAVS.index(nav)+1) if nav else 'TRUE'});E.SubElement(E.SubElement(a,'DestinationVariableInstance'),'Name').text='GW_Nav' if nav else 'GW_'+command
    def input(x,y,w,label,field,view,hide=None,readonly=False):
        text(x,y,w,24,label,16,view=view,color=C['muted'],hide=hide)
        combined=' OR '.join('('+s+')' for s in [hide,'HMI.Managed' if readonly else None] if s) or None
        o=obj('TextInput',x,y+29,w,44,'',18,fill=C['white'],view=view,hide=combined);bind(o,field)
        if field=='Password':o.find('PasswordInputType').text='true'
        if readonly:text(x+8,y+29,w-16,44,field=field,view=view,hide='('+hide+') OR NOT HMI.Managed' if hide else 'NOT HMI.Managed')
    def heading(title,hint,view):text(32,305,1216,34,title,25,view=view);text(32,348,1216,36,hint,17,view=view,color=C['muted'])
    box(0,0,1280,88);obj('HmiImage',24,18,160,52)
    text(244,15,600,38,'NativeGateway',27);text(244,53,800,25,('原生工业采集网关 · 连接设备与数据平台','Industrial gateway · devices to your data platform'),16,color=C['muted'])
    button(1124,22,128,'English',nav='EN',hide='HMI.English');button(1124,22,128,'中文',nav='ZH',hide='NOT HMI.English')
    box(0,88,1280,64)
    text(0,150,1280,3,fill=C['green'])
    for x,label,nav,views in [(24,('设备与点位','Devices & points'),'LIST',[0,1,2,4,5,6,9,10,11]),(216,('连接设置','Connection'),'MQTT',[3,7]),(408,('使用说明','How it works'),'HELP',[8])]:
        active=' OR '.join('HMI.View = '+str(v) for v in views)
        button(x,98,180,label,nav=nav,hide=active);button(x,98,180,label,nav=nav,primary=True,hide='NOT ('+active+')')
    text(790,100,462,40,field='GatewayId',size=20,color=C['muted'])
    for x,w,label,field in [(24,270,('消息服务器','Broker'),'UiConnection'),(310,170,('运行版本','Config version'),'ActiveVersion'),(496,130,('设备','Devices'),'DeviceCount'),(642,130,('点位','Points'),'TotalPoints'),(788,200,('待入库确认 / 批','Awaiting storage / batches'),'QueueCount'),(1004,248,('本地修改状态','Local changes'),'UiDraftState')]:
        box(x,170,w,88);text(x+14,180,w-28,24,label,15,color=C['muted']);text(x+14,211,w-28,32,field=field,size=20)
    text(32,271,1216,25,field='UiConfigSource',size=17,color=C['teal'])
    box(24,310,490,484,view=0);box(530,310,722,484,view=0)
    text(40,322,330,32,('设备','Devices'),24,view=0);text(546,322,480,32,('所选设备的采集点位','Points on selected device'),24,view=0)
    button(376,318,122,('新增设备','Add device'),nav='DNEW',view=0)
    text(40,365,330,26,field='SelectedDevice',view=0,size=16,color=C['muted']);button(376,357,122,('连接详情','Details'),nav='DEDIT',view=0)
    text(546,365,398,26,field='SelectedPoint',view=0,size=16,color=C['muted']);button(976,357,122,('点位详情','Details'),nav='PEDIT',view=0);button(1110,357,126,('新增点位','Add point'),nav='PNEW',view=0)
    for i in range(8):
        y=400+i*48;bg=C['white'] if i%2 else '#FFF0F6F3'
        text(40,y,458,46,field='DeviceRow'+str(i+1),view=0,size=17,fill=bg);button(418,y+1,80,('查看','View'),nav='D'+str(i+1),view=0,hide=f'HMI.DeviceRow{i+1} = ""')
        text(546,y,690,46,field='PointRow'+str(i+1),view=0,size=17,fill=bg);button(1156,y+1,80,('查看','View'),nav='P'+str(i+1),view=0,hide=f'HMI.PointRow{i+1} = ""')
    for x,field,prev,nxt in [(40,'DevicePages','DPREV','DNEXT'),(546,'PointPages','PPREV','PNEXT')]:button(x,806,110,('上一页','Previous'),nav=prev,view=0);text(x+126,814,100,30,field=field,view=0);button(x+238,806,110,('下一页','Next'),nav=nxt,view=0)
    button(1014,806,222,('使配置生效','Review & activate'),nav='REVIEW',view=0,primary=True)
    heading(('设备连接详情','Device connection'),('平台管理时仅供查看；独立使用时，先保存设备，再添加点位。','Read-only in Hub mode. In standalone mode, save the device before adding points.'),1)
    fs=[(('设备标识（唯一）','Device ID (unique)'),'DeviceId'),(('设备名称','Device name'),'DeviceName'),(('设备地址','IPv4 address'),'Host'),(('端口','TCP port'),'Port'),(('站号','Modbus unit ID'),'UnitId'),(('连接超时 / 毫秒','Connect timeout / ms'),'ConnectTimeoutMs'),(('请求超时 / 毫秒','Request timeout / ms'),'RequestTimeoutMs'),(('重试次数','Retry count'),'RetryCount')]
    for i,(label,field) in enumerate(fs):input(32+(i%4)*310,402+(i//4)*90,286,label,field,1,readonly=True)
    text(32,592,260,24,('设备开关','Device enabled'),16,view=1,color=C['muted']);text(32,625,140,35,field='UiDeviceEnabled',view=1)
    button(178,622,90,('启用','Enable'),nav='DEVON',view=1);button(280,622,90,('停用','Disable'),nav='DEVOFF',view=1)
    input(32,688,286,('全部点位采集周期 / 毫秒','All point poll periods / ms'),'DevicePollMs',1,hide='HMI.Managed');input(342,688,286,('全部点位上报周期 / 毫秒','All point report periods / ms'),'DeviceReportMs',1,hide='HMI.Managed')
    button(652,717,430,('把周期加入该设备的待生效配置','Stage periods for all points on this device'),nav='PERIOD',view=1)
    for v,kind,label in [(1,'Device',('保存设备到待生效配置','Save device to draft')),(2,'Point',('保存点位到待生效配置','Save point to draft'))]:
        button(32,806,238,label,command='Save'+kind,view=v,primary=True);button(286,806,180,('返回设备列表','Back to devices'),nav='LIST',view=v);button(1010,806,230,('删除设备…','Remove device…') if v==1 else ('删除点位…','Remove point…'),nav='DDEL' if v==1 else 'PDEL',view=v,danger=True)
    heading(('点位详情','Point details'),('地址从 0 开始。保存点位后，需确认配置生效才会改变采集。','Addresses start at 0. Save the point, then review and activate the draft.'),2)
    fs=[(('点位标识（设备内唯一）','Point ID (unique on device)'),'PointId'),(('点位名称','Point name'),'PointName'),(('寄存器地址（从 0 开始）','Register address (zero-based)'),'Address'),(('单位','Engineering unit'),'Unit'),(('采集周期 / 毫秒','Poll interval / ms'),'PollIntervalMs'),(('上报周期 / 毫秒','Report interval / ms'),'ReportIntervalMs'),(('过期时间 / 毫秒','Stale after / ms'),'StaleAfterMs'),(('变化死区','Change deadband'),'Deadband'),(('倍率','Scale'),'Scale'),(('偏移','Offset'),'Offset'),(('字节序','Byte order'),'ByteOrder')]
    for i,(label,field) in enumerate(fs):input(32+(i%4)*310,398+(i//4)*88,286,label,field,2,readonly=True)
    for x,label,field,nav in [(32,('数据类型','Data type'),'DataType','TYPEPICK'),(342,('寄存器区域','Register area'),'UiArea','AREAPICK'),(652,('上报方式','Report mode'),'UiReportMode','REPORTPICK')]:
        text(x,674,286,24,label,16,view=2,color=C['muted']);text(x,708,188,40,field=field,view=2,size=17);button(x+196,706,90,('选择','Choose'),nav=nav,view=2)
    text(962,674,286,24,('点位开关','Point enabled'),16,view=2,color=C['muted']);text(962,708,82,40,field='UiPointEnabled',view=2,size=17);button(1048,706,90,('启用','Enable'),nav='POINTON',view=2);button(1148,706,90,('停用','Disable'),nav='POINTOFF',view=2)
    heading(('连接消息服务器','Connect to your broker'),('连接参数单独保存；断线后自动重试，无需反复点击保存。','Settings are saved separately. Reconnection is automatic after a network failure.'),3)
    for x,y,label,field in [(32,402,('服务器地址，例如 tcp://192.168.0.5:1883','Broker URI, e.g. tcp://192.168.0.5:1883'),'BrokerUri'),(652,402,('客户端标识（服务器内唯一）','Client ID (unique on broker)'),'ClientId'),(32,496,('用户名（匿名连接留空）','Username (blank for anonymous)'),'UserName'),(652,496,('密码（留空保留原密码）','Password (blank keeps saved password)'),'Password')]:input(x,y,596,label,field,3)
    text(32,590,1216,28,('设备、点位与采集上报周期：请在 Hub 编辑后发布。','Devices, points and periods: edit and publish in Hub.'),18,view=3,hide='NOT HMI.Managed',color=C['teal'])
    button(32,638,250,('高级：身份、模式与时区','Advanced: identity & mode'),nav='ADVANCED',view=3);text(302,646,946,26,('一般无需修改。更换网关身份会清空本机点表，等待新配置。','Usually unchanged. A new gateway ID clears local points and waits for new configuration.'),16,view=3,color=C['muted'])
    input(32,700,388,('网关标识','Gateway ID'),'BrokerGatewayId',3,hide='NOT HMI.Advanced');input(444,700,388,('时区偏移 / 分钟（中国 480）','UTC offset / minutes (China 480)'),'UtcOffsetMinutes',3,hide='NOT HMI.Advanced')
    text(856,700,392,24,('配置管理方式','Configuration ownership'),16,view=3,hide='NOT HMI.Advanced',color=C['muted']);text(856,733,392,30,field='UiManagementMode',view=3,hide='NOT HMI.Advanced');button(856,770,184,('平台管理','Hub managed'),nav='MODEHUB',view=3,hide='NOT HMI.Advanced');button(1052,770,184,('本地独立','Standalone'),nav='MODELOCAL',view=3,hide='NOT HMI.Advanced')
    button(32,838,300,('检查并保存连接…','Review connection settings…'),nav='BROKERREVIEW',view=3,primary=True)
    button(356,838,300,('本地采集与组批设置','Local collection & batching'),nav='GATEWAY',view=3)
    heading(('本地采集与组批','Local collection & batching'),('周期单位为毫秒。设置后检查设备点位，再确认配置生效。','Periods are in milliseconds. Review devices and points, then activate the draft.'),12)
    for x,label,field in [(32,('采集总开关（true 启用 / false 停用）','Collection enabled (true / false)'),'Enabled'),(444,('组批周期 / 毫秒','Batch interval / ms'),'BatchIntervalMs'),(856,('每包点数上限（1～64）','Maximum points per batch (1–64)'),'MaxBatchPoints')]:input(x,420,388,label,field,12,readonly=True)
    text(32,550,1216,100,('组批周期控制网关多久组织一次待发送数据，采集周期由各点位决定。\n超过每包点数上限时自动分包，多个设备的数据可以出现在同一批中。','Batch interval controls how often pending values are grouped. Each point has its own poll period.\nLarge batches are split automatically; a batch may contain points from multiple devices.'),21,view=12)
    button(32,738,300,('检查并使配置生效','Review & activate'),nav='REVIEW',view=12,primary=True);button(356,738,220,('返回连接设置','Back to connection'),nav='MQTT',view=12)
    for v,title,hint in [(4,('确认删除','Confirm removal'),('只修改待生效配置。删除设备会同时移除它的全部点位。','Only the draft changes. Removing a device also removes all its points.')),(5,('放弃未生效的修改？','Discard unapplied changes?'),('用当前运行配置更新列表，已保存到控制器的运行配置不变。','Replace the draft with the running configuration. Saved controller settings stay active.')),(6,('使配置生效并保存','Activate and save configuration'),('完整校验设备与点位；保存成功后按新配置采集，重启自动恢复。','The complete draft is validated, saved and activated. It restores after restart.')),(7,('确认连接设置','Review connection settings'),('保存后连接会短暂中断，再自动连接新地址；请确认网络参数正确。','Saving briefly disconnects MQTT, then reconnects automatically using these settings.'))]:heading(title,hint,v)
    for v in [4,6]:text(48,420,1184,44,field='SelectedDevice',view=v);text(48,478,1184,44,field='SelectedPoint',view=v)
    text(48,560,1184,70,('确认后从草稿移除；仍需“使配置生效”才会停止采集。','After removal, activate the draft to stop acquisition.'),20,view=4)
    button(48,696,330,('删除设备及其点位','Remove device and its points'),command='RemoveDevice',view=4,danger=True,hide='HMI.DeleteKind <> 1');button(48,696,330,('删除所选点位','Remove selected point'),command='RemovePoint',view=4,danger=True,hide='HMI.DeleteKind <> 2');button(402,696,200,('取消，返回列表','Cancel'),nav='CANCEL',view=4)
    text(48,430,1184,100,('草稿中的新增、编辑、删除都将被放弃。\n仅查看最新配置时，可返回列表；显示会自动更新。','All additions, edits and removals in the draft will be discarded.\nTo view updates, return to the list; it refreshes automatically.'),22,view=5)
    button(48,640,300,('放弃修改并更新显示','Discard draft & refresh'),nav='DISCARD',view=5,danger=True);button(372,640,200,('保留修改，返回','Keep changes'),nav='LIST',view=5)
    text(48,554,1184,70,('连接设置与设备点表分开保存。此操作只使设备与点位配置生效。','Connection settings are separate. This action activates devices and points.'),21,view=6);button(48,696,330,('确认生效并保存到控制器','Activate & save to controller'),nav='COMMIT',view=6,primary=True);button(402,696,200,('返回继续检查','Back to review'),nav='LIST',view=6)
    for y,label,field in [(418,('服务器地址','Broker URI'),'BrokerUri'),(508,('网关标识','Gateway ID'),'BrokerGatewayId'),(598,('管理模式','Management mode'),'UiManagementMode')]:text(48,y,1184,28,label,17,view=7,color=C['muted']);text(48,y+32,1184,40,field=field,view=7,size=23)
    text(48,690,1184,56,('切换模式必须使用新网关标识；这会移除原身份的本地点表。','A mode change needs a new gateway ID and clears the old local point configuration.'),19,view=7,color=C['red']);button(48,786,330,('确认保存并自动重连','Save & reconnect automatically'),nav='BROKERCOMMIT',view=7,primary=True);button(402,786,200,('返回修改','Back to edit'),nav='MQTT',view=7)
    heading(('使用流程与自动恢复','Workflow & automatic recovery'),('平台统一管理为主，本地维护用于独立运行场景。','Use Hub as the primary owner. Local editing is intended for standalone use.'),8)
    for y,title,body in [(410,('01  平台管理（推荐）','01  Hub managed (recommended)'),('在 Hub 添加设备与点位，设置采集、上报周期并发布。\n网关自动接收、校验、保存并回执；此页自动显示最新配置。','Add devices and points in Hub, set periods, then publish.\nThe gateway validates, saves and acknowledges the configuration. This UI updates automatically.')),(540,('02  独立运行','02  Standalone operation'),('新增设备 → 保存设备 → 新增点位 → 保存点位 → 使配置生效。\n“保存到待生效配置”还不会改变采集；“放弃修改”恢复当前运行配置。','Add device → save device → add points → save points → activate.\nSaving a draft does not change acquisition. Discard restores the running configuration.')),(670,('03  断线与重启','03  Connection loss & restart'),('断线后自动重连，恢复网络后继续上报；重启自动恢复已保存配置。\n内存队列不跨重启保存；断网期间不保证每次采样都留存。','Reconnection, reporting and saved configuration restore automatically.\nThe RAM queue does not survive restart or retain every offline sample.'))]:text(48,y,1184,32,title,23,view=8);text(48,y+46,1184,78,body,19,view=8,color=C['muted'])
    pickers=[(9,('选择数据类型','Choose data type'),[('16 位无符号整数','16-bit unsigned','UINT16'),('16 位有符号整数','16-bit signed','INT16'),('32 位无符号整数','32-bit unsigned','UINT32'),('32 位有符号整数','32-bit signed','INT32'),('32 位浮点数','32-bit float','FLOAT32'),('布尔值','Boolean','BOOL')]),(10,('选择寄存器区域','Choose register area'),[('保持寄存器','Holding register','HOLDING'),('输入寄存器','Input register','INPUT'),('线圈','Coil','COIL'),('离散输入','Discrete input','DISCRETE')]),(11,('选择上报方式','Choose report mode'),[('定时：按上报周期发送','Cyclic: at the report interval','CYCLIC'),('变化：超过死区后发送','On change: beyond the deadband','CHANGE'),('变化或定时：任一条件满足即发送','Change or cyclic: either condition','BOTH')])]
    for v,title,items in pickers:
        heading(title,('点击选项后返回点位详情，仍需保存点位。','Choose an option, then save the point.'),v)
        for i,(zh,en,nav) in enumerate(items):button(48+(i%2)*608,420+(i//2)*88,570,(zh,en),nav=nav,view=v)
        button(48,758,220,('返回点位详情','Back to point'),nav='POINTBACK',view=v)
    text(32,894,1216,26,field='UiLiveStatus',size=17,color=C['teal']);text(32,926,160,26,('最近操作','Last action'),16,color=C['muted']);text(186,926,1062,28,field='UiStatus',size=16);text(32,965,920,26,field='UiPersistence',size=16,color=C['muted']);button(1000,950,248,('放弃草稿 / 更新显示…','Discard draft / refresh…'),nav='REFRESH',hide='HMI.Managed')
    size=E.SubElement(page,'Size');E.SubElement(size,'Width').text='1280';E.SubElement(size,'Height').text='1000';E.SubElement(page,'MarginColorString').text=C['bg']
    for k,v in [('AvailableSecurityScope','Always'),('AvailableSecurityScopeOperator','Equal'),('AvailableSecurityScopeLevel','0')]:E.SubElement(page,k).text=v
    E.SubElement(page,'Fill',{TYPE:'SolidFill','Color':C['bg']});out=ROOT/'hmi'/APP/'Gateway.hmi/Definition.hmipagedef';out.write_bytes(E.tostring(page,encoding='utf-8',xml_declaration=True));print('Built bilingual native HMI:',number,'objects')
if __name__=='__main__':build()
