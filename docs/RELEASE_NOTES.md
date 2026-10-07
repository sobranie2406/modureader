# Modu 1.2.2 · Stable

## English

**Modu 1.2.2 (build 10087)** includes the following changes since stable **1.2.1**.

- Import multiple books at once: choose files, import a folder recursively, or select supported files within a folder. On desktop, drop files or folders onto the bookshelf or reader. Import staging preserves the original files.
- Improve text selection in OCR and text-reflow reading: macOS shows the selection toolbar automatically and supports initial word expansion; Android also expands the initial selection. Selection handles remain available for manual adjustment, with the paragraph-selection preference supported. Ordinary text-book reading remains separate from scanned-page processing.
- Reduce motion throughout E-Ink mode, including app navigation, pop-ups, page-turn effects and animated loading indicators. Use solid, high-contrast surfaces in place of translucent effects; turning E-Ink off restores normal presentation.
- Add compact book-format and scanned-book badges to covers. Manual scanned-book settings take priority over automatic classification. Format badges describe the stored file, so books converted from TXT / Markdown may show EPUB.
- Make the floating home navigation translucent, with trailing scroll clearance so the last row remains visible and accessible.
- Add a separate object-storage sync tab with S3-compatible provider presets, including Alibaba OSS and Tencent COS. Existing WebDAV credentials and enabled state are retained; switching providers does not move cloud data. Back up before switching. Provider compatibility remains subject to the actual endpoint and bucket configuration.
- Fix footnote links inside highlighted or underlined text being intercepted by the annotation toolbar. Make folder overflow buttons consistent with book covers.
- Reduce Android opening-transition contention by initializing the reader after the cover transition; reduce unnecessary rebuilds when the AI keyboard changes and fix double keyboard avoidance. Actual device frame-rate improvements have not yet been measured.
- Include a native HarmonyOS ARM64 **unsigned HAP**. It requires HarmonyOS signing credentials/profile before installation; an Android APK signature cannot be reused. This package has not yet been validated on a physical HarmonyOS device.
- Add the Telegram channel and discussion group to About, feedback and bilingual project documentation. The QQ community shows a copyable group number instead of a QR code: **1009765685**.

[Telegram channel](https://t.me/Modureader) · [Discussion group](https://t.me/ModuReaderDiscussion)

Nine packages, each with SHA-256: Android ARM64; iOS ARM64; macOS, Windows and Linux ARM64/x64; HarmonyOS ARM64 (unsigned HAP, manual signing/installation). Android x64 is not distributed. Mac disk images contain only Modu.app and the Applications shortcut.

Back up and upgrade in place. Android retains the project signing key. macOS uses ad-hoc signing and is not notarized; Windows requires WebView2; Linux packages target Debian 13; iOS requires your own valid signing for the app and Share Extension. Models remain on-demand downloads.

[Corresponding source](https://github.com/sobranie2406/modureader/tree/v1.2.2) · [Changes since 1.2.1](https://github.com/sobranie2406/modureader/compare/v1.2.1...v1.2.2) · [Installation guide](https://github.com/sobranie2406/modureader/blob/v1.2.2/docs/RELEASING.md)

---

## 简体中文

**Modu 1.2.2（构建 10087）**，以下为 **1.2.1 正式版以来**的变化。

- 支持批量导入书籍：多选文件、递归导入整个文件夹，或进入文件夹后勾选适配格式。桌面端可将文件或文件夹拖到书架及阅读界面；导入过程保留原始文件。
- 改善 OCR 与文字重排阅读中的选词：Mac 自动弹出划词工具栏并支持首次按词扩选，Android 同样支持首次扩选。保留选择手柄供手动调整，并遵循整段选择设置。普通文字书仍与扫描版处理逻辑分离。
- E-Ink 模式关闭应用内导航、弹窗、翻页及动态加载等动画，使用清晰的实色样式；关闭 E-Ink 后恢复常规显示。
- 封面增加紧凑的书籍格式及扫描版标签，手动设置结果优先于自动识别。格式标签显示实际存储格式，TXT、Markdown 转换后的书籍可能显示 EPUB。
- 首页浮动导航改为半透明效果，滚动底部预留避让空间，最后一排书籍仍可完整查看及操作。
- 同步设置增加独立的对象存储标签页，提供 S3 兼容服务预设，包括阿里云 OSS、腾讯云 COS 等。保留已有 WebDAV 凭据和开关状态；切换服务不会自动迁移云端数据，请先备份。实际兼容性仍取决于所用端点和存储桶配置。
- 修复高亮、划线范围内的脚注链接被批注工具栏拦截；统一文件夹与书籍的更多按钮样式。
- 安卓阅读界面在封面过渡结束后初始化，减少开书时的并发负担；减少 AI 键盘变化时不必要的重建，修复键盘重复避让。实际帧率改善幅度尚待实机测量。
- 新增原生鸿蒙 ARM64 **未签名 HAP**，安装前需使用鸿蒙证书与 Profile 签名，不能沿用安卓 APK 签名。该包尚未完成鸿蒙实机验证。
- 关于、问题反馈及中英文项目文档加入 Telegram 频道与讨论群；QQ 交流入口改为可复制群号 **1009765685**，不再显示二维码。

[Telegram 频道](https://t.me/Modureader) · [Telegram 讨论群](https://t.me/ModuReaderDiscussion)

共 **9 个程序包**，各附 SHA-256：Android ARM64、iOS ARM64，macOS、Windows、Linux 的 ARM64／x64，以及鸿蒙 ARM64（未签名 HAP，需手动签名安装）；不发布安卓 x64。Mac 安装盘仅展示 Modu.app 和 Applications 快捷入口。

请先备份，再覆盖升级，不要先卸载或清空数据。Android 沿用原签名；macOS 为 ad-hoc 签名且未公证；Windows 需要 WebView2；Linux 面向 Debian 13；iOS 需自行签名主应用及 Share Extension。模型继续按需下载。

[对应源码](https://github.com/sobranie2406/modureader/tree/v1.2.2) · [1.2.1 至 1.2.2 源码差异](https://github.com/sobranie2406/modureader/compare/v1.2.1...v1.2.2) · [安装说明](https://github.com/sobranie2406/modureader/blob/v1.2.2/docs/RELEASING.md)
