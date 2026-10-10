# Modu 1.2.5 · Stable

## English

**Modu 1.2.5 (build 10102)** — changes since stable **1.2.4**.

- Feat(lookup): Add the default-enabled Lookup selection tool. Its overview queries dictionaries, encyclopedia, translation and AI Knowledge automatically, with independent source switches, adaptive cards and settings links. Book AI, Classical Chinese translation and Web search remain separate tabs; existing standalone tools remain available, disabled by default.
- Feat(dictionary): Query one or several local dictionaries, show sources and explicit no-entry results, and offer optional Chinese/English Wiktionary with attribution. Remove Free Dictionary API.
- Feat(dictionary): Display original MDX HTML, images, audio and script-generated entries inline using imported MDD/local resources. Originals run in an isolated local view without an app bridge or external network access; audio requires user interaction. Older text-only imports need reimporting for original resources. MDX 3 remains unsupported.
- Perf(lookup): Tighten dictionary typography and spacing, size cards to their contents and avoid duplicating original and plain-text results. Very long originals scroll within a capped view.
- Feat(ai): Prefill Book AI with selected text, retain context choices, edit-before-send and follow-up questions, and hide reading-skill controls in Classical Chinese translation.
- Feat(keyboard): Add customizable reader shortcuts for desktop and Android hardware keyboards, with multiple bindings, conflict checks, settings backup and restore defaults. Play/pause uses one key, P by default; previous/next paragraph controls are also supported.
- Fix(bookshelf): Long-press enters multi-selection instead of a sticky action menu. Keep three-dot menus and add shared batch create-folder, move and delete actions in the shelf and opened folders.
- Fix(reader): Use the shared cover-opening transition when opening books from folders or Reading History, respecting disabled-animation and E-Ink preferences; improve long chapter-title layout.
- Feat(notifications): Use temporary rounded pill notifications for downloads and other status messages across platforms.
- Fix(tts): Add previous/next paragraph arrows and preserve playing or paused state during navigation. Shorten the Chinese labels for return-to-narration and start-from-page controls.
- Fix(tts): Recognize additional publisher footnote markers so their numbers are not narrated, without stripping ordinary numeric links.
- Fix(tts): Classify synthesis failures across online engines, validate MiMo audio responses, retry transient failures with bounded backoff and server cooldown handling, and improve privacy-safe diagnostics. Stop or configuration changes cancel pending retries; configuration and permanent HTTP failures are not repeatedly retried.
- Ci(harmony): Update the isolated HarmonyOS reorder-callback adapter for the revised selection-tool settings.
- Docs(features): Refresh the bilingual settings, feature and privacy guides, Chinese-default homepage and fictional bookshelf badge showcase.

**Packages:** 9 installers and 9 SHA-256 files: Android ARM64; iOS ARM64; macOS, Windows and Linux ARM64/x64; HarmonyOS ARM64. No Android x64. Mac DMGs contain only Modu.app and the Applications shortcut.

**Installation:** Back up and upgrade in place; do not uninstall or clear the library first. Android retains the project signing key. macOS uses ad-hoc signing and is not notarized. Windows requires WebView2; Linux targets Debian 13. iOS requires your own signing for the app and Share Extension. The HarmonyOS HAP is unsigned, requires a valid HarmonyOS certificate/profile, and is not yet device-validated. Models remain on-demand downloads.

**Validation scope:** Automated regressions cover the changed query, dictionary, selection, keyboard and narration paths. Android preview checks and local Android/macOS package checks do not constitute acceptance on every platform, keyboard, voice provider or third-party dictionary. Online services may charge for requests; import only dictionary resources you are entitled to use.

[Source](https://github.com/sobranie2406/modureader/tree/v1.2.5) · [Changes since 1.2.4](https://github.com/sobranie2406/modureader/compare/v1.2.4...v1.2.5) · [Installation guide](https://github.com/sobranie2406/modureader/blob/v1.2.5/docs/RELEASING.md)

---

## 简体中文

**Modu 1.2.5（构建 10102）**，以下为 **1.2.4 正式版以来**的变化。

- Feat(lookup): 新增默认开启的划词「综合」入口，汇总页自动查询字典、百科、翻译和 AI 知识，支持独立来源开关、内容自适应卡片及设置入口。本书 AI、文言文翻译、联网搜索使用独立标签；原有单独工具保留，默认关闭。
- Feat(dictionary): 本地词典可单选或多选查询，显示来源及明确的「词典名 · 无条目」结果；可选用带来源标注的中英文维基词典，移除 Free Dictionary API。
- Feat(dictionary): 导入 MDX 及配套 MDD／本地资源后，直接内嵌显示原版 HTML、图片、音频与脚本生成词条。原版视图与应用桥接和外部网络隔离，音频需主动操作；旧的纯文字导入需重新导入才能补齐原版资源，暂不支持 MDX 3。
- Perf(lookup): 缩小字典字号与留白，结果卡片随内容适配，避免原版与纯文字重复展示；过长原版内容在限高视图内滚动。
- Feat(ai): 本书 AI 自动填入选中文字，保留上下文选择、先编辑再发送和继续提问；文言文翻译隐藏阅读技能控件。
- Feat(keyboard): 桌面与安卓实体键盘新增自定义阅读按键，支持多个绑定、冲突检查、设置备份及恢复默认。播放／暂停使用同一个按键，默认 P；支持上一段／下一段。
- Fix(bookshelf): 长按封面改为多选，不再打开难以关闭的操作菜单。保留三个点菜单，书架与文件夹内统一支持批量建立文件夹、移入和删除。
- Fix(reader): 从书架文件夹和阅读历史开书时沿用统一封面过渡，遵循关闭动画与 E-Ink 设置；改善长章节标题的排版。
- Feat(notifications): 下载完成等状态提示统一使用短暂显示、自动消失的圆角椭圆提示框，适用于各平台。
- Fix(tts): 朗读浮动栏增加上一段／下一段箭头，跳转时保留播放或暂停状态；定位按钮文案改为「回朗读页」「此页开始」。
- Fix(tts): 补齐出版物注释标记识别，避免朗读注释序号，同时保留普通数字链接的正文。
- Fix(tts): 在线语音引擎统一分类合成失败，校验 MiMo 音频响应，对临时错误进行有限退避重试并遵循服务端冷却；增强不包含正文和密钥的诊断日志。停止朗读或修改配置会取消重试，不反复重试配置及永久 HTTP 错误。
- Ci(harmony): 更新独立鸿蒙构建中的排序回调适配，兼容新版划词工具设置。
- Docs(features): 更新中英设置、功能与隐私说明，首页默认中文，并使用虚构书库展示索引及格式标签。

**安装包：**9 个程序包及 9 个 SHA-256 校验文件：Android ARM64、iOS ARM64、macOS／Windows／Linux 的 ARM64 与 x64，以及 HarmonyOS ARM64。不发布 Android x64；Mac DMG 只包含 Modu.app 和 Applications 快捷入口。

**安装：**建议先备份再覆盖升级，不要先卸载或清空书库。Android 沿用项目签名；macOS 为临时签名，未公证。Windows 需要 WebView2，Linux 面向 Debian 13。iOS 需自行签名应用和分享扩展。HarmonyOS HAP 未签名，需有效鸿蒙证书／Profile 后签名安装，尚未完成鸿蒙实机验证。模型仍按需下载。

**验证范围：**自动回归覆盖综合查询、字典、选择操作、快捷键及朗读修改；安卓预览版检查和本地安卓／Mac 包检查，不代表每个平台、实体键盘、语音服务和第三方词典均完成验收。在线查询可能产生服务费用；请仅导入有权使用的词典资源。

[对应源码](https://github.com/sobranie2406/modureader/tree/v1.2.5) · [1.2.4 至 1.2.5 源码差异](https://github.com/sobranie2406/modureader/compare/v1.2.4...v1.2.5) · [安装说明](https://github.com/sobranie2406/modureader/blob/v1.2.5/docs/RELEASING.md)
