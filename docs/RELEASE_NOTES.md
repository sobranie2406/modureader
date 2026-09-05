# 默读 / Modu 首个公开测试版

本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，为独立修改版，不是上游官方发行版。整体按 GPL-3.0-or-later 发布，保留 Anx Reader 的 MIT 许可与各依赖版权。

包含书架、阅读、笔记、统计、AI 阅读技能、多模型配置、RAG 向量索引、翻译、语音和 WebDAV 同步等功能。测试版仍可能存在平台差异；成功构建不等同于所有功能均经真机验证。测试范围见 docs/TESTING.md。

## 安装限制（下载前请阅读）

- Android：独立发行签名 APK，arm64 对应 arm64-v8a，x64 对应 x86_64；不是 Play Store 版本。
- Windows：x64 / ARM64 便携 ZIP，未做商业代码签名，需要 WebView2 Runtime。
- Linux：x64 / ARM64 tar.gz，面向 Ubuntu 24.04；需安装 GTK3、WPE WebKit / FDO、GStreamer 等运行库，见包内 INSTALL.md。
- macOS：x64 / ARM64 ZIP，**未做 Apple Developer ID 公证**。不要关闭整个系统的安全保护；也可以审查源码后自行构建签名。
- iOS：仅 ARM64 真机 **unsigned.ipa**，**不能直接安装**，必须使用自己的合法开发者签名和配置（含 Share Extension）。没有 x64 iPhone 安装包，不是 App Store / TestFlight 发行版。

每个附件提供 SHA-256 校验文件；源码可从本 Release 的 Source code 下载。第三方来源见 UPSTREAM.md，许可证见 LICENSE、LICENSES 和应用“关于”。API 密钥、书籍与本机测试记录均不在源码或安装包中。
