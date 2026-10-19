# Modu 1.2.12

Build / 构建：**10150** · Stable / 正式版

### English

- Feat(reading): Add multiple reading rounds with per-round statistics, atomic round changes and undo; synchronize rounds and their reading time across devices with sync protocol v9. Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh) for [#46](https://github.com/sobranie2406/modureader/pull/46) and [#47](https://github.com/sobranie2406/modureader/pull/47).

- Feat(review): Add Markdown book reviews and independent cross-device synchronization, including edits and clearing. Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh) for [#48](https://github.com/sobranie2406/modureader/pull/48). All syncing devices must upgrade to 1.2.12 for protocol v9 compatibility.

- Feat(statistics): Add a daily check-in goal, defaulting to 10 minutes across all books; 0 minutes keeps the previous recorded-reading rule. Show today's progress and total qualified days, and recalculate history without changing reading records. Include the goal in settings backups and refresh after sync/settings changes. Thanks [@1Cookie2gavh](https://github.com/1Cookie2gavh) for [#49](https://github.com/sobranie2406/modureader/pull/49).

- Feat(tts): Highlight the current spoken sentence in text/OCR reflow using the ebook speech colour. Keep the highlight while paused and clear it on stop, page end or page change without changing selection, saved notes or page boundaries.

- Fix(tts): Enable the Android 13+ vivo/iQOO notification stop-button fallback in regular builds, retaining the media-session action and removing the card when stopped. Leave other vendors, older Android versions and existing play/pause routing unchanged.

- Fix(ocr): Accept validated integral page numbers returned as doubles by macOS WebView in shared text/OCR loading, restoring prefetch without replacing saved corrections. Add privacy-safe prefetch failure diagnostics.

- Feat(tts): Add page-local narration to text/OCR reflow, reusing speech providers, voice/rate settings, playback controls and the floating toolbar. Read only the displayed original page's saved/corrected reflow text; stop at its end and when switching pages or leaving reflow. Reflow speech state stays in this session and is never saved or synced; original PDF/scanned pages have no narration, and ordinary ebook narration and reading-progress sync are unchanged.

- Fix(reader): Route comparison keyboard controls to the active pane, restore focus to reflow after closing menus, and preserve text-selection and editor shortcuts without disabling original-page mouse gestures.

- Fix(reader): Prevent dragging original PDF/scanned pages from turning pages; enlarged-page arrow keys pan within the current page. Preserve per-page zoom/position through resize, fix rotated rectangle zoom and keep rectangle mode active until dismissed. Raise reading zoom to 8× and remove the duplicate zoom slider from Page settings. Ordinary ebook/reflow controls are unchanged.

- Feat(reader): Compare original PDF/scanned pages with reflow text above/below in portrait or side by side in landscape. Add comparison switches to Text/OCR tools, preserve each reader's controls, and follow original page numbers while reusing saved text and corrections.

- Fix(settings): Constrain and center font-download cards on wide screens, bound preview image height without cropping, and wrap links/download actions on narrow screens.

- Fix(reader): Reuse the existing reader menu heading component for the Text/Page tabs and match document submenu title fonts to it. Preserve existing sizes, weights, spacing, option fonts and reading fonts.

- Fix(statistics): Limit reading-history deletion and undo to the selected book and day/week/month/year, preserving records outside that interval when leaving statistics.

### 简体中文

- Feat(reading): 新增多轮阅读及分轮统计，支持原子切换轮次和撤销；通过 v9 同步协议跨设备同步轮次与阅读时长。感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh) 贡献 [#46](https://github.com/sobranie2406/modureader/pull/46)、[#47](https://github.com/sobranie2406/modureader/pull/47)。

- Feat(review): 新增 Markdown 书评及独立跨设备同步，支持修改与清空。感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh) 贡献 [#48](https://github.com/sobranie2406/modureader/pull/48)。参与同步的设备均需升级至 1.2.12，以兼容 v9 协议。

- Feat(statistics): 新增每日打卡目标，默认跨书累计阅读 10 分钟，设为 0 分钟可沿用有记录即打卡的规则；显示今日进度和累计达标天数，按当前目标重算历史但不修改原始记录。目标纳入设置备份，同步及设置变化后刷新统计。感谢 [@1Cookie2gavh](https://github.com/1Cookie2gavh) 贡献 [#49](https://github.com/sobranie2406/modureader/pull/49)。

- Feat(tts): 文字／OCR 重排朗读增加当前句高亮，沿用普通电子书朗读颜色；暂停保留，停止、读完或换页时清除，不改变文字选区、已有笔记及本页朗读边界。

- Fix(tts): 正式构建启用 Android 13 及以上 vivo／iQOO 通知退出键兼容处理，保留媒体会话停止操作，停止朗读后移除通知卡片；其他品牌、旧版 Android 及现有播放／暂停路径不变。

- Fix(ocr): 共用文字／OCR 加载兼容 macOS 网页返回的整数形式小数页码，严格校验后转换，修复预缓存失败；保留已有校对结果，并补充不含私人内容的预缓存失败诊断日志。

- Feat(tts): 文字／OCR 重排恢复本页朗读，复用语音服务、音色语速、播放控制与浮动栏；只朗读当前原书页对应的已保存／校对文字，读完停止，换页或退出重排时停止旧页朗读。朗读状态仅在当前会话有效，不保存、不参与跨设备同步；原版 PDF／扫描书不提供朗读，不改变普通电子书朗读及原有阅读进度同步。

- Fix(reader): 分屏对照键盘操作仅作用于当前面板；关闭菜单后恢复重排侧焦点，保留文字选择和编辑快捷键，不影响原页鼠标拖动。

- Fix(reader): PDF、自动识别及手动标记的扫描书原页拖动不再触发翻页；放大后方向键仅移动当前页画面。修正窗口变化打断每页缩放与位置保存、旋转后框选放大比例错误及框选模式提前退出；阅读缩放上限改为 8 倍，移除页面设置中的重复缩放条。普通电子书和重排阅读交互不变。

- Feat(reader): PDF／扫描书原页与重排文字支持分屏对照，竖屏上下、横屏左右；文字与 OCR 工具提供开关，两侧保留各自阅读功能，按原书页码联动并复用已保存文字和校对稿。

- Fix(settings): 下载字体页在宽屏居中限宽，预览图限制高度且完整显示，窄屏链接及下载操作自动换行。

- Fix(reader): “文字／页面”标签页复用旧阅读菜单标题组件，文档二级菜单标题统一沿用其衬线字体；保留各层原有字号、字重、间距、选项字体和阅读正文字体。

- Fix(statistics): 阅读记录删除与撤销限定为所选书籍及当天／周／月／年，离开统计页面时不再误删其他日期的历史记录。

## Downloads / 下载

Nine packages, each with a SHA-256 checksum / 九个平台安装包及各自 SHA-256 校验文件：

- Android ARM64 — APK
- macOS ARM64 / x64 — DMG
- Windows ARM64 / x64 — EXE installer / 安装程序
- Linux ARM64 / x64 — DEB (Debian 13)
- iOS ARM64 — unsigned IPA / 未签名 IPA
- HarmonyOS ARM64 — unsigned native HAP / 未签名原生 HAP

Back up first, then upgrade without uninstalling or clearing your library. Android retains the project signing key. macOS is ad-hoc signed and not notarized. Windows requires WebView2. Linux targets Debian 13. iOS requires your own signing for the app and Share Extension; HarmonyOS requires a valid local certificate/profile. Models are downloaded or imported separately, not bundled.

建议先备份，再覆盖升级，不要卸载或清空书库。安卓沿用项目签名；macOS 为临时签名、未公证；Windows 需要 WebView2；Linux 面向 Debian 13；iOS 应用及分享扩展需自行签名，鸿蒙 HAP 需使用有效证书和配置签名安装。模型按需下载或离线导入，不内嵌安装包。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.2.12) · [Changes / 变更](https://github.com/sobranie2406/modureader/compare/v1.2.11...v1.2.12) · [Licenses / 许可](https://github.com/sobranie2406/modureader/blob/v1.2.12/NOTICE)
