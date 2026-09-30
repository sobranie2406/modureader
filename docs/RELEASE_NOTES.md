# 默读 / Modu 1.1.9 正式版

版本：**1.1.9+10063**。

## 本次更新

- **高亮与下划线删除**：选中已有标注的局部或全部，即可删除相交的完整标注；同步清理重复标记，避免删除后仍残留。删除包含该标注的备注，请按确认框提示操作。
- **删除确认清晰可见**：弹出确认框时暂时隐藏划词工具栏和颜色栏，避免遮挡；取消删除后恢复工具栏。
- **AI 词典更快回答**：优先使用当前模型已有知识解释选词，不再自动等待联网检索，不发送书籍正文。英文提供音标、翻译与中英文解释，中文提供拼音、词义与相关知识。
- **联网补查由你决定**：需要核实时，在同一对话输入“确认联网搜索”并发送，才检索维基词典、维基百科和百度百科，再由当前模型整理并附来源，无需额外搜索 API Key。
- **对话与提示词衔接**：重新打开词典对话仍能按原选词继续补查；多语言提示明确说明输入确认，不再提示点击不存在的按钮。未修改的内置提示词随版本更新，用户自定义内容保持不变。
- **功能截图与说明更新**：中英文 README 补充新版阅读、古籍竖排、AI 提示词、划词工具栏和设置界面。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.9) · [Gitee 安装包](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.9)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议备份书库。Android 沿用原签名；macOS 退出旧应用后，使用 DMG 拖入应用程序覆盖安装。

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 使用 ad-hoc 签名，未做 Apple 公证。
- Windows 需 WebView2 Runtime；安装器没有商业 Authenticode 签名。
- Linux DEB 面向 Debian 13，请使用 APT 安装依赖。
- iOS IPA 需用自己的有效签名配置签署主应用及 Share Extension 后安装。

GitHub 保留历史发行版及源码标签；Gitee 替换旧应用发行版，提供同一批安装包和校验文件。独立模型镜像不变。

对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.9) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.9.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.9/docs/RELEASING.md)。许可与版权信息见同标签 LICENSE、NOTICE、UPSTREAM.md 和 LICENSES。

## English

Modu **1.1.9 (build 10063)** fixes highlight and underline deletion. Select any overlapping part of a mark to delete its complete annotation, including duplicate marks. The confirmation stays visible above selection tools and color controls; cancelling restores the toolbar.

The AI dictionary answers from the current model's knowledge first, without automatically waiting for web retrieval or sending book contents. When verification is needed, type the displayed confirmation phrase in the same conversation. Modu then checks Wiktionary, Wikipedia and Baidu Baike and lets the same model summarize the results with sources, without an additional search API key. Reopened conversations retain the original selected term. Updated localized instructions preserve user-edited prompts.

The Chinese and English READMEs include new 1.1.9 screenshots covering reading, vertical layout, custom AI prompts, selection tools and settings.

Upgrade in place after backing up. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows requires WebView2, and iOS requires your own valid signing. Gitee receives identical, hash-verified GitHub packages.
