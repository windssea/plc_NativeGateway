# PLC 发布管理与 MCP 流程

2026-11-20 正式发布更新：MCP 已新增正式版本提升工具 `project_release_prepare_release`（要求来源 `-dev.` 版本未被阻止、已绑定编译包且具备真实下载启动收据，按 `native-X.Y.Z` 重打心跳版本并仍须独立冷编译、PCWE 打包、冻结绑定与部署后实时验收）。两台设备已完成正式版 **`native-0.8.2`** 发布与实时验收：
- `AXC F 1252`（`192.168.0.10` / `NG-HUB-1252-01`）：`projects/releases/AXCF1252/native-0.8.2/`（源自 `native-0.8.2-dev.c1cfb42488265450`，`project_sha256=dae5e9e059672632308ceee6f9365823540136445df57e238821a45789cb9c8c`，48 文件 PCWE `inventory_sha256=f2854fbe6f32c55be2d2760608a139c665d456231f94b5ffa564d3454cd6c9e7`，部署尝试 `5e41bb53006c4f9a84af93951d0c76e3`），实时心跳核验 `agentVersion=native-0.8.2`、`.7:502` 真实电表 `12/12 GOOD`、`1/1 (abn=0)`。
- `AXC F 2152`（`192.168.0.8` / `NG-HUB-2152-01`）：`projects/releases/AXCF2152/native-0.8.2/`（源自 `native-0.8.2-dev.eb28b9f30280b16f`，`project_sha256=53dd68086cb3dcf0350077d887cbe9c422d4925c61ba1c7d357adc6c145df142`，48 文件 PCWE `inventory_sha256=1e1a5be95d966254285e6a6384747fdf9c380dd479599c8c2095bc01d9727640`，部署尝试 `d02b396c07c245a89b125afcfc851674`），实时心跳核验 `agentVersion=native-0.8.2`、50 台 mock 电表 `250/250 GOOD`、`50/50 (abn=0)`。

2026-11-20 后续更新：MCP **0.6.15** 已补齐 1252 AArch64 冷编译与完整 PCWE/HMI 打包，并完成 2152 回归。型号和硬件变体采用独立、可注册的 profile；另可登记独立设备实例身份。最终 1252 为 `native-0.8.2-dev.6.3c4e8564a1d6e649`，2152 为 `native-0.8.2-dev.2.69bcbcedab8995c3`，均未下载。详见后端 `docs/verification/2026-11-20-axcf1252-mcp-cold-build.md` 和 MCP 项目 `docs/device-toolchains.md`。下方“当前能力”段落保留 0.6.14 时点的历史说明。

生效规则：2026-11-20。2152 与 1252 分开发布；每次下载，包括同版本重装和恢复，都留下独立发布尝试。新增操作优先补齐 MCP，不使用 Computer Use 绕过未支持的能力。

## 发布目录

| 硬件 | 固定设备 | 网关身份 | 目录 |
|---|---|---|---|
| AXC F 2152 | 192.168.0.8 | NG-HUB-2152-01 | `projects/releases/AXCF2152/<version>/` |
| AXC F 1252 | 192.168.0.10 | NG-HUB-1252-01 | `projects/releases/AXCF1252/<version>/` |

每个版本包含 `project.pcwex`、`release.json`。编译包登记后增加 `PCWE/`、`package.json`、`build-receipt.json`、`package-receipt.json`。设备操作产生 `deployments/<attempt-id>/started.json` 和 `terminal.json`。

历史工程逐字节复制，旧路径和旧验收文档保留。历史导入不代表本轮重新下载或重新验收。1252 旧 PCWE 及实际下载证据仍在 `projects/variants/native-0.8.1-axcf1252/`；本轮没有把旧 GUI 编译包登记成 MCP 新冷编译结果。

## 版本规则

- 新源码使用 `native-X.Y.Z-dev.<完整输入SHA的前16位>`，版本写入实际心跳 `agentVersion`，完整 SHA-256 同时存入记录。前缀碰撞或同版本不同字节会拒绝登记。
- 同输入重复准备可重用相同源码版本；编译器、库或构建配置改变导致二进制不同，须递增 `build_number` 生成 `native-X.Y.Z-dev.<build_number>.<输入SHA前16位>`，重新编译，不能覆盖已冻结的包。
- 一个版本只能绑定一份工程、一份编译包。每次下载是新的尝试 ID，重装也保留记录。
- 工程版本、Hub 业务配置版本、启动 BootId 分别记录，不能互相替代。
- 修改工作区不能直接重新下载：必须先冻结 dev 工程，编译该副本，登记该包。未登记或修改后的同名工程会在真实下载/恢复入口被拒绝。
- 正式版另行准备内嵌正式版本的工程、重新编译和验收。不能改目录名、改 JSON 或把 dev 包直接描述为正式验收通过；本轮不提升正式版本。

## MCP 发布顺序

1. `project_import_copy` 导入待修改工程；通过 MCP 编辑得到新修订。
2. `project_release_prepare_dev`：传当前工程 SHA、`base_version`、变更说明，必要时传 `build_number`。返回独立冻结版本和新的 `managed_project`。
3. 对返回的工程调用 `project_build_plan`、`project_compile`。不支持的硬件必须先实现、测试对应编译器与打包器，不能套用另一型号的结果。
4. `project_generate_pcwe` 生成完整包，再调用 `project_release_bind_package` 冻结工程、编译收据、包收据、每个文件哈希。
5. 通过已有 MCP 下载审阅/恢复计划及只读预检核对固定 IP、证书、配置和影响，按授权执行。记录每次尝试，原有一次性授权及目标排他锁继续生效。
6. 下载入口和完整恢复入口在任何 Stop/文件写入之前验证版本、目标、包、编译收据和冻结文件；发布 intent 无法落盘则不执行。
7. 核对下载/Load/Start 和真实运行观察，分别保留结果。核对心跳版本、网关身份、启动实例、授时、配置、采集与入库；不得以磁盘文件匹配推断内存运行镜像完全一致。
8. `project_release_inventory` 查询版本与历次尝试。只有 started 没有 terminal 的记录为结果未知；异常不记录异常消息中的敏感内容，不自动重试。端点隔离仍由原下载/恢复流程处理。

`terminal.status=operation_returned` 仅表示调用已返回，实际成功/失败见 `terminal.result.status`。`controller_downloaded=true` 也不等于业务验收完成。`current_device_version_verified=false` 明确保留未完成的运行版本核验；没有运行证据不得自动改成 true。

## 当前能力与启用方式

MCP 源码：`D:/work/code/PLCnext-Engineer-mcp`，版本 `0.6.14`。新增四个工具：历史归档、dev 版本准备、编译包绑定、发布清单。源码已增加真实下载与恢复入口的发布校验，包括后台恢复作业路径。

配置项 `PLCNEXT_MCP_RELEASE_ROOT` 已指向本仓库 `projects/releases`。新启动 MCP 使用新代码；已经加载的旧 MCP 进程不会热更新。当前聊天仍持有旧工具连接，**后续设备操作使用已加载 0.6.14 的 MCP 新连接**，不能绕过新增校验。本轮实际验收通过隔离的 stdio MCP 客户端完成，没有重启 Hub、MQTT 或 PLC。

2152 新 dev 工程已通过 MCP 冷编译、打包及发布登记，尚未下载。1252 新 dev 工程已登记；现有冷编译器与 PCWE 生成器只验证了 2152/ARM Thumb2，1252/AArch64 仍有能力缺口，必须补齐独立编译、原生库、硬件/HMI/运行映射和打包验证后再发布。登记能力支持 1252 不代表 1252 冷编译已支持。

验证报告见 Hub 后端仓库 `docs/verification/2026-11-20-plc-release-management.md`；完整 MCP 协议证据在相邻 `release-management-20261120/accepted/` 与 `final/`。
