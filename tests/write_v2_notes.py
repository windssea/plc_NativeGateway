from pathlib import Path
root=Path(__file__).resolve().parent.parent
p=root/'NATIVE-GATEWAY.txt'
s=p.read_text(encoding='utf-8-sig')
section='''\n\n2026-10-23 NativeGateway v0.2.0 更新（长测开始前）
  原生 IEC/ST + Engineer Web HMI，工程 NativeGateway.pcwex。
  HMI：https://192.168.0.8/ehmi/hmiapp.html
  设备上限 50；共享点池 320；每台最多 32 点。此版本取代上文 v0.1.2 的 8 台上限。
  设备、点位列表每页 8 行，可选择、翻页、新增、编辑、删除；删除有确认页。
  编辑先进入草稿，“应用并持久化”校验、写盘、SHA256 回读通过后才激活。
  MQTT 新配置到达时，无修改草稿自动刷新；有修改草稿检测版本冲突，防止覆盖新配置。
  设备编辑页可把采集/上报周期写到所选设备全部点位；MQTT 支持 config/set、config/patch。
  MQTT 使用 PLC-ENG-01 专用 Topic 前缀和电脑 192.168.0.5:1883 的现有 Docker broker。
  新持久化文件 NativeGateway-v2-A.bin/B.bin，格式 2，双槽、递增 generation、SHA256 回读验证。
  首次运行自动只读迁移旧 NativeGateway-A.bin/B.bin；旧文件不覆盖。
  已实测 HMI 新增设备 hmi-proof、点 point-1，应用 v7 后 Unit 50 采到 235.0 / GOOD。
  已实测 MQTT patch v8 把该点从 5 秒改为 1 秒：12 秒 3 批 -> 15 秒 15 批。
  已实测控制器 Reboot 恢复 v8、3 点 GOOD；broker 当时仅保留旧 v6，不能伪造本地恢复。
  已实测配置 v100：50 台 / 250 点全部值与 mock 预期相符，无缺点。
  发现配置事务阻塞 ACK 时队列满后新批次丢弃；已改为队列满时暂停组批，保留待上报状态。
  修复后 v101 完整配置复测：队列峰值 16、丢弃 0、250 点 GOOD。tests/backpressure-results-v2.json。
  最后修复版编译 0 错误、0 警告，已下载 2152。
  历史联机日志已备份 tests/online-history-20261023.csv 后经用户确认清空。
  清空后所见是编译失败的 MSG_ONL0048、主动重启的连接丢失 MSG_ONL0050，未见新增 MSG_ONL0156。

上报行为
  每点按 pollIntervalMs 采集，按 reportMode / reportIntervalMs 决定待上报。
  每台设备独立 Modbus TCP 连接，台内点位串行轮询。
  网关按 batchIntervalMs（本次 1000 ms）扫待上报点，跨设备合并，每包最多 32 点，自动续包。
  因此不是每次固定把全部 250 点塞进一个包，也不是每台设备固定一个包。
  本次各点采集、上报周期为 5000 ms；250 点约 50 values/s，250 点通常至少分 8 个数据包。
  16 批 RAM 回执队列，等待业务 STORED / REJECTED。队列满时背压，既有队列不被覆盖。
  队列不跨重启保留；背压期间周期样本可合并为最新值，不承诺保存所有历史采样。
  测试端仅模拟业务 ACK：原始报文写入本地 wire 日志并 fsync 后才发 STORED，不代表生产 Hub 入库。

8 小时稳定性记录
  tests/soak/control.json 存实际起止时间及参数；未生成该文件前均为预检，不计入 8 小时。
  tests/soak/summary.json 当前状态；final-summary.json 为真正完成 8 小时后生成的冻结结果。
  tests/soak/wire-*.jsonl 每 64 MiB 轮换保留所有本次收发报文；minute-summary.jsonl 每分钟汇总。
  tests/soak/controller-resources.jsonl 每 10 秒读取控制器 IDeviceStatusService 的 CPU、内存、IEC 内存、温度。
  memoryUsagePercent 与 actualMemoryPercent 同时保存，后者考虑可回收内存，接近 Cockpit 显示口径。
  标准 FILE_OPEN 强制读写，不能直接读取只读 /proc；已停用该尝试，不把无效 0 值当成资源测量。
  资源记录器运行于电脑，采集、配置处理和 MQTT 上报仍全部由 PLC 原生 IEC/ST 执行。
  测试配置中第 50 台保留 HMI 临时设备 ID hmi-proof（Unit 50），其余 soak-meter-001..049。
  第 50 台电压点 ID 为 point-1；其余点 current / frequency / power / energy。仍为 50 台各 5 点。
  实际配置 tests/config-soak-101.json，250 点预期 tests/expected-soak-101.json。
  稳定性测试需电脑、Docker、PLC、网线持续运行；记录器存活期间申请 Windows 保持唤醒，退出即取消。
  删除按钮最终确认的 UI 实测等待用户对临时测试数据的删除许可；不能把代码存在当作已实测通过。
'''
if '2026-10-23 NativeGateway v0.2.0 更新' not in s:p.write_text(s+section,encoding='utf-8')
