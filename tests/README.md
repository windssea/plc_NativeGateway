# 测试与本机联调

> **最新进度（2026-10-27）：** 审计v2离线修改已提交，M14本机接收通过；MCP72项、独立核验89项和Python55项受约束测试通过。合成导出链路不替代真实交付，IEC20项未执行；不下载PLC，单后端、无新数据库，P06后置。见[接收报告](../docs/M14本机适配接收与受约束验证-20261027.md)。

> 工程与版本以[统一下载入口](../projects/README.md)为准：根工程为授时候选，恢复旧运行程序须选stable归档；本文历史版本说明不代表最终发布。

> **此前进度（2026-10-26，历史记录）：按[JOINT-PLAN/5](../docs/三方联调实施与统一验收-20261026.md)继续三方功能，P06仍后置。Python真实授时/配置/2178事件及两批持久恢复分项已通过；PLC授时候选boot63通过47实机断言、授时/控制/250GOOD及114批2240值入库核验，双端归一化配置一致。MCP0.6.3核销后已恢复原native-0.5.0/boot64，250GOOD及24批1500值核验通过，租约释放；完整故障矩阵/独立事件逐槽对标及整体验收仍待验。现有开发库/唯一后端保持。见[最新报告](../docs/三方联调-T05-T07实机基本闭环与原工程恢复-20261026.md)。**



此目录的 Python / Java 程序及 JSON / YAML 点表是开发和验收工具，网关业务运行在 PLC 的原生 IEC/ST 中，不依赖 PC Python Agent。

## 依赖

- Python 虚拟环境及 `paho-mqtt`；协议校验还需要同级 `PLCnext-iot/src` 中的 `plcnext_iot.contracts`。
- 同级 `PLCnext-mock-device` 提供 `iot_sim` 模拟器，使用 `mock-bootstrap.yaml` 及 `mock-50x5-config.json` 准备 50 台 × 5 点。
- RSC 读写工具需要同级 `JPlcnextRsc` 的 Java / Python SDK；Java 资源采样器还需要相应 SLF4J 依赖。
- Hub 联调需要同级 `PLCnext-Hub-Backend`。现有 `hub_api.py`、`start_hub_backend.py` 是本机开发辅助工具，从该外部工程的本地开发说明读取凭据，不随本仓库提供账号或密码。换机时请适配本地凭据来源和服务配置。
- 测试脚本保留验收环境的地址和部分绝对路径：控制器 `192.168.0.8`、broker `192.168.0.5:1883`、Hub `127.0.0.1:8080`、mock Modbus `11502` / 管理页面 `18080`。运行前检查代码中的地址、网关身份和外部依赖。

## 入口与运行影响

| 程序 | 用途 / 影响 |
|---|---|
| `hub_wire_observer.py` | 只读订阅报文并记录；不生成业务入库回执 |
| `ResourceRecorder.java` | 每 10 秒读取控制器 CPU、实际内存及 IEC 内存 |
| `tools/validate_doc_examples.py`（仓库根目录下） | 离线校验通信样例，不访问控制器 |
| `hub_recovery_verify.py` | 通过 Hub 查询最新值，核对恢复后的点位覆盖 |
| `ui_workflow_probe.py` | 验证 HMI 标签与导航；会操作测试界面状态 |
| `recovery_suite.py` | 有故障注入：停止测试 broker、暂停 mock 或重启控制器。仅在维护窗口执行 |
| `hub_fixture.py` / `hub_closed_loop.py` 等 | 会发布或修改 Hub 测试配置；执行前核对隔离网关身份 |
| `maintenance_mode_verify.py PHASE` | 原生维护模式分阶段验收。会切换配置归属、修改一个点的周期、发布 Hub 配置；`reboot` 会重启控制器 OS。`final-ui` 选择清空后取消，不执行清空。依赖本机已建立的 50×5 隔离 fixture 和前序状态文件，不能跳过前提批量运行 |
| `tools/summarize_maintenance.py --check-hub`（仓库根目录下） | 只读核对当前验收证据、IoT 契约、真实 STORED 覆盖和 50 台设备最新值；不生成回执 |

其他脚本包含历史版本的容量、增删、配置和重启测试，并非可一次性全量运行的单元测试套件。不要直接批量执行此目录的程序。

持续校时验证新增：`continuous_time_verify.py` 是带前提的维护分阶段测试，会改配置，`reboot` 会重启 PLC；`plc_time_stability.py` 默认只读，指定 `--restart-ntp` 会重启本机 `nativegateway-ntp` 容器；`time_locking_acceptance.py publish` 会通过真实 Hub 修改隔离 fixture 周期，可能超时，不应批量重跑，检查已有发布结果后再处理。后者整组验收未完成，不作为 Hub 修复通过证据。记录器可用仓库根目录 `tools/start_lab_recorder.py` 启动，它不发送业务回执。

## 验收材料

`validation/` 保存最终版本的精简验收结果。原始持续采样、原始报文、SQLite 数据库、启动日志、历史截图、旧测试段及虚拟环境保留在原工作站，已从 Git 排除；项目文档中的这些证据路径用于定位原工作站文件。原 8 小时测试提前停止，不代表已通过 8 小时稳定性测试。

完整结论及限制见 `docs/HMI与自动恢复-20261023.md`、`docs/Hub-接入验收-20261023.md` 和主项目说明。

P01/P02 新增 `phase1_capture_test.st` 是纯 IEC 断言入口，使用 `tools/build_phase1_capture_test.py OUTPUT.pcwex` 生成隔离工程，再由 Engineer 编译/明确选定测试控制器。它不运行 MQTT/配置存储/物理 I/O；下载会暂时替换当前程序，须按本轮授权及维护流程执行。`tools/phase1_plc_probe.py before|after|test OUTPUT.json` 只读；`quiesce|candidate` 会在 RAM 暂停采集并等待业务队列排空，成功后保持暂停以便 Engineer 恢复原工程，不保存配置。候选模式还核对真实入口/GOOD 点及稳定计数。`tools/inspect_phase1_compiled.ps1` 只检查编译元数据，不执行程序。结果及恢复边界见 [P01/P02 报告](../docs/阶段1-P01-P02实现与验证-20261024.md)，不要批量运行所有历史测试。

P03/P04 的 `phase1_pipeline_test.st` 同样为纯 IEC 断言，使用 `tools/build_phase1_pipeline_test.py OUTPUT.pcwex` 生成；41 项结果用 `tools/phase1_plc_probe.py pipeline-test OUTPUT.json` 只读导出。夹具 ACK 仅作逻辑输入。`tools/phase1_pipeline_plc_probe.py OUTPUT.json` 只读完整候选快照，`--pause-and-drain` 会暂停 RAM 采集并最多等待 45 秒，成功后保持暂停，超时恢复启用；不能用短超时工具清理大量积压。`tools/phase1_wire_observer.py OUTPUT.json --seconds N --stop-file PATH` 只订阅现有网关 DATA/ACK，最长 3600 秒/4000 条，满条数标记 truncated，不发布消息或伪造 STORED。离线 `tools/check_phase1_pipeline.py --archived` 复核 P03/P04 归档输入及历史证据，不连接设备/数据库；不带该参数时要求当前源码仍等于 P03 输入，后续 P05 开发后不再满足。见 [P03/P04 报告](../docs/阶段1-P03-P04实现与验证-20261024.md)，不要批量运行历史设备脚本。

P05/P06 见[实现、实机验证与待验项](../docs/阶段1-P05-P06开发进度与待验-20261024.md)。`tools/check_phase1_diagnostics.py` 离线核对源码/编译输入/紧凑证据及 23 项主机测试。诊断 16 项和并行流水线 41 项已实机通过；完整生产/性能变体编译 0/0，纯并行 v4 夹具存在 1 条未用 NG_Add4 警告。P06 实测吞吐 57.559/s、最大任务 23.515 ms，不放行；设备已恢复原版本。`tests/phase1_performance_test.st` 和其打包器仅准备，未编译或下载，不作为增量 <=1 ms 证据。

`tools/phase1_audit_export.py OUTPUT.jsonl --wait-ready 120 --seconds 60` 会连接现有 PLC，读取 P05 审计/诊断，且只在文件 fsync 后写审计 ACK 游标；会释放审计副本对配置槽的引用，不改变业务所有权/回执/采集状态。启动前核对目标，不能当纯只读脚本批量执行。文件独占，最多 64 MiB/100000 条；原生环溢出/连接中断后不续接假装完整。`tools/phase1_task_snapshot.py OUTPUT.json` 仅只读 ESM 原生任务信息；LAST/MIN/MAX 属运行任务，不能直接当新代码的增量耗时。旧 ResourceRecorder 继续停止。


P06 验证变体由 `tools/build_phase1_performance_gateway.py OUTPUT.pcwex` 生成，生产源码无故障开关。`tools/phase1_performance_probe.py snapshot OUTPUT.json` 只读；其 hold/release、drop-ack/accept-ack、pause/resume/reset 均会写候选 RAM，必须提供 `--expect-boot` 精确匹配，且只对含 P06 字段的受测工程使用。`tools/phase1_fault_profile.py hold|drop-ack OUTPUT.jsonl --expect-boot BOOT --seconds 300` 在 finally 解除故障门，不能替代清理时的暂停/排空；不停止共享服务、不伪造 ACK。

`tools/audit_phase1_native_cohort.py TRACE WIRE FINAL OUTPUT` 离线复核从原始入口起点开始、最终暂停排空的无损 cohort，逐点重算报告资格并核对关联/报文/真实 ACK。它不证明跨 RAM 重启完整性，也不自动出具性能通过。`tools/verify_phase1_hub_receipts.py WIRE COHORT OUTPUT` 使用 dev-data-check 的现有开发库连接，READ ONLY 查询精确批次收据和样本多重集；不初始化、清理、迁移或创建数据库。运行环境缺 psycopg 时可用 `uv run --python 3.12 --with 'psycopg[binary]' --with paho-mqtt python ...`；不得因此改成临时数据库。原始 JSONL、wire 和展开映射留本机，紧凑证明与 SHA 清单保留在 validation/p05-p06；重新复核原始证明需要这些本地文件。

## 2026-10-27 审计v2离线约束

`audit_facts_test.st`定义20项断言，8个可达POU已公开MCP冷编译，未执行；不得将冷编译写为20项实机通过。完整候选和固定目录见[PLC-AUDIT/2](../docs/PLC逐事件决策时钟与漏槽审计-20261027.md)。主机独立核验在Hub仓库执行`python tools/phase2/run_offline_audit_tests.py`（89项，禁止SQLite/网络）；Python既有采集/时钟组合用`tools/run_startup_regression.py`（55项，禁止SQLite）。不运行会创建临时数据库的全量discover，不下载PLC，不重启服务或恢复P06。

## 2026-10-27 M14本机适配接收

公开MCP 0.6.9/79工具的准备/审阅、72项受约束MCP测试、89项独立核验和55项Python回归通过。IEC20项仍仅编译未执行。明确合成链路入口为Hub仓库的`tools/phase2/receive_m14_loopback.py --mcp-repo D:/work/code/PLCnext-Engineer-mcp --output <全新本机目录>`，需使用MCP虚拟环境Python；SQLite连接禁止，网络连接仅允许自有loopback TLS。它连接生产Exporter与独立核验器，但DATA/STORED均为内存合成，不发布MQTT、不接触Hub数据库或PLC，不构成真实业务交付证明。入口拒绝覆盖已有导出日志。当前禁止下载PLC，P06仍后置；详见[接收报告](../docs/M14本机适配接收与受约束验证-20261027.md)。
