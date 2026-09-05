# 默读 / Modu Beta 1 · 修订构建 6326

本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，为独立修改版，不是上游官方发行版。整体按 GPL-3.0-or-later 发布，保留 Anx Reader 的 MIT 许可与各依赖版权。

包含书架、阅读、笔记、统计、AI 阅读技能、多模型配置、RAG 向量索引、翻译、语音和 WebDAV 同步等功能。测试版仍可能存在平台差异；成功构建不等同于所有功能均经真机验证。测试范围见 docs/TESTING.md。

## 安装限制（下载前请阅读）

- Android：独立发行签名 APK，arm64 对应 arm64-v8a，x64 对应 x86_64；不是 Play Store 版本。
- Windows：x64 / ARM64 **EXE 安装器**，支持快捷方式及系统卸载。未做商业代码签名，需要另行安装 WebView2 Runtime。
- Linux：x64 / ARM64 **DEB**，面向 Debian 13 (trixie)；使用 `sudo apt install ./下载的文件.deb` 解析并安装系统依赖。包含 ONNX Runtime 1.22.0，不保证兼容其他发行版。
- macOS：x64 / ARM64 **DMG**，打开后将 Modu.app 拖入 Applications。**未做 Apple Developer ID 公证**。不要关闭整个系统的安全保护；也可以审查源码后自行构建签名。
- iOS：要求 iOS 16 或更新版本，仅 ARM64 真机 **unsigned.ipa**，**不能直接安装**，必须使用自己的合法开发者签名和配置（含 Share Extension）。没有 x64 iPhone 安装包，不是 App Store / TestFlight 发行版。

每个附件提供 SHA-256 校验文件；源码可从本 Release 的 Source code 下载。第三方来源见 UPSTREAM.md，许可证见 LICENSE、LICENSES 和应用“关于”。API 密钥、书籍与本机测试记录均不在源码或安装包中。

## Beta 1 修订重建（build 6326）

本次沿用 `v0.1.0-beta.1` 发布页和版本名，重新编译应用，内部构建号由 6325 增至 6326。请重新下载安装包，不要继续使用旧下载缓存。Android 使用原专用签名，可覆盖更新；请勿卸载应用后再安装，以免清除本机数据。

- Windows 随应用附带同架构 VC++ CRT 运行库，并检查安装后的运行库完整性。仍需 WebView2。
- Android tokenizer 重新链接为 16 KB ELF 对齐；打包时检查全部原生库与 ZIP 对齐。
- macOS/iOS 营销版本为 `0.1.0`，构建号独立保留为 `6326`，不再产生四段营销版本。
- 未选系统声音时使用原生默认声线。Linux 不支持系统语音，设置和阅读入口明确提示；不会自动切到在线服务或上传正文。
- 新增英文 README 与中英文切换，保留上游致谢、真实截图和安全说明。

四个 ONNX 本地向量模型及分词器全部内嵌，合计约 208 MiB，无需下载或 API Key。默认使用 BGE Small ZH v1.5，自动向量化默认关闭。首次覆盖旧版也会应用这两项设置，但保留远程配置和密钥；之后的手动选择不会反复重置。首次使用只在本机准备模型文件。远程聊天、翻译或语音仍可能将文本发送给所选服务，本地向量化不代表整个 AI 流程离线。

六个桌面包使用 DMG / EXE / DEB。Android `-notices.zip` 仅为许可证附件，GitHub 的 `Source code (zip)` 仅为源码，不是安装包。Linux 保留 ONNX Runtime 1.22.0 实体库和相对 ELF 库路径修正。

本轮本机验证：172 项 Flutter 测试通过、2 项外部环境测试跳过；17 项打包测试及 8 项阅读器 JavaScript 测试通过。macOS 原生集成测试实际加载四个内嵌模型，均生成正确维度的归一化向量，模型下载请求为零。构建及安装检查不等于全平台真机功能验收。macOS 仍未公证，iOS 仍未签名。每个平台打包时校验四个模型及分词器的固定 SHA-256，缺失或损坏即停止打包。

## 原版来源

原始 build 6325 的应用源码为 [454b3b54](https://github.com/sobranie2406/modureader/tree/454b3b547d47395f4ce02f0998c83401b6ace743)，原桌面安装器封装源码为 [fc42d2a1](https://github.com/sobranie2406/modureader/tree/fc42d2a1963f3d759b7ace46fb1aee2f6a1fa091)。本次旧附件已在发布操作前本地备份；新包的 SOURCE.txt 标明其实际源码提交。
