# Modu 1.3.8

Build / 构建：**10175** · Stable / 正式版

### English

- Fix(reader): Improve older WebView compatibility for chapter loading, page turns, highlights and footnotes.

- Fix(tts): Apply local speed control to OpenAI-compatible speech; support independent pitch on Android and macOS.

- Feat(notes): Search excerpts, comments and chapter names across all notes or within the current book.

- Feat(reader): Place adjustable AI windows and footnotes near their source text when popup movement and resizing is enabled. ([Issue #75](https://github.com/sobranie2406/modureader/issues/75)) Thanks [@gexiaoqing2009](https://github.com/gexiaoqing2009).

- Fix(bookshelf): Keep folder cover density consistent across phone layouts.

- Feat(ocr): Add PP-OCRv6 Small as the default and Medium as a higher-accuracy option, retain v5, and provide Gitee model mirrors.

- Feat(dictionary): Add a copy button beneath each dictionary result.

- Fix(reader): Limit brightness adjustments to book content and content dialogs; keep menus and non-reading pages at system brightness in both themes.

- Feat(reader): Set header and footer fonts, colours and opacity independently, with reset controls.

- Feat(plugins): Preview plugin packages before installation and preserve registered dictionary, toolbar and reading actions. ([PR #72](https://github.com/sobranie2406/modureader/pull/72)) Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Fix(appearance): Refresh linked reading colours after palette, system brightness and scheduled theme changes; fix the fine-tune dialog layout. ([PR #76](https://github.com/sobranie2406/modureader/pull/76)) Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Docs(ui): Shorten guidance and move detailed instructions into question-mark popovers.

### 简体中文

- Fix(reader): 完善旧版 WebView 的章节加载、翻页、高亮和注释兼容。

- Fix(tts): OpenAI 兼容朗读支持本地语速调节，安卓和 macOS 支持独立音调调节。

- Feat(notes): 支持在全部笔记或当前书籍中搜索摘录、批注和章节名称。

- Feat(reader): 开启弹窗移动与缩放后，AI 小窗和注释框贴近原文显示。 ([Issue #75](https://github.com/sobranie2406/modureader/issues/75)) 感谢 [@gexiaoqing2009](https://github.com/gexiaoqing2009).

- Fix(bookshelf): 统一手机文件夹内的封面布局密度。

- Feat(ocr): 新增 PP-OCRv6 Small 默认模型及 Medium 高精度选项，保留 v5，提供 Gitee 模型镜像。

- Feat(dictionary): 每条字典释义下方新增复制按钮。

- Fix(reader): 深浅色模式均仅调整书籍及内容对话框亮度，菜单和非阅读界面保持系统亮度。

- Feat(reader): 页眉页脚支持独立设置字体、颜色和深浅，并可恢复默认。

- Feat(plugins): 插件安装前可预览内容，完善字典、划词工具栏和阅读动作的注册与恢复。 ([PR #72](https://github.com/sobranie2406/modureader/pull/72)) 感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Fix(appearance): 配色微调、系统明暗和定时主题变化后刷新联动的书页配色，修复微调窗口布局。 ([PR #76](https://github.com/sobranie2406/modureader/pull/76)) 感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Docs(ui): 精简界面说明，将详细操作指导收进问号弹层。

### Downloads / 下载

Android ARM64 · iOS ARM64 · macOS ARM64 / x64 · Windows ARM64 / x64 · Linux x64 / ARM64 · HarmonyOS ARM64.

Nine architecture-specific packages, each with a SHA-256 sidecar. Existing automatic-update filenames are preserved. / 共九个分架构安装包，均提供 SHA-256 校验文件，沿用原有自动更新文件名。

iOS IPA and HarmonyOS HAP require your own signing. macOS uses ad-hoc signing without notarization; Windows has no commercial Authenticode signature and requires WebView2. Linux DEB targets Debian 13. / iOS IPA 与鸿蒙 HAP 需自行签名；macOS 为临时签名、未公证；Windows 无商业 Authenticode 签名，需 WebView2；Linux DEB 面向 Debian 13。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.3.8) · [Installation / 安装说明](https://github.com/sobranie2406/modureader/blob/v1.3.8/docs/RELEASING.md) · [License](https://github.com/sobranie2406/modureader/blob/v1.3.8/LICENSE) · [Notice](https://github.com/sobranie2406/modureader/blob/v1.3.8/NOTICE)
