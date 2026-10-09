# Modu 1.2.4 · Stable

## English

**Modu 1.2.4 (build 10093)** — changes since stable **1.2.3**.

- Feat(import): Import text UMD books with chapters, metadata and supported covers, converting them to EPUB for reading and synchronization. Image/comic UMD is not supported.
- Fix(bookshelf): Show TXT, MD and UMD source-format badges and book details after conversion; retain stored EPUB paths and content checksums used by synchronization.
- Feat(reader): Apply the expanding, outward-opening cover transition across platforms, with the reader mounted at its final size; preserve iOS edge-swipe return and E-Ink/disabled-animation preferences.
- Fix(ios): Refresh the selection menu after dragging native selection handles, so copying and marking use the updated range rather than the initially selected word.
- Fix(remote-library): Read large WebDAV directory listings in a background worker, increase the listing limit to 32 MiB, skip individual malformed encoded entries and show directory-specific errors.
- Feat(remote-library): Import the current remote folder or a folder from its menu, including subfolders; select compatible books before sequential downloads, with duplicate checks, progress and cancellation.
- Perf(remote-library): Throttle download progress updates and reuse sorted/filtered lists during folder imports to reduce repeated UI work.
- Fix(reader): Restore MOBI note popups only when legacy note lists and superscript icons match; recognize AZW3 note types and explicit embedded note text, hiding duplicate inline notes while retaining ambiguous content.
- Docs(features): Update the bilingual feature and settings guides for UMD, original-format badges, remote folder imports, shared cover transitions and note compatibility.

**Packages:** 9 installers and 9 SHA-256 files: Android ARM64; iOS ARM64; macOS, Windows and Linux ARM64/x64; HarmonyOS ARM64. No Android x64. Mac DMGs contain only Modu.app and the Applications shortcut.

**Installation:** Back up and upgrade in place; do not uninstall or clear the library first. Android retains the project signing key. macOS uses ad-hoc signing and is not notarized. Windows requires WebView2; Linux targets Debian 13. iOS requires your own signing for the app and Share Extension. The HarmonyOS HAP is unsigned, requires a valid HarmonyOS certificate/profile, and is not yet device-validated. Models remain on-demand downloads.

**Validation:** Automated reader/import regressions and comparisons against three local EPUB/MOBI/AZW3 editions cover the changed behavior. These checks do not establish device acceptance on every platform. Ambiguous MOBI notes remain visible instead of being guessed or removed.

[Source](https://github.com/sobranie2406/modureader/tree/v1.2.4) · [Changes since 1.2.3](https://github.com/sobranie2406/modureader/compare/v1.2.3...v1.2.4) · [Installation guide](https://github.com/sobranie2406/modureader/blob/v1.2.4/docs/RELEASING.md)

---

## 简体中文

**Modu 1.2.4（构建 10093）**，以下为 **1.2.3 正式版以来**的变化。

- Feat(import): 支持文字版 UMD 导入，保留章节、元数据和支持的封面，转换为 EPUB 后沿用阅读及同步流程；暂不支持图片／漫画 UMD。
- Fix(bookshelf): TXT、MD、UMD 转换后仍显示原始格式标签及书籍详情，同步继续使用实际存储的 EPUB 路径和内容校验值。
- Feat(reader): 各平台统一采用封面放大、向外翻开的开书过渡，正文在最终尺寸下初始化；保留 iOS 侧滑返回及 E-Ink／关闭动画设置。
- Fix(ios): 拖动系统选区手柄后及时更新选词菜单，复制和标注使用调整后的范围，不再停留在首次选中的词语。
- Fix(remote-library): 大型 WebDAV 目录在后台解析，目录响应上限提高至 32 MiB，跳过单条编码异常记录，并显示针对目录的错误信息。
- Feat(remote-library): 支持从当前远程目录或文件夹菜单批量导入，包含子文件夹；下载前勾选兼容书籍，依次下载，提供重复检查、进度及取消操作。
- Perf(remote-library): 限制下载进度刷新频率，复用排序和筛选结果，减少远程文件夹导入时的重复界面计算。
- Fix(reader): 仅在旧式注释列表与上标图标匹配时恢复 MOBI 注释弹窗；补齐 AZW3 注释类型及明确内嵌注释文字的识别，隐藏重复显示的注释，保留无法可靠判定的内容。
- Docs(features): 更新中英文功能与设置指南，补充 UMD、原格式标签、远程文件夹导入、全平台封面过渡和注释兼容说明。

**安装包：**9 个程序包及 9 个 SHA-256 校验文件：Android ARM64、iOS ARM64、macOS／Windows／Linux 的 ARM64 与 x64，以及 HarmonyOS ARM64。不发布 Android x64；Mac DMG 只包含 Modu.app 和 Applications 快捷入口。

**安装：**建议先备份再覆盖升级，不要先卸载或清空书库。Android 沿用项目签名；macOS 为临时签名，未公证。Windows 需要 WebView2，Linux 面向 Debian 13。iOS 需自行签名应用和分享扩展。HarmonyOS HAP 未签名，需有效的鸿蒙证书／Profile 后签名安装，尚未完成鸿蒙实机验证。模型仍按需下载。

**验证范围：**已对修改部分进行阅读器、导入自动回归测试，并核对本地三份 EPUB／MOBI／AZW3 样书；这些检查不代表所有平台均完成实机验收。无法可靠配对的 MOBI 注释保留原文，不猜测或删除。

[对应源码](https://github.com/sobranie2406/modureader/tree/v1.2.4) · [1.2.3 至 1.2.4 源码差异](https://github.com/sobranie2406/modureader/compare/v1.2.3...v1.2.4) · [安装说明](https://github.com/sobranie2406/modureader/blob/v1.2.4/docs/RELEASING.md)
