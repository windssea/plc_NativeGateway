# NativeGateway 对接 PLCnext-Hub-Backend 的兼容对齐方案

日期：2026-10-23。依据：三个项目当前源码、保存的 MQTT 报文，以及 Hub 当前 Java 校验器的离线复测。

本文是修改方案与已确认差异，不表示这些修改已经下载到 PLC。现有 native-0.2.0 / v104 的 8 小时长测保持运行，本次未修改 PLC、broker、Hub 数据库或三个项目的业务源程序。

## 1. 目标与用户确认的配置归属

目标是使 Hub 继续使用现有 IoT 网关绑定、草稿、发布、回执、状态投影和数据入库流程，不增加 NativeGateway 专用设备类型、专用 Topic 或数据转换服务。agentVersion 应如实报告原生程序版本，不伪装成 Python Agent。

用户已确认：以 Hub 管理模式为主；HMI 保留维护能力，设备/点表本地编辑仅用于不对接 Hub 的独立模式。

| 项目 | 职责与修改原则 |
|---|---|
| PLCnext-iot | 现有 v1 协议和 Agent 行为作为参照，不为原生程序放宽协议或改变正常收发逻辑 |
| PLCnext-Hub-Backend | 保留当前生产接入路径与校验；不增加“如果是 native”分支 |
| PLCnext-Engineer / NativeGateway | 补齐契约、配置归属、时间、身份、回执和状态行为；适配现有 Hub |

“后端无感”指在原生程序支持的 Modbus TCP / 容量范围内复用同一业务流程，不等于当前 PLC 已获得 Python Agent 的 OPC UA、2000 点及磁盘数据队列能力。

## 2. 本次已完成的离线验证

IoT 与 Hub 的 `protocol.schema.json` SHA256 都是：

```text
d65c133d44a02072972361a4c601ca3b22bf0ab1125f6d63d48ca47b65a830e9
```

两个项目的 topics.json 哈希也完全相同。因此应使用同一契约，不需要另建原生协议。

本次从 Hub 当前源码编译 `DefaultIoTContractValidator` 和 `IoTSemanticValidator`，使用 Hub 已有应用包内依赖，在隔离的临时目录运行。没有启动 Hub 应用、访问数据库或发布 MQTT。

21 项检查结果：11 份文档样例、4 类当前窗口最新报文、3 个候选错误码映射样例通过；另外 3 个当前原生错误回执复现了 Schema 拒绝。所有测试预期均成立。4 类窗口报文是 data、data/ack、heartbeat、config/get；data/ack 来自测试回执器，不是 PLC 上行。

失败分支如下：

| 当前原生回执 | Hub 校验结果 | 对齐方式 |
|---|---|---|
| config/ack：BAD_CONFIGURATION | 不在 error.code 枚举中，消息无效 | 与 IoT 编码器一致，未知内部错误映射为 APPLY_FAILED；本地诊断保留原码 |
| config/patch/ack：BAD_CONFIGURATION | 不在 patchError.code 枚举中，消息无效 | 同上；可准确归类时使用合法的 SCHEMA_INVALID 等码 |
| config/patch/ack：RETAINED_PATCH | 不在 patchError.code 枚举中，消息无效 | 像 IoT 一样映射为 OPERATION_CONFLICT |

证据：`tests/hub-compatibility/audit.json`。重跑：

```powershell
tests/.venv/Scripts/python.exe tools/audit_hub_compatibility.py
```

这只是契约、代表性报文和源码行为审计，不是 Hub 实际注册、发布、入库验收。此前“长测 Schema 错误为 0”只覆盖已收到的报文，不证明未触发的异常回执分支正确。

## 3. 优先解决的接入阻碍

### 3.1 时间：合法 JSON 仍可能被 Hub 忽略

Hub 的 `IoTConfigGetHandler` 与 `IoTStateService` 拒绝未来时间，以及早于当前时间 90 秒的控制/状态报文。不是只要 timestamp 是整数即可。

本次捕获的原生 heartbeat 时间比 PC 记录器接收时间约快 **35.33 秒**。若 Hub 与此 PC 同步，将导致心跳、状态、config/get 被忽略：界面可能一直等待心跳，patch 能力与基线也无法建立。数据入库路径允许未来 5 分钟，故可能出现“数据结构正确，但管理状态不可用”的情况。

修改/部署要求：

1. PLC 与 Hub 使用同一可靠时间源，校正 UTC/RTC 时区转换。
2. 在联调开始前实测 Hub 接收时间与 PLC 报文时间；不通过随意减去固定 35 秒掩盖时钟误差。
3. 用单调时间做采集和重试调度，继续与墙上时间分开。
4. 本次长测期间不校时，以免改变测试条件；接入阶段再处理并留证据。

Hub 对“未来时间”的判断没有正向容差，所以仅声称误差小于几秒还不够，必须实际验证新会话心跳与 config/get 被接纳。若统一校时后仍遇到正常时钟偏差边界，应另行评估所有 Agent 共用的时间策略，而不是给 native 添加特判。

### 3.2 配置：Hub 必须拥有发布历史

Hub 不把任意自报的 configVersion 当作已注册配置。`IoTMessagingMapper.observeGet` 会检查活动版本和 activeMessageId 是否匹配本地发布历史；不匹配会置 config_drift，dispatcher 随后停止自动下发。

`IoTTelemetryTransaction` 按 gatewayId + configVersion 查历史发布，按历史点表映射数据。没有该版本时返回 RETRY，不发 STORED；有版本但不存在对应设备/点时会拒绝。不能让 PLC 任意改点表后沿用 Hub 的版本上报。

当前 v104 / soak-50x5-104 来自独立测试，不能假定新建 Hub 网关已经认识它。首次接入应采用明确的入网流程：备份独立配置，建立干净的 Hub 管理身份/配置基线，由 Hub 正常发布第一条配置。独立测试身份与记录保留。若要沿用既有身份及版本，则必须先验证 Hub 是否有匹配历史；本次没有发现可直接把任意 PLC 活动配置自动导入为历史的现成接入捷径，不应直接写表伪造 APPLIED。

### 3.3 身份：消息 ID 必须跨网关不冲突

当前原生 bootId 为 `eng-{RTC毫秒}-{配置文件Generation}`，数据 ID 为 `data-{bootId}-{sequence}`。两台 PLC 在同一秒、相同 Generation 启动且序号相同，可以产生相同 messageId；RTC 只有秒精度，同台快速重启或回拨也存在重复风险。

Hub 的数据回执按 messageId 查询和去重；相同 ID 来自另一网关或不同 payload 会被拒绝为 VERSION_CONFLICT。Python Agent 使用随机 UUID，当前原生方式不具备同等唯一性。

下一版应使用稳定网关/设备命名空间、持久化启动计数和批次序号组成有长度约束的身份，或使用经过验证的 UUID 实现；须保证所有 ID 不超过协议的 64 字符。启动计数必须在联网和生成数据前可靠提交。不能把最长 64 字符 gatewayId 原样拼接后直接造成超长。

验收包括两台逻辑网关同秒启动、RTC 回拨、同秒重启、配置重载和 MQTT 重连。配置重载不能重置同一 boot 的数据序号，重连只换 sessionId，重发保留原字节及 ID。

### 3.4 异常回执：统一出口做合法编码

在生成 config/ack 与 config/patch/ack 前统一映射内部错误码，按消息类型区分合法枚举，不把内部字符串直接填入 wire。

同时对齐重复设备操作、内外 deviceId 不同等场景的 OPERATION_CONFLICT 语义。保存失败保持 FAILED / STORAGE_ERROR，活动配置不切换；APPLIED 必须在持久化验证与激活完成后发出。

保留现有 patch 的 activeConfigVersion、activeMessageId、appliedConfigVersion 区分，以及原始字节幂等；Hub 对历史 patch 回执不会倒退游标。当前 32 条重放环小于 Python Agent 默认 4096 条请求记录，超出环的历史请求不能谎报已经精确处理，应补持久请求日志/明确容量拒绝，并复测 Hub 断线后的长 patch 链重放。

## 4. 双模式 HMI 的具体设计

| 行为 | HUB_MANAGED | STANDALONE |
|---|---|---|
| 查看设备、点位、质量、连接、队列和版本 | 保留 | 保留 |
| broker、凭据、网络/时间诊断维护 | 保留，变更需提示绑定影响 | 保留 |
| 新增/删除/修改设备和点表、采集/上报周期 | 由 Hub 发布；HMI 编辑与 Apply 均阻止 | 保留现有草稿、确认、持久化流程 |
| 采集配置版本与 messageId | 原样保留 Hub 指定值 | 本地事务生成 |
| 网络断开时自动开放本地编辑 | 不允许；仍保持 Hub 管理归属 | 不适用 |
| 模式切换 | 明确维护动作，说明基线影响 | 明确维护动作 |

只禁用页面按钮不够，`NG_HmiEdit` 与 Main 提交入口都要检查模式，防止旧页面、残留命令或标签写入绕过。模式是本地持久化策略，不新增到现有 heartbeat/config JSON 中；当前 Schema 对未知字段严格拒绝。

HMI 显示配置来源、管理模式、活动版本和活动 messageId。Hub 管理状态下仍能查看和诊断，但本地维护不暗中提升采集配置版本。修改 Gateway ID、迁移 broker 或从独立模式入网需要显式接入维护流程，不能当作普通点位保存。

新增 Mode、BootCounter 等字段若改变现有持久化结构布局，需提升文件格式并提供 v2→新格式迁移；不能继续按 FormatVersion 2 解释变化后的二进制结构。

## 5. 状态、回执与缓存的行为对齐

### 5.1 在线状态与 device/status

配置 MQTT 遗嘱：status、QoS1、retain=true、online=false、reason=connection_lost、timestamp=null、对应会话 sessionId。使用 null 是因为遗嘱在 CONNECT 时预设，断线时已无法填入新鲜时间；IoT 现实现也是此行为。

正常可控断开前尽力发布 shutdown；PLC 突然掉电由 broker 遗嘱与 Hub 心跳超时覆盖。具体库的 Will 结构、生命周期和发布次序须在下一版编译并做断链测试，不能只设一个 Boolean 就认为完成。

增加设备状态变化时的 device/status，沿用现有 Schema。Hub 也会从 heartbeat.devices 更新设备状态，所以缺少单独 device/status 不是当前正常数据接入的硬阻碍，但会影响及时性。

当前 5 秒 heartbeat 比 Python 的 30 秒更频繁，Hub 90 秒超时可接受；频率不同不等于结构不兼容。无需为了字面一致在本次长测中改变节拍。event 虽在共享协议中定义，但当前 Hub 路由没有处理它，本次源码也未见 Python Agent 常规发布；不作为后端无感接入的首要改动。

设备无启用点、整体禁用、断线和恢复等边界也应逐项对齐状态、lastError 与 lastGoodTimestamp。Python 对没有启用点的设备报告 DISABLED；原生目前只按网关/设备总开关覆盖 DISABLED，需补零启用点判断，避免页面长期显示 CONNECTING 等不一致状态。

### 5.2 data/ack 与持久化 Outbox

原生当前只检查 gatewayId、messageId 和 STORED/REJECTED 等关键字段，尚未完整检查 schemaVersion、timestamp、errors 及状态与错误数组的关系。应补完整契约校验，错误回执不能清队列；对未真正发送的批次不接受过早 ACK。

目前原生对任何 REJECTED 都移除并增加 Dropped；Python 对 UNKNOWN_CONFIG_VERSION、RESOURCE_LIMIT、STORAGE_ERROR 这类暂时错误保留并退避重试，其他拒绝进入死信。应按同样策略区分，并保留错误原因供维护。当前 Hub 对缺历史版本或数据库失败通常选择不回 STORED，所以无 ACK 时也必须正确保留和重试。

原生的 16 批 RAM 队列不跨重启，Python 有磁盘 Outbox。在线数据格式可兼容，但若要求掉电/断网后的业务可靠性一致，需要增加限额、校验、原字节重发、重启恢复与死信策略。避免每次扫描同步写盘，应评估周期预算、写放大、存储寿命和可持续吞吐，独立做故障与性能验证。

## 6. 容量与功能边界不能通过伪装解决

| 能力 | Hub / Python 路径 | 当前原生 | 本轮建议 |
|---|---|---|---|
| 设备数 | 最多 50 | 最多 50 | 一致 |
| 总点数 | 最多 2000 | 共享 320 | 本轮先验收 50×5；不盲目扩数组 |
| 每台点数 | 受总点数约束 | 最多 32 | 明确部署约束；超限回合法错误 |
| 配置长度 | 最多 2 MiB | 最多 131071 字节，另受 token 限制 | 先验收实际 Hub 生成配置 |
| 单批点数 | maxBatchPoints ≤500 | 实际发送 ≤32 | 32 小于配置上限仍合法，Hub 不要求固定一包数量 |
| 南向协议 | Modbus TCP、OPC UA None/None | Modbus TCP | 本轮只配置 Modbus TCP |
| 主机地址 | 协议支持主机文本 | 当前仅 IPv4 | 本轮配置 IPv4；域名解析另作能力扩展 |

在后端代码完全不改的前提下，可在这些约束内复用现有功能；Hub 目前不会动态读取原生的 320 点容量，不能声称它能在保存草稿时自动预防所有硬件超限。超限由设备返回标准失败，Hub 按现有发布失败流程展示。

若未来需要 UI 自动按不同设备禁用 OPC UA/限制点数，应为所有 Agent 设计统一能力发现与校验，版本化升级公共契约及 Hub。那是通用产品能力改动，不能靠往现有 JSON 偷加字段，也不属于“后端完全不修改”的承诺。

## 7. 建议实施顺序

1. 保持本次 v104 长测原状，继续观察 PLC；本次只做离线审计和方案。
2. 建立下一版原生源码：管理模式、合法错误出口、启动/数据身份、ACK 验证和 retry 分类；补兼容样例。
3. 完成新增字段的持久化迁移、时间前置条件、Will 和 device/status；按资源预算决定 Outbox 的交付阶段，明确可靠性边界。
4. 长测结束并审阅证据后，在维护窗口编译新版本，再进行 Hub 实际接入；新的程序验收使用新的测试段，不覆盖 v104 证据。
5. 从 Hub 正常绑定与发布开始，取得真实业务入库和回执证据，再确认“无专用后端适配”成立。

### 7.1 实际联调矩阵

| 场景 | 必须取得的证据 |
|---|---|
| 新网关入网 | Hub 看到新鲜 heartbeat、session；config/get 能力与基线被接受 |
| 首次/重复发布 | Hub 自己生成 config/set 或首次 bootstrap patch；APPLIED 与历史版本对应；相同原字节幂等 |
| 设备增删改及周期 | Hub 生成 patch；ACK、草稿、活动配置和数据库结果闭环；删除不只看页面消失 |
| 点位删除 | replace 完整设备点表；原点不再采集/入库，其余点正确 |
| 50×5 | Hub 真实发布的 250 点配置、250 点正确入库、资源与吞吐正常 |
| 断 ACK / 断 broker / 重启 | 原字节 ID 重发、Hub 去重、无伪 STORED；会话与遗嘱行为正确 |
| 无历史配置/非法 ACK/暂时拒绝 | 队列保留、重试/死信符合策略，不误删数据 |
| 双网关、回拨、同秒重启 | ID 无冲突，boot/session 次序可被 Hub 接受 |
| HMI 模式 | Hub 模式禁止本地配置提交；独立模式新增/删除/周期与恢复可用 |
| 超限与错误分支 | Hub 实际记录 REJECTED/FAILED 和合法错误码，无静默超时 |

### 7.2 测试回执器的隔离

当前 soak_observer 会给合法数据模拟 STORED。这适合独立长测，不能作为“Hub 已入库”的证据。真正 Hub 联调时要使用独立网关身份/Topic，或把记录器改为只读观察；不得同时让测试器抢先给该网关发 STORED。以 Hub 事务提交、receipt 和实际数据查询共同验收。

## 8. 源码定位与当前状态

| 依据 | 位置 |
|---|---|
| Hub 严格契约 | hub-device/.../iot/contract/DefaultIoTContractValidator.java、IoTSemanticValidator.java |
| 控制消息时间门限 | hub-device/.../iot/messaging/IoTConfigGetHandler.java |
| 新鲜会话与设备状态 | hub-device/.../iot/state/IoTStateService.java |
| 配置漂移与 patch 游标 | hub-device/.../iot/messaging/IoTMessagingMapper.java |
| 发布报文与重试 | hub-device/.../iot/config/IoTSnapshotCompiler.java、IoTPatchCompiler.java；messaging/IoTReleaseDispatcher.java |
| 历史点表与事务入库 | hub-device/.../iot/telemetry/IoTTelemetryTransaction.java |
| Python 错误码/Will/健康 | PLCnext-iot/src/plcnext_iot/messaging/messages.py、config_service.py、health.py |
| Python 数据持久化和 ACK 分类 | PLCnext-iot/src/plcnext_iot/storage/outbox.py |
| 原生改动入口 | src/Main.st、NG_Mqtt.st、NG_HmiEdit.st、NG_Store.st、类型定义 |

维护窗口进度（2026-10-23）：用户已结束长测，`native-0.3.0` 已进入实际编译、下载和 Hub 联调。管理模式、启动身份、v3 持久化迁移、严格 ACK 分类和 device/status 已实现。Hub 已实际接受首次 patch v1、周期修改 v2、点位删除 v3，并发出真实 STORED，API 可查询正确 mock 数据；最终范围和异常以 `tests/hub-runtime/` 及维护验收报告为准。Hub 和 Python Agent 业务代码未增加 Native 专用协议分支。

已确定的交付差异：供应商库 Will payload 为 IecString80，完整 IoT 遗嘱未启用；离线依赖 Hub 心跳超时。遥测队列仍为 RAM，磁盘 Outbox 未交付。常规业务 ACK 的窗口与等待时间已按 IoT 的 8 批、首次 30 秒/重试 60 秒实现。原“保持长测不下载”等步骤属于维护窗口前的历史计划，现已由用户授权的维护流程取代。
