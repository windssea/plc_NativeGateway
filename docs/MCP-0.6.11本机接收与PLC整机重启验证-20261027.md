# MCP 0.6.11接收与PLC整机软件重启恢复

2026-10-27。先提交Hub最新值查询修复与验证文档：Hub `c5e64cf`、配套主线文档 `40be8a2`；然后执行本次受约束接收及一次整机软件reboot。使用现有开发PostgreSQL，后端始终为58200/8080一个实例，没有创建数据库或重新下载PLC工程。P06未启动。

## 接收与操作基线

全新stdio进程实际加载`D:/work/code/PLCnext-Engineer-mcp`，公开接口确认0.6.11、85工具，5个reboot入口和`kind=reboot`授权可发现。本轮实际执行本机回环测试：`test_controller_reboot.py` 10项（22.209秒）、`test_lease_reconciliation.py` 29项（3.845秒），共39项全部通过。覆盖正常回复、丢回复不重发、非自动运行后的只读续查、旧boot、取消、无授权、基线篡改、租约重放及配置/证书异常。不将维护者614项全量结果写成本轮执行。

目标192.168.0.8:41100，显式证书SHA256 `3c7b256b25712d045396c61ecaf919700af43b7daaf9f36787438491f9caf863`。运行对象保持稳定归档`projects/stable/native-0.5.0/NativeGateway.pcwex`，源SHA256 `7c0724cdbe18552956b5f111e2c9ae0feb2829f9d28cfa2fd449ffe8bac46154`，MCP项目`17ae4361baa846868b14775bf1de15ea`、既有包`f7fc619d55ba42c091f4ca0efed23e73`。包仅用于绑定身份，没有下载、Reset/Load或文件传输。

授权前只读读取：boot80、Running前后均3、v19、50台/250点、采集启用、250点GOOD。Hub实际与报告版本均19、APPLIED，完整发布配置规范化SHA256为`d6f02536e42aaded44514239b73c48678c315290724f8bfd1c893f32556f64e8`。辅助脚本最初使用了错误大小写`Active.Enabled`，在准备请求生成前失败，未触发设备操作；按实际读取的`Active.enabled`修正后继续。

读计划`1d480ec59dbb44bbb20c63996b8098a9`及其哈希沿用公开运行读取。配置摘要`bf6f827b4a321061bc7dc2f9275ff32bacc1b2db9d320a059136cdf75cd94c3b`覆盖返回的1006个Active字段；该接口明确`full_sampling_configuration_verified=false`。因此本轮是版本/数量/开关、已读取配置字段、Hub完整发布内容及实际250点业务行为的一致性验证，不声称逐字节证明全部PLC配置内存或已加载镜像。

## 一次整机reboot与自动恢复

公开prepare→inspect→精确MCP授权→execute，计划`777d42eb0a27464e8301bb11f8c678a3`，SHA256 `e7b56e8c8acc488ac3fdd592669961ad4e324d87266a1dbdb67c214c97929a2b`。仅调用一次`project_execute_reboot`，没有只读续查或第二次执行。

固定服务`Arp.Device.Interface.Services.IDeviceControlService.RestartDevice()`于15:18:32.104记录一次发送，15:18:32.113收到回复。日志中的第二个RestartDevice事件是该次请求的回复，不是第二次发送。没有补发PLC Start、Reset/Load、下载或变量写入。状态查询只读取本地记录。

结果为`reboot_auto_run_verified`：应用boot80→boot81；最后连续两次独立读取均boot81、Running前后3、v19、相同1006字段配置摘要、250点全部GOOD。最终观测15:20:55.126完成。工具执行至确认约145.391秒，包含基线读取、重连/轮询和连续确认，不能直接当成操作系统纯启动耗时。`outcome_unknown=false`、`endpoint_lease_retained=false`，租约已正常释放，没有待恢复动作。

整次通过MCP独立RSC/TLS完成，不依赖ACI、SSH或Engineer/Computer Use控制设备。Hub网页的浏览器查看仅用于展示验证。工具明确`os_boot_id_verified=false`、`memory_loaded_image_attested=false`：新BootId是NativeGateway应用标识，不是内核boot ID。这是固定整机重启命令后的业务恢复验证，**不是物理断电或介质无损验收**。

## 真实配置、采集和上传

- Hub仍是同一个v19发布记录`2114961616874844161`，APPLIED、实际/报告版本一致；完整发布配置哈希与重启前相同，没有重新发布或录入点表。
- 新boot81的首轮未采样快照在15:20:43产生250条UNKNOWN；15:20:44起出现GOOD。记录保留，没有删除或冒充全启动窗口无异常。最初临时检查曾错误要求整个新boot没有非GOOD，因这些UNKNOWN失败；最终检查按已明确的“完成运行确认之后”验收，并单独保留启动质量分布。
- 以boot81真实收据关联样本，不把旧boot80数据当成恢复：15:20:55.126确认完成后的快照读库共有8576条样本、50台/250点、非GOOD=0；新boot累计151个真实收据（含确认前启动阶段），所选current最后5条均12.4 A。
- 恢复被动窗口仅包含boot81，55个真实收据、3442个样本、250点与既有数据库payload哈希和样本多重集匹配。窗口最后一个DATA的ACK可能晚于捕获结束，最终以数据库实际收据确认；不据此声称完整事件分母或RAM历史无损。
- 心跳保持`agentVersion=native-0.5.0`、v19、RUNNING、50台ONLINE、250GOOD。Hub真实页面显示当前5点良好、12.4 A和历史曲线；旧归档energy v2仍标记陈旧。
- 现有最新值修复仍生效：PLC五次实际HTTP约0.219～0.266秒，IoT约0.187～0.297秒；两端最近一分钟均覆盖50台/250点GOOD。IoT继续v7，没有为PLC重启而停服务或重启Agent。

## 最终状态与后续

PLC始终使用原稳定工程，只经历本次整机软件重启，最终boot81/v19，不需要再下载工程“恢复”。Hub58200/8080、前端35404/8090、mock23716/11502/18080保持；mock实时50台running、250点Good、无设备错误。既有数据库、Redis和broker未切换。

原稳定工程整机软件重启后的配置/自动运行/新采集上传恢复已定向通过。授时集成candidate.1没有在本轮运行，因此不能据此给候选整机授时恢复结项。普通连接恢复、目标服务/容器自启动、30分钟/24小时观察、阶段3原生日志/物理断电等仍按主线计划保留；P06继续后置。

- [Hub证据摘要、配置与真实入库](../../PLCnext-Hub-Backend/docs/verification/2026-10-27-plc-reboot-0611.md)
- MCP原始公开调用、39项测试、两次确认与单次发送证据：Engineer `output/reboot-0611-20261027`。
- 原始被动窗口和读库结果：Backend `logs/plc-reboot-0611-20261027`。

本次新增记录和只读检查工具尚未与上述先行提交混合提交。没有改PLC源码、扩大批长或重新进行P06性能测试。
