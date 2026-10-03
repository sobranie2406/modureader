# Modu changelog

Details and downloads: https://github.com/sobranie2406/modureader/releases

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
