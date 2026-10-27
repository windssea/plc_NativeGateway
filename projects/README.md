# 工程与下载入口

本目录和 [catalog.json](catalog.json) 是工程身份、下载用途与 SHA-256 的唯一索引。2026-10-27 归档仅整理本地文件，未下载 PLC。

| 身份 | 固定工程 | 下载用途与验收边界 |
|---|---|---|
| `native-0.5.0` / STABLE_RESTORE | [稳定原工程](stable/native-0.5.0/NativeGateway.pcwex) | 恢复已验证的原运行程序，32 POU、旧 RTC 兼容路径；最近恢复为 boot72、250 GOOD、48 批 3000 值入库核验。不是平台授时最终版。 |
| `native-0.7.0-timesync-candidate.1` / FUNCTIONAL_CANDIDATE | [授时集成候选](candidates/native-0.7.0-timesync-candidate.1/NativeGateway.pcwex) | 后续三方功能联调的默认输入，66 POU；47 项断言、M13 有限源窗口及共同槽分项通过。完整时间/故障矩阵、生产漂移和 P06 未放行，不等于最终发布。 |
| `p06-before-entry-unification` / HISTORICAL_EXPERIMENT | [旧根目录试验输入](experimental/p06-before-entry-unification/NativeGateway.pcwex) | 仅保留历史 P06 输入，不作为默认下载工程。 |
| `native-0.7.1-audit-candidate.2` / OFFLINE_M14_ACCEPTED_PENDING_IEC_EXECUTION_AND_REAL_VALIDATION | [审计v2离线候选](candidates/native-0.7.1-audit-candidate.2/NativeGateway.pcwex) | 逐事件决策时钟/漏槽审计，66 POU冷编译及布局复核通过；M14公开MCP本机接收及合成导出链路通过，IEC20项断言执行及实机待验。本轮禁止下载，不替换默认candidate.1。 |

仓库根目录 [NativeGateway.pcwex](../NativeGateway.pcwex) 现在是授时集成候选的逐字节副本。**默认打开根工程是继续开发/联调；需要恢复旧运行程序时，必须明确选择稳定原工程。当前没有获准长期部署的最终授时发布版。**

归档保留已经验证的原始字节及 hash，不改旧工程内部 `agentVersion`：稳定版为 `native-0.5.0`；授时候选仍为历史嵌入值 `native-0.7.0-p05p06`。后者与旧 P06 输入相同，不能仅靠心跳版本号区分。候选的唯一身份是 `artifactId + SHA-256`；新审计candidate.2已采用独立内嵌版本`native-0.7.1-audit-candidate.2`，编译结果不继承旧实机验收。

下载前先运行只读校验：

```powershell
python tools/verify_project_catalog.py
```

校验根工程别名、四个归档文件、嵌入版本及 POU 数。归档不就地覆盖；新候选另建版本目录并更新清单。历史记录中的临时路径和 MCP project/package ID 保留溯源，后续交付不得以临时文件作为下载入口。MCP 下载仍须导入所选固定文件、冷编译、生成包、审阅/授权和恢复方案；PCWEX 是工程输入，不是直接写入 PLC 的二进制包。

`src/` 是后续可编辑源码，不能视为稳定原工程的源码快照；各冻结 PCWEX 内含对应源码。`tools/build_native.py` 的新生成结果写入 `output/NativeGateway.development.pcwex`，不会覆盖根工程或冻结归档；`tools/build_time_gateway.py` 接受显式 `--base`，输出为待编译的开发产物。供应商库依赖及路径重定位见 [reference/README.md](../reference/README.md)，重定位后的字节变化需重新校验和编译。

已验证候选与原包的对应关系见 [M13 报告](../docs/三方联调-M13有限窗口闭合与逐槽对标-20261027.md)。实机当前状态仍以最后恢复证据为准，不能从本地根工程推断 PLC 已切换。

审计v2离线进度、编码与预算见[PLC-AUDIT/2](../docs/PLC逐事件决策时钟与漏槽审计-20261027.md)；仅冷启动候选，不承诺保留旧RAM在线升级。

M14本机接收及证据边界见[接收报告](../docs/M14本机适配接收与受约束验证-20261027.md)；本机通过不代表候选已执行或允许直接下载。
