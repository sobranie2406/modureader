# Modu 1.3.11

Build / 构建：**10189** · Stable / 正式版

### English

- Feat(pdf): View two PDF pages side by side, with separate cropping for each page. Image enhancement carries over when switching to continuous scroll.
- Feat(translation): Pretranslate the next 1–5 pages in reader translation and Classical Chinese translation. Continue into the next chapter when needed.
- Feat(reader): Assign “Open table of contents” to a custom tap zone. ([Issue #92](https://github.com/sobranie2406/modureader/issues/92)) Thanks [@chchoo](https://github.com/chchoo).
- Feat(plugins): Review permissions in plugin settings or grant them when prompted. Plugins can use their own data storage and request access to books, notes and search. ([PR #94](https://github.com/sobranie2406/modureader/pull/94)) Thanks [@RuizeSun](https://github.com/RuizeSun).
- Feat(linux): Add an AppImage for Arch Linux x64 alongside the Debian 13 packages. ([Issue #96](https://github.com/sobranie2406/modureader/issues/96)) Thanks [@boreascn](https://github.com/boreascn).
- Fix(pdf): Keep mouse-wheel panning within a zoomed PDF page from turning it accidentally. ([Issue #93](https://github.com/sobranie2406/modureader/issues/93)) Thanks [@peterblack111](https://github.com/peterblack111).
- Fix(translation): Restore skipped paragraphs at page breaks and keep page turns responsive while translations arrive.
- Fix(reader): Keep line spacing consistent on the page before an illustration.
- Fix(macos): Dismiss reader menus and lookup popups by clicking outside them.
- Fix(ios): Fix blank PDF pages on iPad and improve importing books from Files.
- Fix(harmony): Fix book imports from folders on HarmonyOS. ([Issue #95](https://github.com/sobranie2406/modureader/issues/95)) Thanks [@Keenwind](https://github.com/Keenwind).
- Fix(windows): Fix crashes when closing reader views or releasing audio on shutdown.

### 简体中文

- Feat(pdf): PDF 支持双页并排，两页可分别裁边，切换至连续卷轴后保留图像增强设置。
- Feat(translation): 阅读翻译和文言文翻译可预译后续 1～5 页，本章页数不足时接着译下一章。
- Feat(reader): 自定义翻页区域可设为「打开目录」。 ([Issue #92](https://github.com/sobranie2406/modureader/issues/92)) 感谢 [@chchoo](https://github.com/chchoo)。
- Feat(plugins): 可在插件设置里管理权限，也可在使用时按提示授权。插件有独立存储，可申请访问书籍、笔记和搜索。 ([PR #94](https://github.com/sobranie2406/modureader/pull/94)) 感谢 [@RuizeSun](https://github.com/RuizeSun)。
- Feat(linux): 新增面向 Arch Linux x64 的 AppImage，继续提供 Debian 13 安装包。 ([Issue #96](https://github.com/sobranie2406/modureader/issues/96)) 感谢 [@boreascn](https://github.com/boreascn)。
- Fix(pdf): 修复放大 PDF 后用鼠标滚轮移动页面时误触发翻页的问题。 ([Issue #93](https://github.com/sobranie2406/modureader/issues/93)) 感谢 [@peterblack111](https://github.com/peterblack111)。
- Fix(translation): 修复页末漏译和译文更新期间点击翻页失灵的问题。
- Fix(reader): 修复插画前一页行距过大的问题。
- Fix(macos): 点击阅读菜单或查询弹窗外侧即可关闭。
- Fix(ios): 修复 iPad 上打开 PDF 空白的问题，改善从「文件」导入书籍。
- Fix(harmony): 修复鸿蒙从文件夹导入书籍失败的问题。 ([Issue #95](https://github.com/sobranie2406/modureader/issues/95)) 感谢 [@Keenwind](https://github.com/Keenwind)。
- Fix(windows): 修复关闭阅读页面或退出时释放音频导致的崩溃。

### Downloads / 下载

Android ARM64 · iOS ARM64 · macOS ARM64 / x64 · Windows ARM64 / x64 · Debian 13 DEB ARM64 / x64 · Arch Linux x64 AppImage · HarmonyOS ARM64.

Each of the ten packages includes a SHA-256 checksum file. / 共十个安装包，各附 SHA-256 校验文件。

iOS IPA and HarmonyOS HAP require your own signing. macOS uses ad-hoc signing. Windows requires WebView2. See the installation guide for the AppImage runtime dependencies. / iOS IPA 和鸿蒙 HAP 需自行签名。macOS 使用临时签名。Windows 需要 WebView2。AppImage 的运行依赖见安装指南。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.3.11) · [Installation / 安装说明](https://github.com/sobranie2406/modureader/blob/v1.3.11/docs/RELEASING.md) · [License](https://github.com/sobranie2406/modureader/blob/v1.3.11/LICENSE) · [Notice](https://github.com/sobranie2406/modureader/blob/v1.3.11/NOTICE)
