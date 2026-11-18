# Modu 1.3.10

Build / 构建：**10182** · Stable / 正式版

### English

- Feat(reader): Add auto-scroll to standard reading and PDF/OCR reflow, with adjustable speed, e-ink scroll steps, a draggable control bar, and a stop timer up to 120 minutes. The screen stays awake while scrolling. Tap the page to recall the scroll or narration bar after it hides. ([Issue #84](https://github.com/sobranie2406/modureader/issues/84)) Thanks [@zhangxiaochang](https://github.com/zhangxiaochang).
- Fix(reader): Pause auto-scroll during a drag and resume from the new position when you let go. Improve cross-chapter scrolling and keep the current passage in view when reflow layout changes. ([Issue #88](https://github.com/sobranie2406/modureader/issues/88)) Thanks [@zhangxiaochang](https://github.com/zhangxiaochang).
- Feat(reader): Add swipe-to-highlight quick marking on mobile reflow pages. Connected marks can merge.
- Feat(plugins): Add a catalog of reviewed plugins with GitHub and Gitee sources. Install and update compatible plugins from settings, with an on-device mode for testing your own plugins. The optional Private Books plugin can hide or restore books and lock them with a passcode. Private books, their notes, and reading progress stay on the device.
- Feat(plugins): Save an article from a URL, preview its text as Markdown, then export it or add it to the bookshelf with the optional Web Read Later plugin.
- Feat(dictionary): Let the optional lookup plugin try English word forms, French elisions, and custom patterns after an exact lookup misses. ([Issue #83](https://github.com/sobranie2406/modureader/issues/83)) Thanks [@zhuhui-in](https://github.com/zhuhui-in).
- Feat(sync): Explain the counts and conflict options in the sync preview, add upload-only sync, and ask for confirmation again if the list of books to remove has changed. ([PR #86](https://github.com/sobranie2406/modureader/pull/86), [PR #87](https://github.com/sobranie2406/modureader/pull/87)) Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh).
- Fix(sync): Follow WebDAV redirects that add a trailing slash to WeRead and OCR metadata directories.
- Fix(reader): Preserve the paragraph's text size when a book displays a rare character as an inline image.
- Feat(search): Use downloaded local models for semantic search on all platforms, including HarmonyOS.
- Fix(ocr): Restore PDF text extraction, page and region rendering, and local OCR in HarmonyOS PDF reflow. ([Issue #85 discussion](https://github.com/sobranie2406/modureader/issues/85#issuecomment-6947843346)) Thanks [@gexiaoqing2009](https://github.com/gexiaoqing2009) and [@Keenwind](https://github.com/Keenwind).

### 简体中文

- Feat(reader): 普通阅读和 PDF／OCR 重排的滚动模式支持自动滚动，可调速度，适配电纸书分步滚动。浮动条可拖动，支持 0～120 分钟定时停止，滚动期间屏幕常亮。滚动和朗读浮动条闲置后收起，轻点页面可唤回。 ([Issue #84](https://github.com/sobranie2406/modureader/issues/84)) 感谢 [@zhangxiaochang](https://github.com/zhangxiaochang)。
- Fix(reader): 拖动页面时暂缓自动滚动，松手后从当前位置继续。改善跨章滚动衔接，并在重排布局变化后保留当前阅读位置。 ([Issue #88](https://github.com/sobranie2406/modureader/issues/88)) 感谢 [@zhangxiaochang](https://github.com/zhangxiaochang)。
- Feat(reader): 移动端重排页支持快速标记，划过文字即可高亮，相连的划线可合并。
- Feat(plugins): 设置里的插件页可从 GitHub 或 Gitee 安装和更新审核上架的插件，也提供本机开发调试入口。安装「私密书籍」插件后可隐藏、恢复书籍并设置密码，私密书籍、笔记和进度均留在本机。
- Feat(plugins): 「网页稍后阅读」插件可以提取网页正文，预览 Markdown，再导出或加入书架。
- Feat(dictionary): 安装「查词预处理」插件后，原词查不到时可尝试英语词形、法语省音形式和自定义规则。 ([Issue #83](https://github.com/sobranie2406/modureader/issues/83)) 感谢 [@zhuhui-in](https://github.com/zhuhui-in)。
- Feat(sync): 同步预览说明各项数量和冲突处理选项，新增「仅上传」模式。待移除书籍名单发生变化时，重新确认后才继续。 ([PR #86](https://github.com/sobranie2406/modureader/pull/86), [PR #87](https://github.com/sobranie2406/modureader/pull/87)) 感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh)。
- Fix(sync): 修复 WebDAV 给微信读书和 OCR 资料目录补上末尾斜杠时的同步错误。
- Fix(reader): 修复书内用行内图片显示生僻字时，所在段落字号异常的问题。
- Feat(search): 各平台的语义搜索使用下载到本机的模型，鸿蒙也支持本地推理。
- Fix(ocr): 修复鸿蒙 PDF 重排的文本提取、整页与局部取图，以及扫描页本地 OCR。 ([Issue #85 讨论](https://github.com/sobranie2406/modureader/issues/85#issuecomment-6947843346)) 感谢 [@gexiaoqing2009](https://github.com/gexiaoqing2009) 和 [@Keenwind](https://github.com/Keenwind)。

### Downloads / 下载

Android ARM64 · iOS ARM64 · macOS ARM64 / x64 · Windows ARM64 / x64 · Linux ARM64 / x64 · HarmonyOS ARM64.

Each of the nine packages includes a SHA-256 checksum file. / 共九个安装包，各附 SHA-256 校验文件。

iOS IPA and HarmonyOS HAP require your own signing. macOS uses ad-hoc signing. Windows requires WebView2. Linux DEB targets Debian 13. / iOS IPA 和鸿蒙 HAP 需自行签名。macOS 使用临时签名。Windows 需要 WebView2。Linux DEB 面向 Debian 13。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.3.10) · [Installation / 安装说明](https://github.com/sobranie2406/modureader/blob/v1.3.10/docs/RELEASING.md) · [License](https://github.com/sobranie2406/modureader/blob/v1.3.10/LICENSE) · [Notice](https://github.com/sobranie2406/modureader/blob/v1.3.10/NOTICE)
