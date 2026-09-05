# 默读 / Modu Beta 2 · build 6327

本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，是独立修改版，不是上游官方发行版。整体按 GPL-3.0-or-later 发布，保留上游许可及版权。

## 本次更新

- **阅读背景**：修正背景图片格式识别、资源地址转义和缓存；修正颜色编辑保存、取消及即时生效逻辑。手动选择背景时关闭自动主题，避免选择被覆盖。
- **提交 Bug**：设置新增反馈入口，可填写问题、复现步骤并预览，再由用户到 GitHub 提交。可选基础环境信息，不自动附带日志、书籍、聊天或 API Key。
- **移除震动**：删除应用震动调用、设置、开发者测试页及插件依赖，Android 不再申请 VIBRATE 权限，并关闭框架触觉反馈路径。
- **Android 本地推理**：ONNX Runtime 从 1.23.0 更新至 1.24.3，针对上游已报告的 ARM 指令检测兼容性问题。**小米 15 Ultra 上四个模型的闪退尚未完成真机复测，不能将本次更新视为已确认解决所有闪退。**
- 保留四个内嵌 ONNX 模型及分词器，无需下载或 API Key；默认本地中文 BGE、自动向量化默认关闭。远程 AI、翻译和语音仍可能发送文本给所选服务。

## 升级与安装

Beta 2 使用新标签 `v0.1.0-beta.2`，构建号 `6327`；Beta 1 保留。Android 沿用项目专用签名，正式 APK 支持从原签名 Beta 1 覆盖升级。请先备份重要数据，不要为更新直接卸载旧版。

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | 正式专用签名 APK，非 Play Store 版 |
| Windows | x64 / ARM64 | EXE 安装器，附带 VC++ CRT，仍需 WebView2；无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB；使用 APT 安装，不保证其他发行版兼容 |
| macOS | Intel x64 / Apple Silicon ARM64 | DMG，拖入 Applications；ad-hoc 签名，未做 Apple Developer ID 公证 |
| iOS | ARM64 真机 | iOS 16+ 未签名 IPA，需为主程序和 Share Extension 自行合法签名，不能直接安装 |

目标共 9 个应用包，以本发布页实际附件为准。Android `-notices.zip` 是许可附件，GitHub Source code 是源码，均非应用安装包。各附件附 SHA-256。Apple 营销版本为 `0.1.0`，构建号为 `6327`。

## 验证范围与已知限制

- 发布前本机：205 项 Flutter 测试通过、2 项联网测试跳过；10 项阅读器 JavaScript 测试、18 项打包脚本测试通过。
- Android ARM64 Debug 包已构建；包内新版 ONNX / JNI、四个模型、64 位架构、16 KB 对齐、无震动权限已核对。正式分发包由此标签的 CI 重新构建和校验。
- 原生崩溃调查记录：[Android 本地推理与震动移除检查](https://github.com/sobranie2406/modureader/blob/v0.1.0-beta.2/docs/android-onnx-haptics-verification.md)。没有连接的小米真机，无法确认该手机的崩溃堆栈或推理恢复情况。
- CI 的编译、单元测试、安装器检查不等于所有平台全部业务功能均已真机验收。macOS 未公证，iOS 未签名，无 App Store / TestFlight 发布。
- 请勿在公开 Issue 或截图中附带 API Key、同步密码、配置代码或私人书籍。源码及安装包不应包含个人密钥；Android 签名材料保存在仓库 Secrets，不进入源码。

## English summary

Modu Beta 2 (build 6327) improves reader background image/color handling, adds a user-reviewed bug reporting page, removes app vibration, and upgrades Android ONNX Runtime to 1.24.3 for ARM CPU instruction-detection compatibility. The reported Xiaomi 15 Ultra inference crash still requires device testing; successful builds do not establish that it is resolved.

All four local embedding models remain bundled. Local Chinese BGE is the default and automatic indexing is off by default. Android uses the existing dedicated release signing key for upgrades. Back up important data; do not uninstall Beta 1 just to update.

Distribution targets: Android ARM64/x86_64 APK, Windows x64/ARM64 EXE, Debian 13 x64/ARM64 DEB, macOS Intel/Apple Silicon DMG, and an **unsigned iOS ARM64 IPA**. macOS is unnotarized; iOS requires your own valid signing and cannot be installed directly. Each asset has a SHA-256 file. Beta 1 remains available.

Derived from Anx Reader and ReadAny; this is not an official upstream release. Sources, notices and licenses are included or linked.
