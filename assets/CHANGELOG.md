# Modu changelog

Latest stable: **1.2.12+10150**. Updated 2026-10-19.

[Settings](../docs/SETTINGS.md) · [中文设置指南](../docs/SETTINGS_zh.md) · [Published releases](https://github.com/sobranie2406/modureader/releases)

Older sections retain their original version scope; they are not current acceptance reports.

## 1.2.12

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

## 1.2.11

### English

- Feat(settings): Use direct choices for crop scope, vector/OCR model download sources and the update source. Expose TXT export directly in the document Text menu; keep page editing in reflow/extraction tools, preserving cached corrections and existing source behavior.

- Fix(ocr): Keep source-page prefetch running in text/OCR reflow, update its window only when the original page changes, and reuse in-flight recognition before starting foreground work. Show cache progress in reflow tools without cancelling background rendering when leaving cached text.

- Feat(ocr): Sync saved page text, corrections and immutable annotation revisions with downloaded original books over the configured book-sync service. Remote-only books do not fetch OCR caches; downloading the original also retrieves its cache. Match by source-file checksum rather than local book ID or title, merge page results, retain conflicting revisions, and verify uploads before compacting older snapshots.

- Feat(ocr): Use a 1–5 page minus/plus cache control and count saved OCR and corrections as processed pages in cache progress.

- Fix(ocr): Scan saved OCR/corrections before scheduling and process missing pages only. Let an in-flight page finish across touches, scrolling and page turns instead of repeatedly cancelling it; keep foreground OCR, backgrounding and exit cancellation. Shorten the idle scheduling delay and display current-page recognition progress.

- Fix(pdf): Keep the crop preview pinned above independently scrolling options, with illustrated grid choices instead of a dropdown. Start OCR prefetch for original-page reading without crop metadata; bound the queue at the last page, retry transient failures and show cached-page counts or missing-model errors.

- Feat(ios): Add opt-in volume-change paging through the existing reader key bridge, with route, dialog and foreground guards. Keep system volume and TTS audio-session ownership unchanged. This compatibility listener cannot distinguish physical keys from other volume changes or detect repeated presses at volume limits; real-device verification is pending.

- Feat(pdf): Add opt-in, serial background text/OCR prefetch for the current page and up to four following pages, preserving saved corrections. Merge automatic text/OCR reflow and restore ebook reflow controls. Move extraction tools below the preview and crop-reading controls into the crop editor; simplify page options. Make the 80%-transparent zoom bar draggable with a five-second idle timeout, and allow taps on enlarged pages without treating them as drags.

- Feat(pdf): Group the reader menu into Contents, Notes, Text, Page and the existing Brightness panel. Retain region extraction, continuous OCR, cached edits and TXT export; group crop, fit, rotation, page turning and image enhancement under Page. Add 1–4× pinch zoom, desktop rectangle zoom, panning and per-page viewport memory using bounded image rendering. Screen rotation updates the reader viewport and fit width together.

- Fix(harmony): Use the native database backup API on the existing OHOS database worker before merging sync data, instead of unsupported VACUUM/checkpoint SQL. Abort the merge on failed or incomplete snapshots; other platforms keep their existing backup path. ([#41](https://github.com/sobranie2406/modureader/issues/41)). Thanks [@xuezeyang123-hub](https://github.com/xuezeyang123-hub) for reporting and testing.

- Feat(feedback): Include current-session sanitized diagnostic fields from Advanced Logs by default, including recognized failure causes, HTTP/database codes and code frames. Preview before sharing; export long logs as TXT for manual GitHub attachment. Reset the bounded diagnostic buffer on restart without changing sync behavior.

### 简体中文

- Feat(settings): 裁边应用范围、向量／OCR 模型下载源及更新源改为直接点选；文字一级菜单直接提供已保存文字 TXT 导出，本页文字编辑保留在重排／提取工具中，保留缓存校对稿及原有来源逻辑。

- Fix(ocr): 文字／OCR 重排界面继续按原书页码后台缓存，重排内滚动不改变窗口，切换原书页时才更新；前台需要识别时先等在途页面完成并复用结果，重排工具面板显示缓存进度，离开已缓存文字不误取消后台渲染。

- Feat(ocr): 已保存的页面文字、校对稿和笔记引用版本随已下载原书通过现有书籍同步服务同步；未下载原书不拉取缓存，下载原书时一并获取缓存。按原文件校验值关联，不依赖本机编号或书名；逐页合并、保留冲突版本，上传校验成功后再合并清理旧快照。

- Feat(ocr): 缓存页数改用 1–5 页的减号／数字／加号控件；缓存进度将已有识别结果和校对稿计入已处理页数。

- Fix(ocr): 预缓存先检查已有识别与校对稿，只处理缺失页；触摸、滚动和翻页不再反复取消正在处理的页面，手动识别、切后台和退出仍可取消让出资源。缩短空闲调度等待，显示当前页识别进度。

- Fix(pdf): 裁边预览固定在顶部，下面的选项独立滚动，分格改为可点击示意图。修复原页模式无裁边信息时不启动预缓存的问题，缓存范围不越过末页；增加有限重试及已缓存页数、缺少模型等状态提示。

- Feat(ios): 通过现有翻页通道接入可选音量变化监听，仅在前台阅读且无菜单／弹窗遮挡时翻页，不接管系统音量和朗读音频会话。兼容监听无法区分实体键与其他音量变化，音量极值处重复按键可能无效，尚待实机验证。

- Feat(pdf): 新增可选后台文字／OCR 预缓存，按当前页起共 1–5 页串行处理，保留已保存的校对稿。合并自动文字／OCR 重排并恢复电子书重排菜单；提取工具移至预览下方，裁边阅读开关移入裁边编辑器，精简页面选项。缩放条支持拖动、80% 透明和闲置 5 秒隐藏，修复放大后普通点击被误判为拖动。

- Feat(pdf): PDF／扫描书底栏整合为目录、笔记、文字、页面和原有亮度；保留框选提取、连续识别、缓存编辑与 TXT 导出，页面中归拢裁边、适配、旋屏、翻页和图像增强。新增 1–4 倍双指缩放、桌面框选放大、拖动及逐页视口记忆，沿用有上限的图片渲染；旋屏同步调整阅读窗口与适应屏宽。

- Fix(harmony): 鸿蒙同步合并前在现有数据库工作线程调用原生备份接口，不再执行不兼容的 VACUUM／checkpoint SQL；备份失败或不完整时仍停止合并，其他平台备份逻辑不变。（[#41](https://github.com/sobranie2406/modureader/issues/41)）。感谢 [@xuezeyang123-hub](https://github.com/xuezeyang123-hub) 反馈与测试。

- Feat(feedback): 问题反馈默认附带本次启动的高级日志脱敏诊断字段，包含已识别的错误原因、HTTP／数据库错误码及代码堆栈；提交前可预览，长日志可导出 TXT 后手动附加到 GitHub。诊断缓存限量保存并在重启后清空，不改变同步逻辑。

## 1.2.11-beta.3

### English

- Feat(reader): Share ebook layout settings with OCR reflow, disable inapplicable settings, and apply horizontal text alignment with symmetric reading margins. Refine PDF style controls and nested reading panels; clarify header top and footer bottom margins.
- Fix(selection): Cache paragraph word boundaries for initial long-press selection, including direct presses on characters. Keep round draggable handles without re-expanding manually adjusted ranges; suppress the competing Android selection toolbar and exclude line spacing from highlight geometry.
- Style(tts): Match the circled-square stop icon to the other narration toolbar controls, without a separate background.
- Feat(ocr): Save recognition and corrected text in one book file indexed by original page; reuse saved pages across reflow modes and model changes, recognize missing pages automatically, and export saved pages as paginated TXT. Confirm page re-recognition before replacing recognition and edits; preserve historical notes and source positions. ([#42](https://github.com/sobranie2406/modureader/issues/42)). Thanks [@seightday](https://github.com/seightday) for the suggestion.

### 简体中文

- Feat(reader): OCR 重排复用普通电子书排版设置，不适用项置灰；修正左右对齐及阅读边距，整理 PDF 样式和多级阅读菜单，页眉、页脚边距明确标为上边距、下边距。
- Fix(selection): 提前缓存段落词边界，长按文字直接选中完整词；保留圆点拖动手柄，手动调整不再自动扩词，抑制安卓重复原生浮窗，选区高亮不再包含行间距。
- Style(tts): 朗读停止按钮使用与其他按钮一致的圆圈方块图标，不再单独添加背景。
- Feat(ocr): 按原始页码将识别结果及校对稿保存到每本书一个文件；重排模式或模型改变时仍优先读取已有结果，无缓存时自动识别，支持按页导出 TXT。重新识别前确认替换本页识别及编辑结果，保留旧笔记和原图位置。（[#42](https://github.com/sobranie2406/modureader/issues/42)）。感谢 [@seightday](https://github.com/seightday) 提出建议。

## 1.2.11-beta.1

### English

- Feat(tts): Use icon-only narration controls with a larger circled-square stop button. Make the floating background 80% transparent and draggable within the screen, without changing the reading viewport or playback actions. Keep opaque icons, tooltips and accessibility labels.

- Perf(reader): Measure horizontal chapter extent in the existing geometry pass before alignment writes, avoiding a second immediate full-chapter layout. Keep fresh measurements for later image/resize updates and transformed content. Twelve synthetic browser comparisons preserve geometry and CFIs; E-Ink timing is pending.
- Fix(selection): Theme native handles only inside reader WebViews as blue circles from creation, keeping native selection, smart expansion and later custom handle takeover. Device verification of the green-handle transition is pending.

- Perf(reader): Reuse a styled template for page-alignment runs, skip unchanged offsets and redundant generated-node style reads, and split layout diagnostics into content-free substage timings. E-Ink device latency verification is pending.

- Fix(selection): Keep reader handle takeover after Android stylus drag-selection and native scroll-to-selection while preserving the exact manually selected range; finger scrolling and mouse/keyboard selection retain their behavior. Native handles still reproduced on test3; device verification of the follow-up is pending.

- Fix(reader): Handle Android WebView renderer loss in the reader, background import/search, dictionary and web popups; discard dead views and offer explicit reload instead of reusing them. Skip unchanged layout attributes and batch geometry updates into one pagination pass. Record anonymous chapter resource, document, preparation, font and layout timings for device diagnosis. Manual crash recovery was verified remotely; the underlying renderer crash and E-Ink navigation delays remain under investigation.

- Fix(harmony): Preserve reader URL parameters in the HarmonyOS loopback WebView fallback, preventing a missing book address from causing HTTP 500 and import timeouts. Related to the investigation of [#33](https://github.com/sobranie2406/modureader/issues/33); thanks [@xuezeyang123-hub](https://github.com/xuezeyang123-hub) for reporting the HarmonyOS bookshelf/reader failures. API 26 emulator import and shelf checks pass; the original device-only blank shelf is not yet reproduced.

- Feat(sync): Start the existing manual two-way sync directly from the bookshelf sync button, without opening the sync status sheet; retain sync policies and result feedback.

- Fix(settings): Standardize the system theme value as `system`, accepting legacy `auto` preferences and backups so global settings file/link export no longer fails validation.

- Feat(tts): Add a stop button at the trailing end of the floating narration toolbar, retaining the compact layout on narrow screens.

- Fix(settings): Adjust settings sliders only by dragging the thumb; ignore track taps and track-started drags to prevent accidental changes while scrolling. Keep reading progress tap-to-seek ([#40](https://github.com/sobranie2406/modureader/issues/40)). Thanks [@ndd200](https://github.com/ndd200) for the suggestion.

### 简体中文

- Feat(tts): 朗读浮动栏改用纯图标及更大的圆圈方块停止按钮；背景80%透明，可在屏幕内拖动，不改变正文视口和播放操作。图标保持清晰，保留长按提示及无障碍标签。

- Perf(reader): 普通横排在对齐偏移写入前复用本次几何测量获取章节宽度，避免立即再次计算整章布局；后续图片／尺寸变化和旋转内容仍重新测量。12组合成章节浏览器对比的坐标与CFI一致，墨水屏耗时待验证。
- Fix(selection): 仅阅读器 WebView 从创建时使用蓝色圆点原生手柄，保留原生选择、自动扩词及后续自定义手柄接管；绿色手柄过渡的实机验证待完成。

- Perf(reader): 页面对齐节点复用样式模板，跳过未变化的偏移写入和生成节点的重复样式读取；细分排版耗时诊断，不记录正文。墨水屏实机耗时改善待验证。

- Fix(selection): Android 触控笔滑动选字及系统滚动到选区后保留阅读器自定义手柄接管，保持手动选择的准确范围，不再次扩词；手指滚动与鼠标／键盘选区行为不变。test3 实机仍复现原生手柄，追加修复待实机验证。

- Fix(reader): 阅读器、后台导入／检索、词典和网页弹窗接管 Android WebView 渲染进程退出，移除失效视图并提供手动重载，不再复用崩溃视图。跳过未变化的排版参数，多项布局参数合并为一次分页；记录不含书籍内容的资源、文档、准备、字体与排版分阶段耗时。远端已验证手动重载恢复；底层渲染崩溃及墨水屏跳转延迟仍在排查。

- Fix(harmony): 鸿蒙 WebView 本地页面降级加载保留阅读器网址参数，避免书籍地址丢失导致 HTTP 500 和导入超时。本次排查关联 [#33](https://github.com/sobranie2406/modureader/issues/33)，感谢 [@xuezeyang123-hub](https://github.com/xuezeyang123-hub) 反馈鸿蒙书架及打开书籍异常。API 26 模拟器导入和书架检查通过；原反馈设备的首页空白尚未复现。

- Feat(sync): 点击书架同步按钮直接启动原有手动双向同步，不再弹出同步面板；同步策略和结果提示保持不变。

- Fix(settings): “跟随系统”主题值统一为 `system`，兼容旧版 `auto` 设置及备份，修复全局设置文件／链接导出校验失败。

- Feat(tts): 在朗读浮动栏最右侧增加停止按钮，窄屏保留自适应紧凑布局。

- Fix(settings): 设置滑块仅允许拖动滑块调节，点击轨道或从轨道开始拖动不改值，减少滚动设置页面时的误触；阅读进度条保留点击跳转（[#40](https://github.com/sobranie2406/modureader/issues/40)）。感谢 [@ndd200](https://github.com/ndd200) 提出建议。

## 1.2.10

### English

- Fix(reflow): Remove narration from PDF/OCR reflow menus, selection actions and playback shortcuts; prevent speech from falling through to the hidden original page. Ordinary ebook narration remains available.

- Fix(ocr): Reduce excessive reflow paragraph breaks by measuring printed line spacing per column and requiring clear paragraph gaps, first-line indents or trailing whitespace. Join ordinary sentence wraps and nearby same-row OCR fragments; upgrade cached layouts without rerunning OCR while preserving historical note revisions and source coordinates.

- Fix(eink): Lock E-Ink to pure white backgrounds and pure black text across the app, ebook reader and OCR reflow, regardless of dark/night mode. Preserve saved reading palettes and background images when E-Ink is disabled.

- Fix(reflow): Reuse the actual ebook quick-style component for OCR/reflow font size, thickness, line/paragraph spacing, fonts, palettes and backgrounds. Keep typography book-local and additional reflow settings behind the gear button.

- Fix(reflow): Use the ordinary ebook menu host and button order for PDF/OCR reflow. Keep the original-page/mode header and PDF page arrows; both compact and menu arrows automatically reflow the adjacent source page and reuse cached recognition. Preserve PDF preprocessing budgets and caches.

- Fix(tts): Update Edge Read Aloud authentication to the v2 token protocol, resolving synthesis rejection caused by the obsolete token. Preserve clock correction, bounded retries, audio caching and narration positions ([#39](https://github.com/sobranie2406/modureader/issues/39)). Thanks [@115MicroRGB](https://github.com/115MicroRGB) for the iOS report.

- Feat(reflow): Infer paragraphs and first-line indents from source line geometry while retaining uncertain headers, footers and short lines. Reuse ebook color/background editors, imported fonts and spacing controls; add reflow-aware page navigation, search, copy, query/translation, AI drafts and bookmarks. Keep historical text-layout revisions intact for existing annotations.

- Fix(reader): Switch ordinary ebook night colors without repagination or waiting for fonts; apply reader colors to nested publisher text and headings when original-book styles are disabled. Keep OCR reflow and original-page toolbars mutually exclusive, with immediate opaque night colors on reflow text and no hidden source-page repaint.

- Feat(notes): Preserve original page numbers and uncropped image line/text-block coordinates with new PDF/OCR reflow notes. “View original” shows the saved source regions without rerunning OCR; re-recognition never rewrites existing notes or their text revisions. Older notes remain available without guessed image positions or forced text matching.

- Feat(feedback): Remove contact links from feedback; include independently optional crash and safe current-session runtime diagnostics by default in bug reports, with full preview before confirmation. Record content-free reader, narration, sync, lifecycle, timing and memory events; runtime history clears on every restart while crash diagnostics remain separate.
- Feat(reader): Add an immediately saved option to scroll one chapter at a time instead of joining adjacent chapters; continuous scrolling remains the default ([#36](https://github.com/sobranie2406/modureader/issues/36)). Thanks [@Wisso2278](https://github.com/Wisso2278) for the suggestion.
- Fix(reader): Preserve numbered headings and decorated publisher blocks during automatic page alignment and line-spacing fitting; leave affected columns at native spacing while ordinary prose pages still align ([#34](https://github.com/sobranie2406/modureader/issues/34)). Thanks [@Claire9518](https://github.com/Claire9518) for the report and sample EPUB.
- Fix(backup): Resolve library and cache paths before starting the ZIP worker, avoiding uninitialized Windows preferences during database export.
- Fix(storage): Schedule Windows storage relocation before database startup, verify copied files and retain the original library; only switch paths after successful copying.
- Fix(android): Stage settings exports in app-owned cache before opening the system save dialog; distinguish file, system-service and settings-format failures instead of reporting all failures as permissions.

### 简体中文

- Fix(reflow): 移除 PDF／OCR 重排的朗读菜单、划词朗读和播放快捷键入口，避免误读隐藏原页；普通电子书朗读保持不变。

- Fix(ocr): 减少重排过度断段，按栏测算实际行距，仅在明确段距、首行缩进或段尾留白时分段；合并普通句内换行及同一行 OCR 碎片。旧缓存无需重新识别即可更新排版，历史笔记版本和原图坐标保持不变。

- Fix(eink): E-Ink 强制锁定浅色，应用界面、电子书与 OCR 重排统一为纯白底纯黑字，不随深色／夜间模式切换；关闭后恢复保存的阅读配色和背景图。

- Fix(reflow): OCR／重排样式面板直接复用普通电子书组件，统一字号、粗细、行距／段距、字体、配色与背景布局；排版仅保存到当前书籍，重排附加参数收进齿轮设置。

- Fix(reflow): PDF／OCR 重排直接共用普通电子书菜单及按钮排列，保留顶部原页／重排模式和底部 PDF 页码箭头；底部与菜单翻页均自动重排相邻原页并复用识别缓存，保留 PDF 预处理提前量和缓存逻辑。

- Fix(tts): 适配 Edge 朗读新版 v2 鉴权，修复旧版令牌导致的语音生成被拒绝；保留时钟校正、有限重试、音频缓存和朗读位置（[#39](https://github.com/sobranie2406/modureader/issues/39)）。感谢 [@115MicroRGB](https://github.com/115MicroRGB) 提供 iOS 问题反馈。

- Feat(reflow): 根据原页行坐标恢复分段和首行缩进，保留无法确认的页眉、页脚及短行；复用电子书配色、背景图、导入字体与间距设置，补充适配重排文字的跳页、查找、复制、查询／翻译、AI 草稿及书签。保留历史文字排版版本，避免旧划线与笔记错位。

- Fix(reader): 普通电子书切换夜间配色不再重新分页或等待字体；关闭原书样式时，内嵌文字与标题一并跟随阅读配色，避免夜间仍显示黑字。OCR 重排与原页工具栏互斥，避免两套菜单叠加，识别／重排文字立即切换不透明夜间配色，不再同时重绘隐藏原页。

- Feat(notes): 新增 PDF／OCR 重排笔记保留原始页码及未裁切原图的行／文字块坐标；“查看原图”按保存时位置框选核对，不依赖重新 OCR。重新识别不改写既有笔记及文字版本；旧笔记保留，不猜测坐标、不强行匹配。

- Feat(feedback): 问题与反馈页面移除联系方式；Bug 报告默认附带可分别取消的崩溃日志和安全运行日志，提交前预览完整内容并确认。补充不含私人内容的阅读、朗读、同步、生命周期、耗时与内存记录；运行记录每次重启清空，崩溃诊断独立保留。
- Feat(reader): 新增“跨章节连续滚动”开关，关闭后每章独立滚动，章末通过翻页或目录进入下一章；即时保存，默认保留连续滚动（[#36](https://github.com/sobranie2406/modureader/issues/36)）。感谢 [@Wisso2278](https://github.com/Wisso2278) 提出建议。
- Fix(reader): 自动上下对齐和行距微调时保护带编号、边框等特殊排版的小标题，避免编号、竖线与标题文字错位；相关页面保留原排版，纯正文页继续对齐（[#34](https://github.com/sobranie2406/modureader/issues/34)）。感谢 [@Claire9518](https://github.com/Claire9518) 提供反馈和复现书籍。
- Fix(backup): 在主线程确定书库和缓存路径，再启动 ZIP 压缩，修复 Windows 数据库导出时设置未初始化的问题。
- Fix(storage): Windows 存储迁移改在重启后、数据库打开前执行，逐文件校验并保留原书库，复制成功后才切换路径。
- Fix(android): 设置导出先写入应用缓存，再调用系统保存窗口；区分文件读写、系统服务和设置格式错误，不再统一提示权限问题。

## 1.2.10-beta.1

### English

- Feat(reader): Give PDF reflow and OCR results an ebook-style reading surface and compact bottom menus for text style, brightness and narration. Preserve source-page navigation, selection/annotations, region/full-page/batch recognition and AI drafts; opening menus does not resize the text viewport.
- Feat(feedback): Remove contact links from feedback; include independently optional crash and safe current-session runtime diagnostics by default in bug reports, with full preview before confirmation. Record content-free reader, narration, sync, lifecycle, timing and memory events; runtime history clears on every restart while crash diagnostics remain separate.
- Feat(reader): Add an immediately saved option to scroll one chapter at a time instead of joining adjacent chapters; continuous scrolling remains the default ([#36](https://github.com/sobranie2406/modureader/issues/36)). Thanks [@Wisso2278](https://github.com/Wisso2278) for the suggestion.
- Fix(reader): Preserve numbered headings and decorated publisher blocks during automatic page alignment and line-spacing fitting; leave affected columns at native spacing while ordinary prose pages still align ([#34](https://github.com/sobranie2406/modureader/issues/34)). Thanks [@Claire9518](https://github.com/Claire9518) for the report and sample EPUB.
- Fix(backup): Resolve library and cache paths before starting the ZIP worker, avoiding uninitialized Windows preferences during database export.
- Fix(storage): Schedule Windows storage relocation before database startup, verify copied files and retain the original library; only switch paths after successful copying.
- Fix(android): Stage settings exports in app-owned cache before opening the system save dialog; distinguish file, system-service and settings-format failures instead of reporting all failures as permissions.

### 简体中文

- Feat(reader): PDF 重排和 OCR 结果统一为电子书式阅读界面，使用自适应底部样式、亮度和朗读菜单；保留原页导航、划词标注、区域／整页／连续识别及 AI 草稿功能，展开菜单不改变正文视口。
- Feat(feedback): 问题与反馈页面移除联系方式；Bug 报告默认附带可分别取消的崩溃日志和安全运行日志，提交前预览完整内容并确认。补充不含私人内容的阅读、朗读、同步、生命周期、耗时与内存记录；运行记录每次重启清空，崩溃诊断独立保留。
- Feat(reader): 新增“跨章节连续滚动”开关，关闭后每章独立滚动，章末通过翻页或目录进入下一章；即时保存，默认保留连续滚动（[#36](https://github.com/sobranie2406/modureader/issues/36)）。感谢 [@Wisso2278](https://github.com/Wisso2278) 提出建议。
- Fix(reader): 自动上下对齐和行距微调时保护带编号、边框等特殊排版的小标题，避免编号、竖线与标题文字错位；相关页面保留原排版，纯正文页继续对齐（[#34](https://github.com/sobranie2406/modureader/issues/34)）。感谢 [@Claire9518](https://github.com/Claire9518) 提供反馈和复现书籍。
- Fix(backup): 在主线程确定书库和缓存路径，再启动 ZIP 压缩，修复 Windows 数据库导出时设置未初始化的问题。
- Fix(storage): Windows 存储迁移改在重启后、数据库打开前执行，逐文件校验并保留原书库，复制成功后才切换路径。
- Fix(android): 设置导出先写入应用缓存，再调用系统保存窗口；区分文件读写、系统服务和设置格式错误，不再统一提示权限问题。

## 1.2.9

### English

- Fix(reader): Keep viewport-based page alignment out of footnote popups, preventing repeated height adjustments; normalize unnumbered footnote list margins and padding without changing ordinary numbered lists.
- Fix(selection): Fit Android touch-selection highlights to the actual text bounds on aligned pages, preserving the selected text, automatic word selection and draggable handles.
- Fix(tts): Preserve active narration and its live position when sync refreshes the reader, instead of reinitializing playback or restoring a paused remote position. Reopening a book still restores its highlight paused.
- Fix(sync): Distinguish successful uploads with newer local progress pending from real sync failures. Persist and retry the remaining changes without stopping narration; retain network/conflict errors, data-merge protections and Jianguoyun rate limits.

### 简体中文

- Fix(reader): 注释弹窗不再应用按屏幕高度调整行距的正文对齐逻辑，避免反复改变高度；统一无编号注释列表的左右留白，保留普通编号列表样式。
- Fix(selection): 修正 Android 分页对齐后的蓝色划词高亮过高问题，按实际文字范围绘制，保留选中文本、自动选词与拖动手柄。
- Fix(tts): 同步刷新阅读界面时保留当前朗读及实时位置，不再重新初始化播放或强制恢复为暂停的远端位置；重新打开书籍仍恢复高亮并保持暂停。
- Fix(sync): 区分“已上传但又产生新进度”和真正的同步失败，持续朗读时不再误报失败；新增进度持久化排队、自动补传，不中断朗读，保留网络／冲突错误、数据合并保护及坚果云限频。

## 1.2.8

### English

- Perf(pdf): Prepare adjacent cropped/enhanced PDF pages before they enter the scroll viewport, reuse bounded full-panel backing images and refine zoomed details separately. Adapt one/two-panel lookahead to measured processing time and available device hints; cancel obsolete work, recycle bitmap URLs and preserve text/annotation coordinates.
- Fix(windows): Do not refocus the Flutter child window on deactivation or minimized activation messages; retain focus restoration on normal activation. Defensive correction for the reported selection-menu/Show Desktop scenario; the native crash is not yet reproduced or confirmed fixed.
- Fix(sync): Start automatic sync promptly on startup, foreground/unlock, network restoration and book exit after reading/narration writes finish. Persist unfinished requests for retry, preserve Jianguoyun interval/budget/cooldown and Wi-Fi-only rules, and do not acknowledge newer requests with an older upload.

- Feat(models): Add offline file import to embedding and OCR model settings. Accept only the existing catalogue's pinned size and SHA-256, validate the complete set before installation, and preserve model selection and books.
- Feat(tts): Remember and sync each book's exact narration range and playback state. Reopening restores its highlight in a paused state, without automatic speech. Older clients continue to sync reading positions but cannot restore narration state.
- Fix(tts): Follow long passages across page boundaries using system word offsets or an online audio-duration estimate. Retain the existing audio cache and page layout; same-page progress does not repeatedly scroll the reader.
- Fix(tts): Allow configured playback shortcuts in the narration panel and handle Xiaomi hardware keyboards reporting a visible, zero-height IME. Preserve text-editor guards and suppress held-key repeats for play/pause.
- Fix(reader): Follow Legado's pre-display page-finalization approach for horizontal prose: distribute spare height across actual lines, including two/three-line pages, while preserving chapter endings and explicit page breaks. Apply the new viewport width/height before measuring after rotation or resizing; page turns reuse the completed layout without post-display repositioning.
- Fix(harmony): Add a native reader keep-screen-on bridge and contain plugin failures; align export snapshot validation with path_provider's application cache instead of the ability cache, preserving original logs and path restrictions. Investigation of the bookshelf blank screen and chapter-load failure remains open ([#33](https://github.com/sobranie2406/modureader/issues/33)). Thanks [@xuezeyang123-hub](https://github.com/xuezeyang123-hub) for the report.
- Feat(ios): Add opt-in file/folder reading in place for EPUB, PDF, MOBI, AZW3 and FB2, retaining device-local access bookmarks without copying or automatically uploading originals. Keep ordinary import for formats requiring conversion; bookshelf deletion/replacement preserves originals ([#35](https://github.com/sobranie2406/modureader/issues/35)). Thanks [@wangxxisme](https://github.com/wangxxisme) for the suggestion.
- Fix(reader): Include reclaimed leading paragraph space when fitting full pages, and keep DIV paragraph spacing rules active after preparing page-alignment runs. Extend browser checks to production reader CSS and the slider's actual 3em/5em paragraph settings.
- Fix(reader): Keep individual scroll-line boundaries at small line spacing and zero paragraph spacing. Measure loaded font geometry and the available viewport before display, adjust scroll spacing without changing saved settings, and scale paginated edge alignment with text size. Page turns reuse prepared layout.
- Fix(settings): Restore Keyboard shortcuts under Settings → Reading, between page-turning controls and scroll settings. Keep the reader popup compact and preserve existing bindings, immediate saving and reset defaults.

### 简体中文

- Perf(pdf): PDF 相邻页提前完成裁边与图像增强，进入滚动区域即可显示，复用有尺寸上限的整页／分格底图，放大后再补充局部高清细节。结合实际处理耗时及设备信息自动调整提前一至两个阅读区域，取消失效任务并回收图片缓存，保留文字层和批注坐标。
- Fix(windows): 窗口失去激活或处于最小化状态时，不再主动把焦点设回 Flutter 子窗口；正常激活时保留焦点恢复。针对划词菜单打开后“显示桌面”场景进行防护修正，原生崩溃尚未复现或确认修复。
- Fix(sync): 启动、回到前台／解锁、恢复网络及退出书籍时尽快自动同步；退出先等待阅读与朗读位置写入完成，未完成请求持久化后自动补同步，保留坚果云间隔／预算／冷却及仅 Wi-Fi 限制，旧上传完成不清除新请求。

- Feat(models): 向量模型和 OCR 模型设置增加离线文件导入，仅接受现有型号及固定版本，完整文件组通过大小与 SHA-256 校验后才安装，保留当前模型选择与书籍数据。
- Feat(tts): 按书籍独立记忆并同步精确朗读位置、高亮范围和播放状态，重新打开时恢复高亮并保持暂停，不自动出声。旧客户端仍可同步阅读进度，但不能恢复朗读状态。
- Fix(tts): 长段落跨页时按系统字词进度或在线音频时长比例估算跟随翻页，保留已有缓存和页面排版，页内播放进度不反复滚动页面。
- Fix(tts): 朗读面板内支持已配置的播放快捷键，修复小米外接键盘将零高度输入法报告为可见、导致空格键被拦截的问题；保留文本输入保护，长按播放／暂停键不重复切换。
- Fix(reader): 参考 Legado 在显示前完成分页对齐的思路，左右翻页按实际行位置分配剩余高度，补齐两三行正文页的对齐，保留章节末页及显式分页留白；旋转屏幕或改变窗口时先应用新的可用宽高再测量，翻页复用已完成的排版，不在显示后补调位置。
- Fix(harmony): 补齐鸿蒙阅读常亮原生通道并处理插件失败；导出文件快照按 path_provider 使用的应用级缓存目录校验，避免与 Ability 级缓存目录不一致，保留原日志与路径安全限制。书架空白及章节加载失败仍在排查（[#33](https://github.com/sobranie2406/modureader/issues/33)）。感谢 [@xuezeyang123-hub](https://github.com/xuezeyang123-hub) 反馈。
- Feat(ios): 新增文件／文件夹“原位添加”，EPUB、PDF、MOBI、AZW3、FB2 可不复制原书直接阅读，并保存本机访问授权；原书不自动上传或纳入备份，需转换格式的书籍仍用普通导入，书架删除／替换保留外部原书（[#35](https://github.com/sobranie2406/modureader/issues/35)）。感谢 [@wangxxisme](https://github.com/wangxxisme) 提出建议。
- Fix(reader): 顶底对齐计算纳入页首段距释放的空间，避免大行距、大段距正文页被误判跳过；修复 DIV 正文加入排版节点后丢失段落样式的问题，补测实际阅读 CSS 及段距滑块对应的 3em／5em 设置。
- Fix(reader): 修复小行距、零段间距时只能在部分段尾停靠的问题。显示前根据已加载字体和实际可用阅读区域计算滚动行距，保留保存的设置；左右翻页的顶底对齐按实际字号调整，翻页时复用已完成的排版。
- Fix(settings): 恢复“设置 → 阅读”中的自定义按键入口，位于翻页方式下方、滚动设置上方；阅读弹窗保持精简，保留已有按键配置、即时保存和恢复默认。

## 1.2.7

### English

- Fix(ai): Restore selection context across inline page-alignment runs and styled text. AI Knowledge receives nearby paragraph text when context is enabled; keep the existing 120-character window on each side and 600-character limit, without enabling local book search.
- Feat(history): Add an edit-only Reset button to restore the default reading-history cards and their order, saving immediately without deleting reading records ([#32](https://github.com/sobranie2406/modureader/issues/32)). Thanks [@ndd200](https://github.com/ndd200) for the suggestion.
- Fix(pdf): Fix next/previous source-page navigation in text/OCR reflow: pass the page number through the reader navigation API so successful extraction is not incorrectly reported as a reflow failure.
- Feat(pdf): Add multi-page text extraction with printer-style page ranges, sequential local OCR, completed-page reuse and cancellable retry. Navigate directly between extracted-page previews without returning to the image view; keep extraction into AI as a draft.
- Fix(reader): Align ordinary horizontal text pages to the configured top and bottom margins before display, with bounded spacing adjustments and natural chapter endings. Scroll steps and settled gestures prefer complete lines: prioritize the bottom edge going down and the top edge going up when both cannot fit. Do not hide edge text or reflow after page turns. Verified on an Android test device; other native platforms remain unverified.
- Perf(reader): Prepare and cache scroll-line geometry during layout instead of scanning chapter text on every scroll step. Invalidate it after layout/content changes and reuse document-local positions across adjacent chapters. Find only the visible boundary nodes when updating reading position, avoiding per-glyph measurements across the whole page.
- Perf(reader): Animate horizontal pages using a compositor transform, committing the scroll position once at completion. Retain immediate E-Ink/disabled-motion behaviour and the existing fallback for unsupported engines and vertical/continuous reading.
- Fix(harmony): Repair the log export menu and use the native document-save picker for file exports. Report success only after writing completes, handle cancellation and errors, and preserve original files. Native HAP/device verification is pending.
- Fix(harmony): Use the current MODU artwork for the launcher and start window. Stage sync archives in the database directory required by the OHOS SQLite adapter, with unique names and disposable copies; retain integrity checks and merge protections. Add sanitized database failure diagnostics. Physical-device sync verification is pending.
- Fix(reader): Fit quick style panels to their content with an 80% height limit, keeping long settings scrollable and the bottom toolbar reachable. Hide the top toolbar while an expanded bottom tool panel is open.
- Feat(ui): Shorten the Chinese home navigation labels for Remote Library and Reading History to two characters, preserving typography, full page titles and other language labels.
- Feat(settings): Save lookup switches/order, dictionary selections, existing selection-tool options, AI model parameters and skill toggles, per-book indexing models, CSS edits and PDF/OCR text styles without a separate Save step. Keep validation, retry feedback and explicit confirmation for connection drafts, new templates and destructive actions.
- Feat(ui): Add translucent, draggable scrollbars across lists, settings, Lookup and scrollable dialogs; show during scrolling and hide after 1.2 seconds idle. Isolate nested and side-by-side scroll positions, reserve a drag lane beside controls, and leave horizontal scrolling without a scrollbar. Web panels and continuous reading also gain transient scrollbars; pagination stays unchanged and E-Ink skips fading.
- Feat(reader): Match reading-style and PDF settings panel sizes to Lookup; move CSS to its own tab between Style and Other, and remove duplicate selection-toolbar, automatic-summary and keyboard-shortcut entries from the reader panel.
- Chore(dev): Clean up static analysis and migrate legacy custom_lint to an isolated Riverpod native plugin compatible with the current Flutter/Dart toolchain, preserving Riverpod 2 runtime behavior and context-safety checks.
- Fix(pdf): Keep original-page navigation available after text/OCR reflow fails. Left/right arrows start reflow for the adjacent source page instead of repeatedly requesting the same failed page; retry and mode switching target the attempted page while reading progress changes only on success.
- Feat(appearance): Control book-format and indexed labels independently in Appearance; both default to on. Match indexed-label typography and padding to format labels without hiding indexing progress or failure notices.
- Feat(bookshelf): Switch between thumbnails and a cover-free list from the bookshelf toolbar; remember the layout and retain book metadata, folder counts, long-press selection and batch actions.
- Feat(lookup): Customize the overview order of Dictionary, Encyclopedia, Translation and AI Knowledge by dragging in Lookup settings. Remember the order locally, retain positions for disabled sources, and keep optional query-text ordering.
- Feat(appearance): Add an E-Ink-only "Disable all animations" switch, disabled outside E-Ink mode. Keep animation suppression enabled by default; turning it off restores saved animation preferences without changing the monochrome palette or hardware refresh settings.

### 简体中文

- Fix(ai): 修复分页对齐及行内样式拆分文字节点后划词上下文缩短的问题；开启结合上下文时，AI 知识正确收到所在段落的前后文。保留前后各 120 字符、总计最多 600 字符的范围，不启用本地书籍搜索。
- Feat(history): 阅读历史卡片编辑状态新增“恢复默认”按钮，还原默认卡片组合与排列顺序并立即保存，不删除阅读记录（[#32](https://github.com/sobranie2406/modureader/issues/32)）。感谢 [@ndd200](https://github.com/ndd200) 提出建议。
- Fix(pdf): 修复文字／OCR 重排结果切换上一页、下一页失败；按阅读器导航接口传递原版页码，避免提取成功后因原页定位失败而误报重排失败。
- Feat(pdf): 提取文字新增「连续识别」，支持打印机式页码范围、逐页本地 OCR、已完成结果复用和停止后重试；文字预览可直接切换上一页／下一页，无需返回原图。提取至 AI 仍沿用填入草稿的行为。
- Fix(reader): 普通横排正文在显示前小幅调整间距，对齐设置的上下边距，章节末页保留自然留白；滚动翻屏及手势停稳时优先停在完整行，两端无法兼顾时向下以下端为主、向上以上端为主。不隐藏边缘文字，也不在翻页后重排正文。已在安卓测试机验证，其他原生平台仍待实测。
- Perf(reader): 排版时提前计算并缓存滚动行位置，避免每次翻屏扫描整章；排版或正文变化时使缓存失效，相邻章节移动时复用章内坐标。更新阅读位置只查找可见首尾节点，避免逐字测量整页。
- Perf(reader): 左右翻页使用合成层平移动画，结束时一次性提交滚动位置；保留 E-Ink／禁用动画时立即翻页，以及旧引擎、竖排和连续滚动的原有处理。
- Fix(harmony): 修正日志导出菜单，文件导出改用鸿蒙原生保存窗口；写入完成后才提示成功，处理取消和失败并保留原文件。仍待 HAP 构建及鸿蒙实机验证。
- Fix(harmony): 鸿蒙桌面与启动窗口使用现有 MODU 图标；同步数据库改在鸿蒙 SQLite 插件要求的数据库目录内通过独立副本读写，使用唯一文件名，保留完整性校验与合并保护，并补充脱敏数据库错误诊断。同步仍待鸿蒙实机复测。
- Fix(reader): 阅读快捷样式面板按内容收缩，最高占屏幕 80%，长内容可滚动且底部工具栏保持可操作；展开下方工具面板时隐藏上方工具栏。
- Feat(ui): 首页中文导航将“远程书库”和“阅读历史”缩短为“远程”和“历史”，保留原字体字号、页面完整标题及其他语言名称。
- Feat(settings): 综合查询开关与排序、词典选择、已有划词工具选项、AI 模型参数与技能开关、单书索引模型、CSS 编辑及 PDF/OCR 文字样式无需另点保存；保留校验、失败重试以及连接草稿、新建模板和破坏性操作的确认。
- Feat(ui): 列表、设置、综合查询和可滚动弹窗统一增加半透明、可拖动滚动条，滚动时显示，停止操作 1.2 秒后隐藏；嵌套及并排列表独立控制，控件旁预留拖动区域，横向滑动不显示滚动条。内嵌网页与正文连续滚动模式同样支持，分页保持不变，E-Ink 下不播放淡入淡出动画。
- Feat(reader): 阅读样式与 PDF 设置面板尺寸对齐综合查询；CSS 独立为“样式”和“其他”之间的标签，移除阅读面板中的划词工具栏、自动总结前文及键盘快捷翻页入口。
- Chore(dev): 清理静态分析提示，将旧 custom_lint 迁移为兼容当前 Flutter/Dart 的隔离式 Riverpod 原生分析插件，保留 Riverpod 2 运行逻辑及上下文安全检查。
- Fix(pdf): 修复文字／OCR 重排失败后无法继续翻页的问题；左右箭头按原版页码启动相邻页重排，不再反复卡在同一失败页。重试和切换重排模式针对待处理页，仅成功后更新阅读进度。
- Feat(appearance): 外观设置支持独立开关书籍格式与已索引标签，均默认开启；已索引标签的字号和内边距与格式标签一致，不隐藏索引进度或失败提示。
- Feat(bookshelf): 书架首页新增缩略图／无封面列表切换，记忆布局选择，保留书籍信息、文件夹数量、长按多选和批量操作。
- Feat(lookup): 综合查询设置支持拖动调整字典、百科、翻译、AI 知识的汇总顺序，本机记忆设置；关闭来源仍保留位置，保留可选的查询文本智能排序。
- Feat(appearance): 在 E-Ink 模式下增加「关闭所有动画」总开关，未开启 E-Ink 时置灰。默认仍关闭动画；关闭此开关后恢复原有动画设置，不改变黑白显示与硬件刷新设置。

## 1.2.6

### English

- Fix(reader): Handle unavailable chapter documents before accessing their DOM; discard failed chapter resources so retry reloads them. Preserve the outgoing page and reading position, keep slow loads cancellable, and log chapter failure reasons without book text or resource URLs.
- Fix(ai): Remember edit-before-send independently for each AI screen and selection action on this device; exclude these preferences from sync and settings transfer.
- Fix(ai): Keep AI Knowledge on model/web knowledge for follow-ups, history restore and retries; never use local book tools. Keep Book AI follow-ups grounded in their original book or skill source.
- Feat(ai): Add independent settings, new-chat, history and display menus to AI Knowledge, AI translation, Classical Chinese translation and other AI panels. Separate history by built-in/custom skill and home task; clearing one history does not remove another. Retain legacy conversations.
- Fix(reader): Use the same blue touch handles for Android reader selections, including already-expanded words and unexpanded text; replace native drag handles to avoid their magnifier. Preserve manual range edits, copy and annotation actions.
- Ci(lint): Update custom_lint to 0.7.6 to fix its startup failure on the current Dart SDK; keep custom checks enabled.
- Fix(pdf): Restore highlight, underline and annotation actions for PDF/OCR selections; align marks with cropped, zoomed and rotated pages.
- Fix(appearance): Use the full 0–100 manual brightness range instead of a 20% floor; preserve follow-system mode and keep software dimming controls accessible.
- Feat(appearance): Add a default-enabled book-format badge switch in Appearance; keep scanned-book and indexed indicators independent.
- Fix(bookshelf): Hide cover overflow buttons until selection mode is entered by long press or desktop right-click, in both the shelf and folders; keep batch actions and lower-right menu placement.
- Fix(android): Refresh release plugin registration through the shared APK build entry, preventing stale integration-test plugin references after tests.
- Ci(android): Update Gradle, Android Gradle Plugin and Kotlin to 9.2.1, 9.0.1 and 2.3.20; migrate the app and 14 plugins to built-in Kotlin, enable JVM target validation, align library compile SDKs and migrate native-library packaging. Keep the Android 8.0 minimum.
- Ci(android): Pin the SDK command-line parser used by builds and emulator tests, migrate deprecated Gradle property assignments and disable unused Jetifier. Update the Android database plugin to 2.4.2+2 for Android 16 API guards, with sqflite_common pinned to 2.5.6 to preserve transaction semantics. Retain Flutter's required old-DSL compatibility warning.
- Fix(pdf): Restore touch-scroll momentum in PDF continuous-scroll mode, respecting disabled-animation and E-Ink settings ([#31](https://github.com/sobranie2406/modureader/issues/31)). Thanks [@RuizeSun](https://github.com/RuizeSun)
- Feat(pdf): Use the existing brightness-panel moon button to invert PDF pages and darken the surrounding background in night mode. Keep OCR text selection and annotation colours unchanged; turn it off to restore original page colours. Images within PDF pages are also inverted.

### 简体中文

- Fix(reader): 修复切章时空文档导致的加载失败，清理失败章节资源，使重试重新加载；保留原页与阅读位置，慢加载仍可取消，并记录不含正文或资源地址的章节失败原因。
- Fix(ai): 各 AI 界面与划词 AI 入口独立记忆「编辑后发送」开关，仅保存在本机，不参与同步和设置导入导出。
- Fix(ai): AI 知识的追问、历史恢复和重试始终使用大模型／联网知识，不调用本地或本书检索工具；本书 AI 继续围绕原书籍或原技能的原文范围回答。
- Feat(ai): 为 AI 知识、AI 翻译、文言文翻译等 AI 界面补齐独立的设置、新建对话、历史和显示菜单；内置技能、自定义技能与首页任务分别保存历史，清空互不影响，保留旧记录。
- Fix(reader): 安卓阅读选区统一使用蓝色触控手柄，覆盖原生已选中整词及不扩词的文字选区；替换原生拖动手柄，避免其放大浮框，保留拖动调整范围、复制与批注操作。
- Ci(lint): 将 custom_lint 更新至 0.7.6，修复当前 Dart SDK 下检查插件无法启动的问题，保留自定义检查。
- Fix(pdf): 恢复 PDF／OCR 选词的高亮、下划线与批注操作，使标记随裁边、缩放和旋转正确对齐。
- Fix(appearance): 手动亮度使用完整的 0–100 范围，取消原有 20% 下限；保留跟随系统模式，软件调暗时保持控件可见。
- Feat(appearance): 在界面外观中增加默认开启的书籍格式标签开关，不影响扫描版和已索引标记。
- Fix(bookshelf): 书架与文件夹内默认隐藏封面三个点，长按或桌面右键进入多选后再显示；保留批量操作及右下角菜单位置。
- Fix(android): 通过统一 APK 打包入口刷新生产插件注册表，避免测试后残留的 integration_test 引用导致编译失败。
- Ci(android): 将 Gradle、Android Gradle Plugin 和 Kotlin 分别升级到 9.2.1、9.0.1 和 2.3.20；将应用和 14 个插件迁移至内置 Kotlin，启用 JVM 目标版本校验，对齐插件编译 SDK 并迁移原生库打包配置。最低仍支持 Android 8.0。
- Ci(android): 固定构建与模拟器测试使用的 SDK 命令行解析器，迁移 Gradle 弃用属性赋值并关闭不再需要的 Jetifier。Android 数据库插件升级至 2.4.2+2，使用 Android 16 API 兼容分支；锁定 sqflite_common 2.5.6，保留原有事务语义。保留 Flutter 必需的旧 DSL 兼容警告。
- Fix(pdf): 修复 PDF「连续卷轴」触控滑动缺少惯性的问题，遵循关闭动画和 E-Ink 设置 ([#31](https://github.com/sobranie2406/modureader/issues/31)) 感谢 [@RuizeSun](https://github.com/RuizeSun)
- Feat(pdf): 复用亮度面板的月亮按钮，夜间模式下 PDF 页面反色、四周背景变黑，保留 OCR 选词与批注颜色；关闭后恢复原色。PDF 页面内的插图也会一同反色。

## 1.2.5

### English

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

### 简体中文

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

## 1.2.4

### English

- Feat(import): Import text UMD books with chapters, metadata and supported covers, converting them to EPUB for reading and synchronization. Image/comic UMD is not supported.
- Fix(bookshelf): Show TXT, MD and UMD source-format badges and book details after conversion; retain stored EPUB paths and content checksums used by synchronization.
- Feat(reader): Apply the expanding, outward-opening cover transition across platforms, with the reader mounted at its final size; preserve iOS edge-swipe return and E-Ink/disabled-animation preferences.
- Fix(ios): Refresh the selection menu after dragging native selection handles, so copying and marking use the updated range rather than the initially selected word.
- Fix(remote-library): Read large WebDAV directory listings in a background worker, increase the listing limit to 32 MiB, skip individual malformed encoded entries and show directory-specific errors.
- Feat(remote-library): Import the current remote folder or a folder from its menu, including subfolders; select compatible books before sequential downloads, with duplicate checks, progress and cancellation.
- Perf(remote-library): Throttle download progress updates and reuse sorted/filtered lists during folder imports to reduce repeated UI work.
- Fix(reader): Restore MOBI note popups only when legacy note lists and superscript icons match; recognize AZW3 note types and explicit embedded note text, hiding duplicate inline notes while retaining ambiguous content.
- Docs(features): Update the bilingual feature and settings guides for UMD, original-format badges, remote folder imports, shared cover transitions and note compatibility.

### 简体中文

- Feat(import): 支持文字版 UMD 导入，保留章节、元数据和支持的封面，转换为 EPUB 后沿用阅读及同步流程；暂不支持图片／漫画 UMD。
- Fix(bookshelf): TXT、MD、UMD 转换后仍显示原始格式标签及书籍详情，同步继续使用实际存储的 EPUB 路径和内容校验值。
- Feat(reader): 各平台统一采用封面放大、向外翻开的开书过渡，正文在最终尺寸下初始化；保留 iOS 侧滑返回及 E-Ink／关闭动画设置。
- Fix(ios): 拖动系统选区手柄后及时更新选词菜单，复制和标注使用调整后的范围，不再停留在首次选中的词语。
- Fix(remote-library): 大型 WebDAV 目录在后台解析，目录响应上限提高至 32 MiB，跳过单条编码异常记录，并显示针对目录的错误信息。
- Feat(remote-library): 支持从当前远程目录或文件夹菜单批量导入，包含子文件夹；下载前勾选兼容书籍，依次下载，提供重复检查、进度及取消操作。
- Perf(remote-library): 限制下载进度刷新频率，复用排序和筛选结果，减少远程文件夹导入时的重复界面计算。
- Fix(reader): 仅在旧式注释列表与上标图标匹配时恢复 MOBI 注释弹窗；补齐 AZW3 注释类型及明确内嵌注释文字的识别，隐藏重复显示的注释，保留无法可靠判定的内容。
- Docs(features): 更新中英文功能与设置指南，补充 UMD、原格式标签、远程文件夹导入、全平台封面过渡和注释兼容说明。

## 1.2.3

### English

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

### 简体中文

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

## 1.2.2

### English

- Import multiple books and folders, including desktop folder drag-and-drop; preserve source files.
- Improve OCR/reflow word expansion and selection menus; retain manual selection handles.
- Disable visual animations in E-Ink mode; add format/scanned badges and translucent navigation with bottom clearance.
- Add independent WebDAV and S3-compatible object-storage settings, retaining existing WebDAV configuration.
- Fix footnotes inside highlights/underlines and make folder overflow buttons consistent with book covers.
- Reduce Android opening/AI keyboard layout contention; actual frame-rate gains await device measurement.
- Include an unsigned native HarmonyOS ARM64 HAP requiring local signing; not yet device-validated.
- Add Telegram channel/discussion links and a copyable QQ group number without a QR code.

### 简体中文

- 支持多书籍、文件夹导入和桌面文件夹拖入，保留原始文件。
- 改善 OCR／重排阅读的按词扩选及划词菜单，保留手动调整手柄。
- E-Ink 模式关闭视觉动画；增加格式／扫描版标签及底部避让的半透明导航。
- 增加独立的 WebDAV 与 S3 兼容对象存储设置，保留已有 WebDAV 配置。
- 修复高亮、划线内脚注打不开的问题，统一文件夹与书籍更多按钮样式。
- 减少安卓开书及 AI 键盘布局的重复负担，实际帧率提升待实机测量。
- 提供原生鸿蒙 ARM64 未签名 HAP，需本地签名安装，尚未实机验证。
- 增加 Telegram 频道／群组，QQ群仅显示可复制群号，不再显示二维码。

## 1.2.1

### English

- Repair converted TXT / Markdown checksums without changing book identities; improve new-device WebDAV synchronization and legacy database compatibility.
- Recognize Jianguoyun, coalesce automatic sync, persist rolling request budgets and server cooldowns, and reduce duplicate listing/authentication/maintenance requests while retaining conflict and integrity checks.
- Improve PDF/scanned-page rendering, tap-to-turn and paper whitening; default selection AI to context with a selected-text-only option.
- Add the QQ community number and original invitation code to About and feedback.

### 简体中文

- 修复 TXT／Markdown 转换后校验不一致，保留书籍身份；改善新设备 WebDAV 同步及旧数据库兼容。
- 自动识别坚果云，合并自动同步，持久化访问预算及冷却，减少重复扫描、认证和维护请求，保留防冲突及完整性校验。
- 优化 PDF／扫描版渲染、点击翻页和纸张增白；划词 AI 默认结合上下文，保留仅选中文字选项。
- 关于及反馈界面增加 QQ 群号和原始入群二维码。

## 1.2.0

### English

- Read PDFs and scanned image books with dedicated crop, panel order, zoom, rotation and continuous-scroll controls, while ordinary text books retain their reading menus.
- Detect image books during import across EPUB, MOBI, AZW3 and FB2; fix fixed-size comic pages and legacy MOBI image record references, with a manual bookshelf override.
- Apply per-page automatic content cropping and image enhancements, including conservative scanned watermark fading; fit original and cropped pages to the window.
- Download lightweight OCR models on demand, with V4 recommended, selectable sources and local deletion; reflow page text directly in the reader or extract a selected region into AI chat.
- Add E-Ink-only refresh controls, improve battery alignment and simulated-bold controls, and add a Classical Chinese translation selection template.
- Search online from an AI Knowledge answer, stop queued vector indexing, and improve narration continuity and web translation/search popup layout and zoom.
- Simplify macOS installers to the app and Applications shortcut; publish eight platform packages without Android x64.

### 简体中文

- PDF 与扫描图片书使用专用裁边、分格、缩放、旋转及卷轴阅读菜单，普通文字书保留原阅读界面。
- EPUB、MOBI、AZW3、FB2 在导入时识别图片书，修复固定尺寸漫画和旧式 MOBI 图片编号漏识别，并支持书架手动切换。
- 按页自动识别内容边界裁边，提供图像增强与扫描水印减淡，原图和裁图随窗口与设置自动适配。
- 轻量 OCR 模型按需下载，推荐 V4，支持来源选择与本地删除；整页文字直接接入阅读区重排，区域提取结果可填入 AI 对话。
- 增加仅在 E-Ink 模式显示的刷新工具，改善页眉电量对齐和模拟加粗按钮，新增文言文翻译划词模板。
- AI 知识回答支持按钮联网补查，支持停止队列向量化，改善朗读连续性及网页翻译、搜索弹窗排版与缩放。
- Mac 安装盘仅展示应用与 Applications 快捷入口，全平台提供八个安装包，不再发布安卓 x64。

## 1.1.12-preview.4

- Add original-page reading for PDFs and image-based EPUBs, with crop, panel order, zoom, rotation and continuous scrolling.
- Add automatic edge cropping and image enhancements; save reading layout and view position per book.
- Classify EPUBs during import only; ordinary books retain their Preview 3 reading menus and settings.
- Add a Search online action before Regenerate and Copy in AI Knowledge replies, continuing the same conversation without clearing an unsent draft.

- 新增 PDF 和图片 EPUB 原版阅读，支持裁边、分格顺序、缩放、旋转和连续卷轴阅读。
- 新增自动裁边和图像增强，按书保存版式与视口位置。
- EPUB 类型仅在导入时判别，普通书籍保持 Preview 3 阅读菜单与设置。
- AI 知识回答末尾增加联网搜索按钮，位于重新生成和复制之前，沿用当前对话并保留未发送草稿。

## 1.1.11

- Automatically expand only the initial Android long-press selection; show draggable handles immediately and preserve subsequent manual range adjustments.
- Fix missing final AI answer text and blank answers when reopening conversation history.
- Continue current and restored reader conversations when manually sending follow-up questions; keep new skill and selection tasks independent.
- Move history to a clock icon beside the options menu and prevent narrow-screen history entries from overflowing.

- 安卓仅在首次长按时自动扩展词语或段落，直接显示拖动手柄，后续手动框选不再强制匹配。
- 修复 AI 回答末尾丢字、历史记录重新打开后回答空白的问题。
- 阅读 AI 的当前对话和历史对话支持手动连续追问，新的技能及划词任务仍保持独立对话。
- 历史入口改为更多选项左侧的时钟图标，修复窄屏历史条目布局溢出。

## 1.1.10

- Add a compact narration toolbar and online speech rates up to 4x, with 3x and 4x steps after 2x.
- Show reading skills by default, with built-in/custom toggles and mixed ordering; optionally fill a template into the input before sending.
- Simplify selection AI templates with selected-text/context scope and optional web search; keep AI Knowledge in the selection toolbar only.
- Fix mobile long-press word selection, including native pointer takeover and older Android WebViews; optionally select a whole paragraph without overriding manual adjustments.
- Fix a persistent blank reader when opening the contents drawer by safely handling removed widgets' focus contexts.
- Move font thickness to a 0.5–2.0 slider in 0.1 steps between font size and line spacing; fix font-weight adjustments for nested text and publisher inline styles, preserving headings, emphasis and custom CSS.
- Add an optional simulated-bold button beside font thickness; text strokes allow fixed-weight fonts to be thickened from 1.1 to 2.0, without changing the text or reading anchors.
- Preserve unchanged book vectors across upgrades and file migrations; verify and recover legacy indexes locally instead of embedding them again.
- Switch translation providers inside the translation popup, without reopening it.
- Simplify global settings migration to files/modu links, retaining credential switches and user prompt edits; clarify database ZIP backup contents and saved locations, and improve bug/feature feedback forms.

- 新增小型朗读快捷栏，在线朗读最高支持 4 倍速，2 倍后提供 3 倍与 4 倍档位。
- AI 阅读技能默认显示，内置与自定义技能均可开关、混合排序；可先填入模板，再编辑并手动发送。
- 划词 AI 提示词精简，支持仅选中文字或结合上下文，可独立勾选联网搜索；AI 知识仅保留在划词工具栏。
- 修复手机长按自动选词，兼容系统接管触摸和旧版 Android WebView；可选择整段，不覆盖用户手动调整的选区。
- 修复点击目录时因焦点回调读取已销毁控件而出现持续白屏的问题。
- 将字体粗细调节移至字体大小与行间距之间，以 0.5–2.0 显示，按 0.1 步进；修复字重被正文嵌套标签和书籍内联样式覆盖的问题，保留标题、强调文字及自定义 CSS。
- 在字体粗细旁新增“模拟加粗”按钮，默认关闭；通过描边让固定字重字体在 1.1–2.0 范围内逐档加粗，不改动文字与阅读定位。
- 修复升级或文件迁移后未变更书籍被误判为需要重新向量化的问题；旧索引经本地校验后复用，修复索引状态而不重新生成向量。
- 翻译弹窗内直接切换翻译服务提供方，无需关闭重开。
- 全局设置仅保留文件和 modu 链接迁移，保留账号接口独立开关，仅备份用户提示词改动；明确数据库 ZIP 备份内容与保存位置，完善 Bug 和功能建议提交表单。
