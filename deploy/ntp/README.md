# 联调局域网时间源

此服务让 PLC 与同机 Hub 跟随同一个主机时钟，不依赖 PLC 能访问公网。它使用 chrony 的 `local stratum 10` 模式：提供共同时间基准，不声称独立、可溯源的 UTC 精度。生产环境优先使用现场已有、持续校准的 NTP 服务器。

服务不修改宿主机时钟，不授予 `SYS_TIME`；`chronyd -x` 仅提供 NTP 服务。镜像内保存配置，容器使用 `unless-stopped` 重启策略。Docker Desktop 本身也需要随主机启动并保持运行。

```powershell
docker build -t nativegateway-ntp:20261023 deploy/ntp
docker run -d --name nativegateway-ntp --restart unless-stopped -p 192.168.0.5:123:123/udp nativegateway-ntp:20261023
docker exec nativegateway-ntp chronyc tracking
docker exec nativegateway-ntp chronyc clients
```

仅将 UDP 123 绑定到联调网卡 `192.168.0.5`。更换主机需替换该地址，并检查 `chrony.conf` 的允许网段。Docker Desktop 可能转换来源地址，因此配置同时允许其私有转发网段。

PLC WBM 位于 `https://192.168.0.8/wbm/`，在 **Configuration → Date & time** 中配置：服务器 `192.168.0.5`、Active、iBurst、MinPoll=MaxPoll=64 秒。配置保存到控制器 OS，独立于 Engineer 工程下载。手动时间开关保持关闭。

统一采用真实 UTC 时，WBM 时区选 Universal (UTC +00:00)，NativeGateway 的 `UtcOffsetMinutes` 配为 `0`。此前用 Engineer 把电脑本地时间写入 PLC 的测试环境使用过 `480`，不得在切换 NTP 后直接沿用。

切换时先进入维护，并保存一个可撤销的本地修改，使新的 Hub 遥测暂停；等待旧队列完成入库，然后在同一维护窗口调整时钟与网关偏移。确认网关 Unix 时间与 Hub 一致后交还平台，恢复平台备份。不要在正常上报中直接造成 8 小时时间跳变。

诊断时查看容器健康、`chronyc clients` 请求计数和最后请求间隔，并核对重启后 WBM 配置及实际报文。仅看到 Active 不代表已经成功同步。

参考：[chronyd 的 -x](https://chrony-project.org/doc/4.6/chronyd.html)、[chrony 隔离网络模式](https://chrony-project.org/doc/4.6/chrony.conf.html#local)、[PLCnext WBM 校时说明](https://plcnext.jp/archives/5116)。
