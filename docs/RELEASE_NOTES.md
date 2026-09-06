# 默读 / Modu Beta 3 · build 6329

本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，是独立修改版，不是上游官方发行版。整体按 GPL-3.0-or-later 发布，保留上游许可及版权。

## 本次更新

- **Xiaomi MiMo**：改用官方 `/v1/chat/completions` 协议，朗读文本放入 assistant 消息，风格放入 user 消息；修正模型、音色和地址默认值，支持官方内置音色及文字设计音色，不改写原文。
- **语音兼容**：正确播放 WAV/MP3，旧 AAC/PCM 配置改用 MP3；MiMo 合成等待时间调整为 60 秒；缓存区分模型、风格和格式等配置。旧配置兼容保留密钥与自定义代理地址。

- **标题与首句**：朗读初始化直接使用当前句，不再额外跳到下一句；保留 H1–H6 文字标题及其目录链接，继续过滤明确的脚注标记和隐藏文字。
- **跨章顺序**：修正系统语音重复回调推进、在线语音补充队列与章节导航之间的竞争；保留重复段落，避免漏掉下一章首句。
- **暂停与切章**：停止后忽略旧任务结果；章节加载中暂停再恢复时保留新章首句；手动切章等待停止完成，不再多跳一句。
- **失败处理**：合成、播放或导航失败时暂停并展示错误，重试保留当前位置，不再用静音代替失败；空章有界跳过，到书末停止。
- 保留 Beta 2 的阅读背景修复、提交 Bug、移除震动及 Android ONNX Runtime 1.24.3。四个本地模型和分词器继续内嵌，默认本地中文 BGE，自动向量化默认关闭。

## 升级与安装

新标签 `v0.1.0-beta.3`，构建号 `6329`；Beta 1、Beta 2 保留。Android 沿用原专用签名，可从相同签名的旧版覆盖升级。请先备份重要数据，不要为更新直接卸载旧版。

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | 正式专用签名 APK，非 Play Store 版 |
| Windows | x64 / ARM64 | EXE 安装器，附带 VC++ CRT，仍需 WebView2；无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB；使用 APT 安装，不保证其他发行版兼容 |
| macOS | Intel x64 / Apple Silicon ARM64 | DMG，拖入 Applications；ad-hoc 签名，未做 Apple Developer ID 公证 |
| iOS | ARM64 真机 | iOS 16+ 未签名 IPA，需为主程序和 Share Extension 自行合法签名，不能直接安装 |

目标共 9 个应用包，以本发布页实际附件为准。Android `-notices.zip` 是许可附件，GitHub Source code 是源码，均非应用安装包。各附件附 SHA-256。Apple 营销版本为 `0.1.0`，构建号为 `6329`。

## 验证范围与已知限制

- 发布前本机：236 项 Flutter 测试通过、2 项联网测试跳过；19 项阅读器 JavaScript 测试通过。包含标题、空章、书末、并发导航、暂停恢复、停止取消和在线语音错误重试用例。
- 新增 21 项小米协议、配置兼容、错误脱敏和音频格式测试，使用模拟 HTTP；**未使用用户 API Key 进行真实 MiMo 联网试听。**
- 1 项 macOS 原生系统语音集成测试通过：三个测试句按顺序完成，其中包含两个标题。未使用私人书库，不等同于原问题书籍已验收。
- 此前朗读顺序修复阶段的 Android ARM64 Debug 构建通过，包内阅读器脚本与生成结果一致；新增 MiMo 修复后的正式分发包由此标签的 CI 重新构建和校验。
- 本机静态分析插件存在环境错误，完整静态分析结果以 CI 为准。详细记录：[朗读回归验证](https://github.com/sobranie2406/modureader/blob/v0.1.0-beta.3/docs/tts-reader-regression.md)。
- **用户原问题书籍、Android 真机听读和小米 15 Ultra 本地模型推理仍待复测。** 图片标题、扫描 PDF 及文件缺失的文字不在此次修复范围，没有新增 OCR。
- CI 编译、单元测试和安装器检查不等于所有平台全部业务功能均已真机验收。macOS 未公证，iOS 未签名，无 App Store / TestFlight 发布。
- 远程 AI、翻译和语音可能发送文本给所选服务。请勿在公开 Issue 或截图中附带 API Key、同步密码、配置代码或私人书籍。Android 签名材料保存在仓库 Secrets，不进入源码。

## English summary

MiMo now uses the official chat-completions speech protocol with corrected defaults, built-in voices and voice design without text rewriting. WAV playback, the 60-second MiMo synthesis timeout and configuration-sensitive caching are fixed. Legacy settings retain keys and custom proxy hosts; unsupported AAC/PCM selections use MP3. The 21 new MiMo tests use mocked HTTP, not a live account.

Modu Beta 3 (build 6329) fixes skipped first sentences and linked text headings in read-aloud. It corrects asynchronous chapter advancement, pause/resume and manual chapter navigation, and retains repeated paragraphs. Synthesis, playback and navigation failures now pause with an error instead of silently skipping text; retries retain the current position. Empty chapters and end-of-book navigation are bounded.

Pre-release local checks: 236 Flutter tests passed, two network tests skipped, and 19 reader JavaScript tests passed. One native macOS system-speech test completed three fixture utterances in order, including two headings. Android ARM64 Debug built successfully. The reported book, Android read-aloud and Xiaomi 15 Ultra local inference still require device testing. Image-only headings and scanned PDFs are outside this fix; no OCR was added.

All four local embedding models remain bundled. Local Chinese BGE is the default and automatic indexing is off. Android uses the existing dedicated release signing key for upgrades. Back up important data; do not uninstall the previous version just to update. Beta 1 and Beta 2 remain available.

Distribution targets: Android ARM64/x86_64 APK, Windows x64/ARM64 EXE, Debian 13 x64/ARM64 DEB, macOS Intel/Apple Silicon DMG, and an **unsigned iOS ARM64 IPA**. macOS is unnotarized; iOS requires your own valid signing and cannot be installed directly. Each asset has a SHA-256 file.

Derived from Anx Reader and ReadAny; this is not an official upstream release. Sources, notices and licenses are included or linked.
