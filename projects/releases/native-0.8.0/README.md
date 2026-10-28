# native-0.8.0：唯一正式主线工程

正式文件：`D:/work/code/PLCnext-Engineer/projects/releases/native-0.8.0/NativeGateway.pcwex`。

SHA256：`42d246435b950a8352e8dd2421319e546aff3fb8fb9cfb823070d4139279e4fb`，66 POU，心跳版本`native-0.8.0`。仓库根工程是同一字节副本，不是另一版本。

从当前src和固定工程元数据复现构建，68个输入哈希一致，完整冷编译通过。默认Hub逻辑授时、配置双槽恢复、有界缓冲与真实ACK补传均整合在本工程；审计v2试验不进入主线，P06后置。硬件/HMI/任务周期及持久配置布局未变。

2026-10-28：同版本下载boot83、自动授时、真实上传、普通MQTT断连恢复通过；一次整机软件reboot后boot84、配置19、250 GOOD，自动恢复，无补发Start或重下载。15:17:58.243914～15:47:58.257024完整1800秒观察通过，异常0；PLC和IoT各30个完整分钟均50台/250点、非GOOD0。测试后保持本工程运行，0.5仅回退。

验证包`a9974bf30ea84069bc0a0be4fc17e4d2`，49文件，使用`empty_capability_v1`。首次omit包失败及0.5恢复的旧证据继续保留，不复用旧失败授权。再次下载需新的独立预检/审阅/授权，不从历史收据推断写入权限。

[验收收据](verification.json) · [完整报告](../../../docs/主线0.8发布与同版本验证-20261028.md) · [构建输入](NativeGateway.build.json)。

Git保留验收JSON和证据文件的原始字节，避免换行转换破坏SHA。构建收据保留实机验证时的原字节输入hash，`normalizedInputs`另提供LF规范化hash；生成器固定工程类型worksheet为原厂CRLF格式，已用Git规范化的LF源码离线重建，PCWEX仍逐字节等于上述正式SHA，未改动冻结工程或设备程序。

本次是统一主线的正常采集与恢复放行；不代表P06、24小时、生产漂移或遥测掉电无损已通过。0.5回退工程原始字节保留在`projects/stable/native-0.5.0/NativeGateway.pcwex`。
