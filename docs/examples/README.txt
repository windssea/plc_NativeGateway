NativeGateway 离线通信样例
全部使用隔离 gatewayId PLC-DEMO-01，不会自动发布，也不会修改 PLC-ENG-01。
JSON 时间戳是固定示例；实际发新命令需使用当前版本基线、新 messageId 和时间戳。
幂等重试应重发原始字节，不能更改 timestamp 后复用 messageId。

Topic 前缀：iot/v1/gateway/PLC-DEMO-01/
全量 config-set-demo.json -> config/set，QoS1，可 Retain。
增量以下依次 -> config/patch，QoS1，不 Retain；须等上一条 APPLIED：
 v2 config-patch-add-demo.json           新增 meter-02
 v3 config-patch-replace-demo.json       meter-01 两点周期改为 1000ms
 v4 config-patch-remove-demo.json        删除 meter-02 及其全部点位
 v5 config-patch-remove-point-demo.json  replace meter-01 完整点表，仅保留 voltage
 v6 config-patch-gateway-demo.json       修改网关组批参数
各版本 baseConfigVersion/baseMessageId 必须匹配实际活动状态。
增量 add/replace 携带完整设备对象，不是 JSON Merge Patch。

config-ack-demo.json / config-patch-ack-demo.json 为设备回执示例；
data-demo.json 为上行数据，data-ack-demo.json 为平台 STORED 回执。
config-get-demo.json 为设备请求平台同步当前配置的消息。
manifest.json 指定每个示例对应的参考协议校验类型。
validation.json 是离线 schema/语义校验结果，不是设备实测结果。
