"""Generate explicit, bounded display translations; never alter wire values."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
T={
'CONNECTED':'已连接','CONNECTING':'正在连接','ONLINE':'在线','OFFLINE':'离线','DEGRADED':'部分异常','DISABLED':'已停用','UNCONFIGURED':'未配置','DRAFT':'待生效',
'GOOD':'正常','BAD':'异常','STALE':'已过期','UNKNOWN':'暂无数据','BAD_COMMUNICATION':'通信异常','BAD_CONFIGURATION':'配置有误',
'true':'启用','TRUE':'启用','false':'停用','FALSE':'停用',
'PERSISTED':'已保存，无待生效修改','UNSAVED DRAFT':'有待生效的修改','VERSION CONFLICT':'配置已变更，请放弃旧草稿',
'HUB_MANAGED':'平台统一管理','STANDALONE':'本地独立管理',
'HUB_MANAGED - local device/point changes blocked':'平台管理：在 Hub 编辑设备、点位与周期并发布；此处查看和维护连接。',
'STANDALONE - local maintenance enabled':'本地管理：编辑设备和点位 → 保存到待生效配置 → 确认生效并保存。',
'holding_register':'保持寄存器','input_register':'输入寄存器','coil':'线圈','discrete_input':'离散输入',
'cyclic':'定时上报','change':'变化时上报','change_or_cyclic':'变化或定时上报',
'voltage':'电压','current':'电流','frequency':'频率','power':'功率','energy':'累计电能',
'No device selected':'暂无设备，请先添加设备','No point selected':'暂无点位，请先添加点位',
'HUB_MANAGED: publish device and point changes from Hub.':'当前由平台管理，请在 Hub 修改并发布设备和点位配置。',
'Display refreshed from active configuration. Unapplied draft discarded.':'已按当前运行配置更新显示，未生效的草稿已放弃。',
'Loaded persisted active configuration.':'已按控制器当前运行配置更新显示。',
'Capacity reached: 50 devices.':'设备数量已达上限：50 台。',
'Capacity reached: 32 points/device, 320 shared points.':'点位数量已达上限：每台 32 个，总计 320 个。',
'New device: save into draft, then add its points.':'填写连接参数并保存设备，再为该设备添加点位。',
'Save a device into the draft first.':'请先保存设备，再添加该设备的点位。',
'New point: save into draft, then apply the complete draft.':'填写寄存器与周期，保存点位后再确认配置生效。',
'Busy: configuration transaction in progress. Try again shortly.':'正在保存配置，请稍候再试。',
'Device index 1..50; point index 1..32.':'请检查设备序号（1～50）和点位序号（1～32）。',
'Invalid device fields: check ID, name, IPv4, port and timeout values.':'设备未保存：检查唯一标识、名称、地址、端口与超时。',
'Device saved to draft. Apply draft to persist.':'设备已加入待生效配置。检查点位后，点击“使配置生效”。',
'Invalid point fields; save the device first and check numeric fields.':'点位未保存：先保存设备，再检查地址、周期、倍率等数值。',
'Point saved to draft. Apply draft to persist.':'点位已加入待生效配置。点击“使配置生效”后开始使用。',
'Device and points removed from draft. Apply to persist.':'设备及其点位已从草稿移除，确认配置生效后才停止采集。',
'Point removed from draft. Apply to persist.':'点位已从草稿移除，确认配置生效后才停止采集。',
'Invalid device polling/report period.':'周期未修改：采集与上报周期必须为有效的毫秒数。',
'Device point periods updated in draft. Apply to persist.':'该设备的点位周期已加入待生效配置，请确认生效。',
'VERSION_CONFLICT: reload active configuration before applying.':'运行配置已有更新。请放弃旧草稿，按最新配置重新编辑。',
'Invalid gateway batch settings.':'请检查组批周期与每包点数（1～64）。',
'Saving, hashing and reading back configuration...':'正在保存并校验配置，请稍候。',
'Check broker/mode/ID. Mode change requires a new Gateway ID to isolate configuration history.':'连接未保存：检查地址、网关标识、客户端标识与模式；换模式须换网关标识。',
'Saving broker settings...':'正在保存消息服务器连接设置，请稍候。',
'APPLIED: configuration saved and activated.':'配置已生效并保存；重启后将自动恢复。',
'Broker/mode saved; identity changes reset local baseline.':'连接设置已保存，正在自动重连；新身份需由平台重新下发配置。',
'Startup identity persisted; MQTT starting.':'已自动恢复保存的配置，无需重复保存。',
'Persisting unique startup identity before MQTT...':'正在保存启动信息，随后自动连接消息服务器。',
'STORAGE_ERROR: active configuration unchanged.':'保存失败，运行配置保持原样。请检查控制器存储。',
'Saving / validating durable file...':'正在写入并校验控制器配置文件……',
'STORAGE ERROR: configuration not committed.':'配置保存失败，请检查控制器存储。',
'Restoring saved configuration...':'正在恢复已保存配置，随后自动连接并采集。',
'Broker unavailable. Retrying automatically; local acquisition continues.':'消息服务器暂不可用，正在自动重连；本地采集继续运行。',
'MQTT_DISCONNECTED':'连接中断，自动重连中','MQTT_CONNECT_ERROR':'连接失败，自动重试中','MQTT_TIMEOUT':'连接超时，自动重试中','MQTT_PUBLISH_ERROR':'发送失败，自动重连中','MQTT_CLIENT_ERROR':'通信组件异常，自动重试中','MQTT_SUBSCRIBE_ERROR':'订阅失败，自动重试中','MQTT_CONSUME_ERROR':'接收失败，自动重试中',
'SCHEMA_INVALID':'配置格式或取值不正确，请检查点位详情。','DUPLICATE_DEVICE_ID':'设备标识重复，请使用唯一标识。','DUPLICATE_POINT_ID':'同一设备内点位标识重复。','INVALID_STALE_INTERVAL':'过期时间必须不小于采集周期。','INVALID_ADDRESS':'寄存器地址范围无效。',
'BAD_CONNECTION':'连接异常','BAD_TIMEOUT':'请求超时','BAD_PROTOCOL':'报文异常','BAD_DECODE':'数据解码异常',
}
def q(v):return "'"+v.replace("'","''")+"'"
def w(v):return chr(34)+v.replace(chr(34),'$"')+chr(34)
lines=['FUNCTION NG_UiText : NG_UiLabel','VAR_INPUT','    Value : NG_Text;','    English : BOOL;','END_VAR','NG_UiText:=TO_WSTRING(Value,"");','IF English THEN']
friendly={'PERSISTED':'Saved · no changes','UNSAVED DRAFT':'Unapplied changes','VERSION CONFLICT':'Configuration changed','CONNECTED':'Connected','CONNECTING':'Connecting','HUB_MANAGED':'Hub managed','STANDALONE':'Standalone','holding_register':'Holding register','input_register':'Input register','discrete_input':'Discrete input','cyclic':'Cyclic','change':'On change','change_or_cyclic':'Change or cyclic','Startup identity persisted; MQTT starting.':'Saved configuration restored automatically. No need to save again.','true':'Enabled','TRUE':'Enabled','false':'Disabled','FALSE':'Disabled','HUB_MANAGED - local device/point changes blocked':'Managed by Hub: edit and publish devices, points and periods in Hub. Connection maintenance is available here.','STANDALONE - local maintenance enabled':'Standalone: edit devices and points → save to draft → review and activate.'}
for i,(key,value) in enumerate(friendly.items()):lines.append(('IF' if i==0 else 'ELSIF')+' Value='+q(key)+' THEN NG_UiText:='+w(value)+';')
lines+=['END_IF;','RETURN;','END_IF;']
for i,(en,zh) in enumerate(T.items()):
 assert len(zh.encode('utf-8'))<=255,(en,len(zh.encode('utf-8')))
 lines.append(('IF' if i==0 else 'ELSIF')+' Value='+q(en)+' THEN NG_UiText:='+w(zh)+';')
lines+=['END_IF;','END_FUNCTION']
(ROOT/'src/NG_UiText.st').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(len(T),'explicit display translations')
