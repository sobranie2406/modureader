# Modu 1.2.3 · Stable

## English

**Modu 1.2.3 (build 10090)** — changes since stable **1.2.2**.

- Fix(sync): Recognize S3 directory placeholder objects as existing directories without treating them as child files, preventing false missing-directory results during synchronization.
- Fix(sync): Request literal listing names from RainYun ROS to preserve spaces, plus signs and Unicode object keys; keep other S3 providers' URL-encoded listings and WebDAV behavior unchanged.
- Feat(history): Rename Statistics to Reading History with a history icon; open available books by tapping their title or cover and show a clear notice for deleted books without removing reading records.
- Feat(history): Add rearrangeable Recently read, This week, Daily reading average and Most annotated cards, with reading-date, progress, activity and annotation labels.
- Fix(l10n): Translate the bookshelf's indexed badge according to the interface language instead of always displaying Chinese.
- Feat(reader): Add Original / Simplified / Traditional Chinese conversion beside the Chinese font selector, using the existing reading conversion preference without rewriting book files.
- Feat(android): Expand the shelf thumbnail and turn the cover outward around its left spine when opening a book; reverse the sequence on return. Keep the native reader outside the animated cover and initialize it immediately. E-Ink and disabled-animation settings still bypass motion.
- Perf(android): Reduce reader platform-view and AI stream/layout contention; preserve drafts and focus, apply keyboard avoidance once, and retain manual scrolling during long responses. Device results vary; sustained smoothness is not guaranteed.
- Fix(tts): Release stalled system-TTS waits on native errors or pre-start timeout, preserve the current sentence for retry, and keep long utterances unrestricted once speech has started.
- Fix(tts): Report delayed or failed reader/backend/audio-focus startup without logging book text or credentials; handle narration-panel startup errors and disposed readers safely. The reported iQOO Wi-Fi-specific failure remains unconfirmed on the original device.
- Feat(tts): Add online lookahead, synthesis-size and concurrency controls, paragraph pauses, audio-cache retention and cache clearing. Defaults are 3 extra passages, 240 characters, 2 concurrent requests, no extra pause and 10-minute retention; system TTS keeps its own engine-managed behavior.
- Fix(tts): Bound reusable audio cache to 32 MiB, expire idle entries, clear on stop when retention is 0, and prevent late requests from undoing cache clearing. Retry timed-out shared synthesis with a fresh request.
- Feat(settings): Include online speech buffering preferences in existing settings export/import and optional provider-settings sync; accept old exports with safe defaults.

**Packages:** 9 installers and 9 SHA-256 files: Android ARM64; iOS ARM64; macOS, Windows and Linux ARM64/x64; HarmonyOS ARM64. No Android x64. Mac DMGs contain only Modu.app and the Applications shortcut.

**Installation:** Back up and upgrade in place; do not uninstall or clear the library first. Android retains the project signing key. macOS uses ad-hoc signing and is not notarized. Windows requires WebView2; Linux targets Debian 13. iOS requires your own signing for the app and Share Extension. The HarmonyOS HAP is unsigned, requires a valid HarmonyOS certificate/profile, and is not yet device-validated. Models remain on-demand downloads.

[Source](https://github.com/sobranie2406/modureader/tree/v1.2.3) · [Changes since 1.2.2](https://github.com/sobranie2406/modureader/compare/v1.2.2...v1.2.3) · [Installation guide](https://github.com/sobranie2406/modureader/blob/v1.2.3/docs/RELEASING.md)

---

## 简体中文

**Modu 1.2.3（构建 10090）**，以下为 **1.2.2 正式版以来**的变化。

- Fix(sync): 正确识别 S3 目录占位对象，不将其作为子文件，修复同步时将有内容的目录误判为不存在的问题。
- Fix(sync): 雨云 ROS 改为请求原始列举名称，正确保留空格、加号及 Unicode 对象名；其他 S3 服务仍使用原 URL 编码流程，WebDAV 行为不变。
- Feat(history): “统计”改为“阅读历史”并更换图标，点击书名或封面可打开仍在书库中的书籍；已删除书籍给出明确提示，保留阅读记录。
- Feat(history): 增加可自由排列的“最近阅读”“本周阅读回顾”“阅读日均时长”“笔记最多的书”卡片，显示阅读日期、进度、活跃天数及笔记数量等标签。
- Fix(l10n): 书架“已索引”标签随界面语言显示，不再在英文界面固定显示中文。
- Feat(reader): 中文字体旁增加“原文／简体／繁体”快捷切换，沿用已有阅读转换设置，不改写书籍源文件。
- Feat(android): 开书时由书架缩略图放大，再沿左侧书脊向外翻开，返回时反向收起；正文视图不参与封面变形并立即初始化。E-Ink 和关闭动画时仍无过渡动画。
- Perf(android): 减少阅读视图与 AI 流式输出、布局之间的重复负担，保留输入草稿与焦点，避免键盘重复避让，长回答中保留手动滚动。不同设备效果有差异，不承诺始终无掉帧。
- Fix(tts): 系统 TTS 原生报错或启动超时时及时结束等待，保留当前句供重试；已经开始的长段朗读不受启动超时限制。
- Fix(tts): 增加正文获取、引擎及音频焦点启动延迟和失败诊断，不记录书籍正文或凭据；安全处理朗读面板启动失败及阅读器关闭。反馈中的 iQOO 特定 Wi-Fi 故障尚未在原设备确认根因。
- Feat(tts): 增加在线朗读缓冲量、合成字数、并发数、段落停顿、缓存保留时间及清理功能。默认额外缓冲 3 段、单次最多 240 字、并发 2、无额外停顿、保留 10 分钟；系统 TTS 仍由设备引擎管理。
- Fix(tts): 可复用音频缓存限制为 32 MiB，支持空闲过期、保留时间为 0 时停止清理，清理前发出的请求不会回填旧缓存；共享合成请求超时后可重新发起请求。
- Feat(settings): 在线朗读缓冲参数纳入已有设置导入导出及可选的服务配置同步，兼容缺少新字段的旧配置。

**发布包：**9 个程序包及 9 个 SHA-256 文件：Android ARM64、iOS ARM64、macOS／Windows／Linux ARM64 与 x64、HarmonyOS ARM64。不发布安卓 x64；Mac 安装盘仅展示 Modu.app 与 Applications 快捷入口。

**安装提醒：**先备份再覆盖升级，不要先卸载或清空书库。Android 沿用原签名；macOS 为 ad-hoc 签名且未公证；Windows 需要 WebView2，Linux 面向 Debian 13。iOS 需自行签名主应用及 Share Extension。鸿蒙 HAP 未签名，需使用有效鸿蒙证书与 Profile 签名，尚未完成鸿蒙实机验证。模型继续按需下载。

[对应源码](https://github.com/sobranie2406/modureader/tree/v1.2.3) · [1.2.2 至 1.2.3 源码差异](https://github.com/sobranie2406/modureader/compare/v1.2.2...v1.2.3) · [安装说明](https://github.com/sobranie2406/modureader/blob/v1.2.3/docs/RELEASING.md)
