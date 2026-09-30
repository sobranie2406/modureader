# 默读 / Modu 1.1.8 正式版

版本：**1.1.8+10061**。

## 本次更新

- **自定义划词工具栏**：内置动作、标注工具和自定义 AI 命令均可开关、拖动排序；支持编辑名称、图标、提示词和显示数量，内置常用 AI 模板默认关闭。
- **AI 阅读体验**：划词模板与阅读技能分别管理，共用阅读 AI 弹窗；每次划词 AI 提问开启新对话，生成结束后自动返回首段。全局设置备份只保存内置提示词的用户改动。
- **语言与提示词**：可手动选择应用语言或跟随系统，界面文字、内置技能和语音描述模板同步切换，保留用户自定义提示词。
- **章节与页数导航**：点击正文直接显示进度滑块，拖动预览章节标题；增加上一章、上一页、下一页、下一章按钮。区分「章节进度」和本章当前页/总页数。
- **字典与网页翻译**：改进 MDX 原生词目查询，保留字典本身的双向词目，不进行中文释义反查；新增百度、有道网页翻译，优化移动端自动填词和滚动。
- **阅读与标注修复**：适配常见图片式注释引用；修复垃圾桶无法删除新建高亮、划线，以及改色后旧标记在切换章节时重新出现的问题。删除采用明确确认，并等待存储和页面清除完成。
- **更新来源统一**：检查与下载共用同一 GitHub/Gitee 来源选择，默认优先 GitHub，手动切换后重新检查。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.8) · [Gitee 安装包](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.8)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议备份书库。Android 沿用原签名；macOS 退出旧应用后，使用 DMG 拖入应用程序覆盖安装。

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 使用 ad-hoc 签名，未做 Apple 公证。
- Windows 需 WebView2 Runtime；安装器没有商业 Authenticode 签名。
- Linux DEB 面向 Debian 13，请使用 APT 安装依赖。
- iOS IPA 需用自己的有效签名配置签署主应用及 Share Extension 后安装。

GitHub 保留历史发行版及源码标签；Gitee 替换旧应用发行版，提供同一批安装包和校验文件。独立模型镜像不变。

对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.8) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.8.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.8/docs/RELEASING.md)。许可与版权信息见同标签 LICENSE、NOTICE、UPSTREAM.md 和 LICENSES。

## English

Modu **1.1.8 (build 10061)** adds customizable selection tools, individually switchable and reorderable annotation controls, and editable AI prompt templates that start disabled. Selection AI commands and reading skills have separate settings and share the reading popup; each selection request starts a new conversation and returns to the beginning when generation ends. Backups retain only user edits to bundled prompts.

Choose an application language or follow the system; interface text and bundled AI/voice prompts follow that choice while custom prompts remain unchanged. Tap the reader to access chapter/page controls, preview chapter titles while dragging progress, and distinguish chapter ordinal from pages within the current chapter.

Dictionary lookup preserves native MDX headwords without reverse-searching definitions. Baidu and Youdao translation webpages support mobile prefilling and scrolling. Common image-marker footnotes are supported. Highlight/underline deletion now uses a visible confirmation, waits for storage and rendering, and clears duplicate annotation caches. Update checking and downloading share one source selector.

Upgrade in place after backing up. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows requires WebView2, and iOS requires your own valid signing. Gitee receives identical, hash-verified GitHub packages.
