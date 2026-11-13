# Modu 1.3.9

Build / 构建：**10177** · Stable / 正式版

### English

- Feat(books): Read original files and folders in place, with read-only access, source badges, relinking and conversion to internal copies. Keep notes and reading progress when switching sources. Reading data continues to sync while linked originals stay on the device.

- Feat(search): Choose Books, Notes or both from bookshelf search. Keep current-book note searches within that book, and place the history layout editor beside the date. ([PR #82](https://github.com/sobranie2406/modureader/pull/82)) Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh).

- Feat(pdf): Zoom PDF pages with Ctrl + mouse wheel on Windows/Linux or Command + mouse wheel on macOS. In comparison mode, this zooms the original PDF while keeping the comparison text size. ([Issue #81](https://github.com/sobranie2406/modureader/issues/81)) Thanks [@gexiaoqing2009](https://github.com/gexiaoqing2009).

- Fix(reader): Use compact AI dialogs and speech-bubble pointers on adjustable windows, with rounded corners and a fixed source anchor while dragging. Keep the text beneath menus and dialogs undimmed.

- Fix(reader): Apply reading brightness consistently to dictionary, query and AI content dialogs, including embedded webpages, without applying the dimming twice.

- Fix(reader): Fix line-spacing adjustments and overlapping footnote text.

- Feat(sync): With automatic sync on and sync preview confirmation off, sync once when the app enters the background and once when it returns, including after unlocking. Save the current reading and narration positions before syncing.

- Fix(sync): Support dufs servers that offer Basic and Digest authentication together, fixing WebDAV connection tests and synchronization failures. ([Issue #80](https://github.com/sobranie2406/modureader/issues/80)) Thanks [@91zgaoge](https://github.com/91zgaoge).

- Fix(sync): Handle S3 directory names and prefixes containing spaces or percent signs, improving RustFS compatibility. ([Issue #78](https://github.com/sobranie2406/modureader/issues/78)) Thanks [@daxiguadev](https://github.com/daxiguadev).

- Fix(settings): Use normal input types for WebDAV addresses and usernames.

- Feat(settings): Add an automatic update-check switch in Advanced, enabled by default, and use a standard settings page for About Modu. Show release notes only once per installed version.

### 简体中文

- Feat(books): 新增文件与文件夹原位读取，原文件只读，支持来源标签、重新关联和转为内部副本，切换来源保留笔记与进度。阅读资料继续同步，原位原书保留在本设备。

- Feat(search): 书架搜索可选择书籍、笔记或两者一起搜索，本书笔记搜索限定在当前书籍；历史布局编辑按钮移到日期旁。 ([PR #82](https://github.com/sobranie2406/modureader/pull/82)) 感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh)。

- Feat(pdf): Windows／Linux 支持 Ctrl＋鼠标滚轮缩放 PDF，macOS 使用 Command＋鼠标滚轮；对照阅读仅缩放 PDF 原文，对照文字字号保持原样。 ([Issue #81](https://github.com/sobranie2406/modureader/issues/81)) 感谢 [@gexiaoqing2009](https://github.com/gexiaoqing2009)。

- Fix(reader): AI 弹窗改为紧凑布局，可移动弹窗使用四周圆角和气泡小尖角，拖动时保留原文锚点；菜单和弹窗下方的文字保持原有明暗。

- Fix(reader): 字典、查询、AI 等内容弹窗及内嵌网页统一跟随阅读亮度，修复部分内容过亮或重复变暗。

- Fix(reader): 修复行距调节不生效及注释文字重叠，改善正文和注释排版。

- Feat(sync): 开启自动同步并关闭同步前预览确认后，切入后台、返回前台各同步一次，解锁返回也会触发；同步前保存当前页面和朗读位置。

- Fix(sync): 兼容 dufs 同时提供 Basic 和 Digest 认证，修复 WebDAV 连接测试及同步报错。 ([Issue #80](https://github.com/sobranie2406/modureader/issues/80)) 感谢 [@91zgaoge](https://github.com/91zgaoge)。

- Fix(sync): 修复 S3 目录名称及前缀含空格、百分号时的读取错误，改善 RustFS 同步兼容。 ([Issue #78](https://github.com/sobranie2406/modureader/issues/78)) 感谢 [@daxiguadev](https://github.com/daxiguadev)。

- Fix(settings): WebDAV 地址和用户名改用普通输入类型，避免触发密码键盘。

- Feat(settings): 高级设置新增「自动检查更新」开关，默认开启；「关于默读」改为常规设置页，更新说明每个安装版本只显示一次。

### Downloads / 下载

Android ARM64 · iOS ARM64 · macOS ARM64 / x64 · Windows ARM64 / x64 · Linux x64 / ARM64 · HarmonyOS ARM64.

Nine architecture-specific packages, each with a SHA-256 sidecar. Existing automatic-update filenames are preserved. / 共九个分架构安装包，均提供 SHA-256 校验文件，沿用原有自动更新文件名。

iOS IPA and HarmonyOS HAP require your own signing. macOS uses ad-hoc signing without notarization; Windows has no commercial Authenticode signature and requires WebView2. Linux DEB targets Debian 13. / iOS IPA 与鸿蒙 HAP 需自行签名；macOS 为临时签名、未公证；Windows 无商业 Authenticode 签名，需 WebView2；Linux DEB 面向 Debian 13。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.3.9) · [Installation / 安装说明](https://github.com/sobranie2406/modureader/blob/v1.3.9/docs/RELEASING.md) · [License](https://github.com/sobranie2406/modureader/blob/v1.3.9/LICENSE) · [Notice](https://github.com/sobranie2406/modureader/blob/v1.3.9/NOTICE)
