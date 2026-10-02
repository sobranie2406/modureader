# 默读 / Modu 1.1.10 正式版

版本：**1.1.10+10069**。

## 本次更新

- **朗读快捷栏**：阅读页面新增小型操作栏，支持回到朗读位置、播放/暂停、从当前阅读位置朗读和打开设置。
- **最高 4 倍语速**：在线朗读提供 2 倍、3 倍、4 倍档位，保留低倍速细调；MiMo 通过本地播放倍率调整，无需重复合成。
- **AI 阅读技能更易用**：默认显示技能列表，内置与自定义技能均可开关、混合排序；可开启先填入输入框，编辑或追加要求后手动发送，默认仍为点击发送。
- **划词 AI 模板更简明**：AI 词典改为“AI 知识”，只介绍含义、背景与相关知识，按选词语言作答；所有划词 AI 命令均可选择仅选中文字或结合上下文，并可独立勾选联网搜索。默认不自动联网，仍可输入“确认联网搜索”补查，无需额外搜索 API Key。
- **移除重复阅读预设**：AI 阅读技能不再显示默认“AI 知识”，划词工具栏中的模板和用户自定义内容保留，已有对话历史继续兼容。
- **智能长按选词**：长按按所在词语选择文字，可在阅读设置中改为长按选择整段；安卓从触摸后系统实际选中的文字扩展选区，不再依赖字间命中点，兼容系统接管触摸及旧版 Android WebView，保留手动调整选区。
- **目录切换白屏修复**：目录打开、关闭与切后台时不再读取已移除控件的焦点上下文，避免焦点异常导致阅读页面持续无法重建。
- **字体粗细调节与字重修复**：将字体粗细调节移至底部样式栏的字体大小与行间距之间，滑块显示 0.5–2.0，按 0.1 步进，1.0 为正常粗细；正文嵌套标签与内联字重不再阻止粗细调整，图形 CSS 模板也覆盖嵌套文字；保留标题、强调文字和自定义代码，切回书籍样式时恢复原有字重。
- **固定字体模拟加粗**：字体粗细旁新增“模拟加粗”按钮，默认关闭；开启后 1.0 保持原样，1.1–2.0 通过同色描边逐档加粗，不能将固定粗体变细。开关随阅读样式保存和备份，关闭后恢复正常字重调节。
- **向量索引升级保留**：按书籍实际内容识别索引，不再因路径、文件修改时间变化误判失效；旧索引经本地校验后复用原向量，复制后失效的索引状态可自动恢复。
- **翻译服务切换**：翻译弹窗内可切换已配置的翻译提供方，无需退出当前弹窗。
- **全局设置备份简化**：保留文件与 modu 链接迁移，移除超出容量的二维码导出和图片导入；账号、密码及 API 接口配置保留独立开关，备份仅携带用户改动，不重复包含默认提示词。
- **数据库备份指引**：同步界面明确“数据库备份导出/导入”，说明 ZIP 内容、保存位置、覆盖恢复步骤；导出成功后显示并可复制实际保存位置。
- **GitHub 反馈改进**：区分 Bug 和功能建议，按模板填写与预览后提交；环境信息及脱敏诊断可选，默认不附带日志。
- **说明文档更新**：中英文 README 同步更新朗读、AI 技能、划词与备份功能说明。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.10) · [Gitee 安装包](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.10)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议备份书库。Android 沿用原签名；macOS 退出旧应用后，使用 DMG 拖入应用程序覆盖安装。

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 使用 ad-hoc 签名，未做 Apple 公证。
- Windows 需 WebView2 Runtime；安装器没有商业 Authenticode 签名。
- Linux DEB 面向 Debian 13，请使用 APT 安装依赖。
- iOS IPA 需用自己的有效签名配置签署主应用及 Share Extension 后安装。

GitHub 保留历史发行版及源码标签；Gitee 替换旧应用发行版，提供同一批安装包和校验文件。独立模型镜像不变。

对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.10) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.10.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.10/docs/RELEASING.md)。许可与版权信息见同标签 LICENSE、NOTICE、UPSTREAM.md 和 LICENSES。

## English

Modu **1.1.10 (build 10069)** adds a compact narration toolbar and online speech rates up to 4×, with 3× and 4× steps after 2×. MiMo changes local playback speed without regenerating audio. Drawer and focus transitions no longer inspect disposed widget contexts, avoiding a persistent blank reader. Font-weight controls now reach nested book text while preserving emphasis and user CSS. The control is labeled Font thickness, ranges from 0.5 to 2.0 in 0.1 steps, and sits between font size and line spacing. An optional Simulated bold button adds stroke-based thickness for fixed-weight fonts above 1.0 and is saved with the reading style.

Unchanged book vectors survive upgrades and file migrations. Content-based identities and local legacy verification restore copied index metadata without regenerating embeddings.

Reading skills are visible by default; built-in and custom skills can be toggled and reordered together. The optional draft mode fills the input field before manual sending, while immediate sending remains the default. AI Knowledge is now a selection-toolbar template only; existing conversations and custom skills remain compatible. Selection AI commands use concise prompts, support selected text or nearby context, and offer optional online search. Model knowledge is used first when search is off; explicit confirmation can still request source-backed verification.

Long presses select the current word, with an optional whole-paragraph mode. Translation providers can be switched inside the translation popup. Global settings use files and modu links rather than oversized QR codes, retain independent credential controls and exclude unchanged default prompts. Database ZIP backup guidance explains contents, destinations and replacement restores, with a persistent saved-location confirmation. GitHub feedback separates bugs from feature requests and previews optional, sanitized diagnostics before submission. Both READMEs have been updated.

Upgrade in place after backing up. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows requires WebView2, and iOS requires your own valid signing. Gitee receives identical, hash-verified GitHub packages.
