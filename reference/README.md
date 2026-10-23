# 构建参考文件

`NativeGateway.before-implementation.pcwex` 保留原始工程的任务、控制器和原生 HMI 配置，供 `tools/build_native.py` 合并源码使用。`NativeGateway.logo-import.pcwex` 提供 Engineer 导入图片时生成的资源元数据。实际界面和图片由 `hmi/` 覆盖，原始 Logo 在 `assets/`。

`NativeGateway.DataList.dl`、`hmi-logo-template.xml` 和 `HMI-Datum.xml` 用于原生 HMI 标签及界面生成。

供应商 **IIoT Library 5.3** 的安装包、库文件、手册和示例不随本仓库分发。请通过 Phoenix Contact 的正式渠道取得并安装。源码打包工具期望本地存在 `reference/IIoT_Library.pcwlx`；该文件已被 Git 忽略。直接在 Engineer 中打开成品工程时，也可在库管理器中重新定位已安装的库。

其他历史备份仍保留在本机，未纳入首次提交。
