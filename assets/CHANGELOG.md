# Modu changelog

Details, installation limits and historical releases: https://github.com/sobranie2406/modureader/releases

## 1.1.2

- Imported TTF/OTF fonts apply immediately and persist; multiple imports select the last successful font, while cancellation or failure preserves the previous choice.
- Add an app brightness slider in the reader; Android uses window brightness without changing system settings, other platforms use an in-app dimming overlay.
- Validate model enablement and availability before queueing and running vectorization, with actionable errors instead of silent keyword-only indexing.
- Update checks and installer downloads prefer GitHub, with Gitee fallback for connection failures, timeouts or service unavailability and mandatory size/SHA-256 checks.
- Stable build 10034. Models remain on-demand; upgrade in place without uninstalling or clearing library data.

- 导入 TTF/OTF 字体后立即应用并记住选择；多选时应用最后成功导入的字体，取消或失败保留原设置。
- 阅读页新增应用亮度滑块；Android 调整窗口亮度而不修改系统设置，其他平台使用应用内遮罩调暗。
- 向量化排队和执行前检查模型启用状态及文件可用性，明确提示如何处理，不再静默生成纯关键词索引。
- 检查更新和安装包下载优先 GitHub，仅连接失败、超时或服务不可用时回退 Gitee，继续校验大小与 SHA-256。
- 正式版构建 10034，模型继续按需下载；请直接覆盖升级，不卸载或清空书库数据。
