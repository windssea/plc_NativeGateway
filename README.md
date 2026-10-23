# NativeGateway

AXC F 2152 的原生 IEC/ST + PLCnext Engineer Web HMI 网关，支持 Modbus TCP 只读采集、MQTT 全量与增量配置、数据组批/业务回执及配置双槽持久化。

- [完整项目说明](docs/NativeGateway-项目说明.md)：架构、字段、HMI 操作、通信协议、构建部署、恢复、实测和运行边界。
- [通信样例与使用顺序](docs/examples/README.txt)
- [可编辑架构图](docs/architecture.mmd)
- [Hub 无感接入对齐方案](docs/Hub-无感接入对齐方案.md)：真实后端行为差异、双管理模式及分阶段验收；含只读 Java 契约审计结果。
- [Hub 接入验收报告](docs/Hub-接入验收-20261023.md)：发布、删点、删设备、周期修改、50×5 入库与真实回执、重启恢复及最终资源指标。

- [双语 HMI 与自动恢复验证](docs/HMI与自动恢复-20261023.md)：新版界面、正确 Logo、配置操作流程、通信中断及系统重启实测。

打开工程：`NativeGateway.pcwex`。当前测试 HMI：<https://192.168.0.8/ehmi/hmiapp.html>。

当前维护版本为 `native-0.4.0`，以 Hub 管理模式为主。设备、点位和周期由 PLCnext-Hub-Backend 原有 IoT 发布接口管理；HMI 保留查看、诊断和 MQTT 维护，独立模式保留本地编辑。Hub 和 Python Agent 业务代码无需为本网关增加专用协议分支。分包支持至 64 点并受 12 KB 值区限制，Hub 模式心跳周期为 30 秒。

原 v104 的 8 小时长测已按用户要求提前结束，实际有效观察 38 分 50.6 秒，不能算 8 小时通过。证据及当时 HMI 短暂不可用异常保留在 `tests/soak/segments/20261023-093205-v104-user-ended-101121`；结论见 `tests/soak/STABILITY-RESULTS.txt`。当前 Hub 联调使用独立身份 `NG-HUB-2152-01`，记录器只读，不模拟 STORED。

部署边界：配置使用 v3 双槽文件自动恢复；遥测队列仍为 16 批 RAM，未交付断电遥测缓存。供应商库的 Will 消息容量为 80 字节，容纳不了完整 IoT JSON，因此当前离线判定依赖 Hub 心跳超时。此前 PDF 是 v0.2 历史说明，维护版以 Markdown 及 Hub 实测报告为准。

示例使用独立的 `PLC-DEMO-01`，离线校验不会发布任何消息。

## 从仓库开始

使用 PLCnext Engineer 2026.0.4 打开根目录的 `NativeGateway.pcwex`，安装或重新定位 IIoT Library 5.3 后编译。源文件位于 `src/`，原生 HMI 位于 `hmi/`；`tools/build_native.py` 负责源码打包，编译和下载仍需 Engineer。供应商库需自行取得，见 [构建依赖](reference/README.md)。

本仓库包含当前工程、源码、文档、测试程序、点表及精简验收结果。虚拟环境、供应商分发文件、持续日志、数据库和历史备份保留在本机，未上传；文档中原始证据路径指向原工作站。测试依赖及可能影响运行的脚本见 [测试说明](tests/README.md)。历史 PDF 不随仓库分发。

```powershell
python tools/validate_doc_examples.py
```
