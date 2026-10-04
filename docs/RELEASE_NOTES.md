# Modu 1.2.0 · Stable

Documentation reviewed 2026-10-04. [Current guides](README.md) · [Release assets](https://github.com/sobranie2406/modureader/releases/tag/v1.2.0). This document describes the published release, not uncommitted preview fixes.

## English

**Modu 1.2.0 (build 10082)** includes all changes since stable **1.1.11**, including the intervening previews.

- Dedicated PDF and scanned-book controls: cropping, panel order, zoom, rotation, panning, fit modes and continuous scrolling, with per-book layout and position persistence.
- Per-page automatic content cropping, image enhancements and conservative scanned watermark fading, without modifying source books. Original and cropped pages adapt to the window.
- Import-time image-book detection for EPUB, MOBI, AZW3 and FB2, including remote imports; fixed-size comics and legacy MOBI image records are now recognized correctly. Manual bookshelf overrides are available. Ordinary text books retain their existing menus and styling.
- On-demand local OCR: recommended PP-OCRv4, optional v5 mobile and v3 models, upstream/Gitee sources and local deletion. Reflow the current page directly in the reader, use selection actions on recognized text, or extract a region into an editable AI draft.
- An online-search action in AI Knowledge replies continues the same conversation; a Classical Chinese translation selection template is included.
- Fix narration skipping ordinary paragraphs mistaken for footnote backlinks. Improve Android Bluetooth page-turner lifecycle handling, battery alignment, simulated-bold controls, and web search/translation popup layout; web translation supports persistent 50%–200% zoom.
- Stop active and queued vector indexing while retaining completed indexes. Disabling automatic indexing cancels automatic tasks without preventing later manual indexing.
- E-Ink-only manual and periodic refresh controls on supported hardware. Refreshed bilingual documentation pairs phone settings with Mac feature results.
- Eight packages: Android ARM64, iOS ARM64, and ARM64/x64 for macOS, Windows and Linux, each with SHA-256. Android x64 is no longer distributed. Mac disk images contain only the app and the Applications shortcut.

Back up and upgrade in place. Android retains its signing key; macOS is not notarized, Windows requires WebView2, Linux packages target Debian 13, and iOS requires your own valid signing. Gitee receives identical GitHub packages; source and licenses remain available at the version tag.

---

## 简体中文

版本：**1.2.0+10082**。以下汇总 **1.1.11 正式版至 1.2.0** 的功能变化，包含期间预览版的改进。

## PDF 与扫描图片书阅读

- 新增专用原版阅读菜单：裁边与分格、阅读顺序、适应页面／宽度、缩放、旋转、平移和连续卷轴阅读，按书保存版式及阅读位置。
- 「裁边与分格」直接进入编辑界面，PDF 与扫描图片书共用操作方式；原图和裁边后的图片随窗口大小及阅读设置自动缩放。
- 自动裁边逐页识别内容边界，处理外围扫描框、纸张阴影和零散噪点，并保留页码、脚注及有效内容。
- 提供墨色、对比度、加深、增白、锐化等图像增强，新增扫描水印减淡；可对照原图、调节强度及恢复默认，不改写原书文件。
- 阅读面板主题跟随应用，仅在 E-Ink 模式使用黑白样式；E-Ink 模式下显示手动刷新和每 N 页自动刷新工具，硬件刷新需设备提供对应接口。

## 自动识别图片书

- EPUB、MOBI、AZW3、FB2 在导入时最多抽样五个正文分节识别图片书，本地导入、远程书库导入及下载流程共用检测。
- 打开书籍只读取已保存的分类，不再抽样等待。书架菜单可手动「设为扫描图片书籍」或恢复普通书籍阅读。
- 修复固定尺寸漫画因页面留白被误判，以及旧式 MOBI 使用图片编号引用导致漏识别的问题。
- 扫描图片书不再弹出普通插图的点击放大／长按选项。未判定为扫描版的文字书保留原阅读菜单和样式，不受 PDF 专用设置影响。

## 按需 OCR、文字重排与提取

- 新增「设置 → OCR 模型」，提供 PP-OCRv4 中英文（推荐）、v5 中英文轻量版、v3 中英文及 v3 英文，按需下载，不随安装包内嵌模型。
- 模型卡片支持下载并使用、选择、校验、取消与删除；可选择上游或 Gitee 下载源，模型选择和下载源纳入全局设置备份。
- 文字重排与 OCR 重排处理当前原页，启用裁边时使用裁后整页；结果直接显示在阅读区，可调节文字样式并使用划词工具、AI、高亮和笔记。
- 提取功能支持手动选择范围，将识别结果填入 AI 对话输入框，再由用户编辑发送。OCR 在本机运行，不自动上传原书。

## 阅读、AI 与网页工具

- 修复部分 EPUB 脚注回链被误判为注释，导致朗读跳过正文段落的问题。
- AI 知识回答末尾新增「联网搜索」，位于「重新生成」「复制」之前；点击后沿用同一对话补查，无需手动输入确认语句，并保留未发送草稿。
- 新增「文言文翻译」划词 AI 预设，可在划词工具栏设置中管理。
- 优化搜索和百度、有道等网页翻译弹窗的适配布局，减少横向溢出；网页翻译新增 50%–200% 缩放并记住比例。
- 优化模拟加粗按钮；缩小页眉页脚电量指示并修复显示电量后文字下移、边框挤压正文的问题。
- 修复 Android 蓝牙翻页笔接入或断开时不必要的阅读窗口重建，恢复按键状态及阅读时的沉浸显示。

## 向量化任务与文档

- 新增「停止向量化」：书架任务栏和向量模型设置均可停止当前及排队任务，同时关闭自动向量化，保留已完成索引、书籍和模型。
- 关闭自动向量化后取消自动任务，避免扫描期间继续入队或重启后继续自动运行；手动任务仍可单独发起。
- 中英文 README 重新组织功能模块，以手机设置与 Mac 功能效果配图展示阅读、CSS、听书提示词、划词工具、AI、向量化及备份；英文作为仓库首页，中文保留独立入口。

## 下载与升级

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.2.0) · [Gitee 安装包](https://gitee.com/sobranie2406/modureader/releases/tag/v1.2.0)

共 **8 个安装包**，各附 SHA-256：Android ARM64、iOS ARM64，以及 macOS、Windows、Linux 的 ARM64 与 x64。**不再发布 Android x64**。

覆盖升级即可，**不要先卸载或清空数据**，升级前建议备份书库及设置。Android 沿用原签名；macOS DMG 仅展示 `Modu.app` 和 `Applications` 快捷入口。旧书已保存的普通书分类可在书架菜单手动切换，无需重新导入。

- macOS 为 ad-hoc 签名，未做 Apple 公证；Windows 需要 WebView2 Runtime，安装器无商业 Authenticode 签名。
- Linux DEB 面向 Debian 13，请用 APT 安装依赖；iOS IPA 需使用自己的有效签名配置为主应用及 Share Extension 签名后安装。
- GitHub 保留历史发行版及源码标签；Gitee 使用同一批安装包，替换旧应用发行版，不影响独立模型镜像。

[对应源码](https://github.com/sobranie2406/modureader/tree/v1.2.0) · [1.1.11 至 1.2.0 源码差异](https://github.com/sobranie2406/modureader/compare/v1.1.11...v1.2.0) · [安装与构建说明](https://github.com/sobranie2406/modureader/blob/v1.2.0/docs/RELEASING.md)
