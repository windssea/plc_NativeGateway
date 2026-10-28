# 唯一正式工程与回退入口

2026-10-28。**后续正式开发、编译和下载统一使用 [native-0.8.0/NativeGateway.pcwex](releases/native-0.8.0/NativeGateway.pcwex)。** 当前设备已经运行该版本，boot84、业务配置19、50台/250点。

| 用途 | 固定文件 | 状态 |
|---|---|---|
| 唯一正式主线 | `projects/releases/native-0.8.0/NativeGateway.pcwex` | Hub逻辑授时、配置恢复、上传、普通断连、整机软件重启及同版本1800秒采集通过 |
| 仅作回退 | `projects/stable/native-0.5.0/NativeGateway.pcwex` | 原始字节保留，旧RTC路径；不用于正式授时联调 |

正式SHA256：`42d246435b950a8352e8dd2421319e546aff3fb8fb9cfb823070d4139279e4fb`。根目录`NativeGateway.pcwex`是正式文件的逐字节兼容副本，**两个路径是同一版本，不是两套交付**；对外和后续任务只引用上表正式路径。catalog的defaultArtifactId/formalArtifactId均为native-0.8.0，fallbackArtifactId为native-0.5.0。

0.7授时候选、审计v2、IEC测试变体及P06输入仅保留历史，不作为默认下载。它们的SHA、旧工具ID及适用范围仍在[catalog.json](catalog.json)与历史报告中，不在归档原地覆盖。

- [正式版本说明](releases/native-0.8.0/README.md)
- [同版本发布验证报告](../docs/主线0.8发布与同版本验证-20261028.md)
- [冻结验收收据](releases/native-0.8.0/verification.json)

下载前只读校验：

```powershell
& 'D:/work/code/PLCnext-Engineer-mcp/.venv/Scripts/python.exe' tools/verify_project_catalog.py
```

校验所有归档SHA、内嵌版本、POU数、唯一正式标记、根副本和已完成的同版本30分钟收据。校验本身不连接PLC。

`src/`与`tools/build_mainline.py`为当前正式主线的可编辑源码和构建入口；从固定旧候选取得硬件/HMI/任务元数据，从src取得全部66POU及NG类型，拒绝覆盖既有输出。后续代码变化应生成新版本输入，冷编译、验证后再提升，不就地覆盖冻结0.8。`build_native.py`、时间/审计/P06构建脚本属于历史开发工具，不作为正式发布入口。

MCP下载顺序：导入正式文件→完整冷编译→生成PCWE（download_memento_policy=`empty_capability_v1`）→完整只读预检→精确审阅/授权→后台下载/启动及运行验证；启动观察显式12次、间隔5秒。PCWEX是工程输入，不是直接写入的二进制包。依赖与路径重定位见[reference/README.md](../reference/README.md)，重定位或源码变更后需重新编译验收。

本次放行是正常负载主线与上述恢复/30分钟观察；P06、24小时、生产漂移、原生遥测文件持久化及物理断电无损仍未放行。配置持久化不能替代遥测历史持久化。
