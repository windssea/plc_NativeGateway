# 测试与本机联调

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

其他脚本包含历史版本的容量、增删、配置和重启测试，并非可一次性全量运行的单元测试套件。不要直接批量执行此目录的程序。

## 验收材料

`validation/` 保存最终版本的精简验收结果。原始持续采样、原始报文、SQLite 数据库、启动日志、历史截图、旧测试段及虚拟环境保留在原工作站，已从 Git 排除；项目文档中的这些证据路径用于定位原工作站文件。原 8 小时测试提前停止，不代表已通过 8 小时稳定性测试。

完整结论及限制见 `docs/HMI与自动恢复-20261023.md`、`docs/Hub-接入验收-20261023.md` 和主项目说明。
