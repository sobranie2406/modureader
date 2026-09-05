# 默读 / Modu 首个公开测试版

本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，为独立修改版，不是上游官方发行版。整体按 GPL-3.0-or-later 发布，保留 Anx Reader 的 MIT 许可与各依赖版权。

包含书架、阅读、笔记、统计、AI 阅读技能、多模型配置、RAG 向量索引、翻译、语音和 WebDAV 同步等功能。测试版仍可能存在平台差异；成功构建不等同于所有功能均经真机验证。测试范围见 docs/TESTING.md。

## 安装限制（下载前请阅读）

- Android：独立发行签名 APK，arm64 对应 arm64-v8a，x64 对应 x86_64；不是 Play Store 版本。
- Windows：x64 / ARM64 **EXE 安装器**，支持快捷方式及系统卸载。未做商业代码签名，需要另行安装 WebView2 Runtime。
- Linux：x64 / ARM64 **DEB**，面向 Debian 13 (trixie)；使用 `sudo apt install ./下载的文件.deb` 解析并安装系统依赖。包含 ONNX Runtime 1.22.0，不保证兼容其他发行版。
- macOS：x64 / ARM64 **DMG**，打开后将 Modu.app 拖入 Applications。**未做 Apple Developer ID 公证**。不要关闭整个系统的安全保护；也可以审查源码后自行构建签名。
- iOS：要求 iOS 16 或更新版本，仅 ARM64 真机 **unsigned.ipa**，**不能直接安装**，必须使用自己的合法开发者签名和配置（含 Share Extension）。没有 x64 iPhone 安装包，不是 App Store / TestFlight 发行版。

每个附件提供 SHA-256 校验文件；源码可从本 Release 的 Source code 下载。第三方来源见 UPSTREAM.md，许可证见 LICENSE、LICENSES 和应用“关于”。API 密钥、书籍与本机测试记录均不在源码或安装包中。

## 安装包格式更新（2026-09-05）

六个桌面压缩包替换为 DMG / EXE / DEB，Android APK 和 iOS IPA 不变。Android `-notices.zip` 仅为许可证附件，GitHub 的 `Source code (zip)` 仅为源码，不是安装包。

此次未重新编译应用业务代码，也未移动 `v0.1.0-beta.1` 标签。Linux 安装测试发现原压缩包漏装 ONNX Runtime 实体库并依赖 CI 绝对路径，已补齐微软官方同版本运行库、固定下载 SHA-256，并修正 ELF 库搜索路径。应用源码见原标签；安装器及运行库分发修正见 [fc42d2a1 安装脚本](https://github.com/sobranie2406/modureader/tree/fc42d2a1963f3d759b7ace46fb1aee2f6a1fa091/scripts/release)。包内 `INSTALLER-SOURCE.txt` / `LINUX-RUNTIME.txt` 分别记录来源。

[六个桌面安装器验证均通过](https://github.com/sobranie2406/modureader/actions/runs/33953107529)：macOS 挂载和签名校验、Windows 安装与卸载、Debian 依赖解析及安装卸载。此结果不代表所有平台全部业务功能已完成实机验收。
