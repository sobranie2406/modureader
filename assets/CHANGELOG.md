# Modu changelog

Current stable baseline: **1.2.2+10087**. Updated 2026-10-07.

[Settings](../docs/SETTINGS.md) · [中文设置指南](../docs/SETTINGS_zh.md) · [Published releases](https://github.com/sobranie2406/modureader/releases)

Older sections retain their original version scope; they are not current acceptance reports.

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
