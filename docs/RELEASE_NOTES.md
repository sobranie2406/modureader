# 默读 / Modu 1.1.7 正式版

版本：**1.1.7+10052**。

## 本次更新

- **书架管理与 Markdown**：支持 MD / Markdown 书籍；书籍、文件夹可置顶和取消置顶，批量选择书籍建立文件夹或移入已有文件夹。
- **阅读排版与搜索**：滚动翻页步长可在 80%～100% 之间调整；修复安卓平板横屏和桌面滚动模式下的侧边距调节。增加标注颜色与内置搜索窗口缩放。
- **AI 词典与思维导图**：词典优先用当前模型知识解释选词，按需查询维基词典、维基百科和百度百科，再由同一模型整理并附来源，无需另配搜索 API Key，不发送书籍正文。精简阅读工具调用展示；思维导图支持全屏、缩放移动和节点展开/折叠。
- **笔记返回原文**：导出笔记附带默读原文位置链接，可从支持链接的外部应用跳回对应书籍位置；保留原文括号、Markdown 高亮与创建/修改时间。
- **WebDAV 同步**：加强条件写入及 ETag 可靠性检测，处理相同内容重复书籍与关联笔记；可靠服务端以数据库为主，兼容模式整理合并日志，清理已安全覆盖的历史日志。
- **ANX 备份迁移**：所有客户端在“设置 → 高级 → 导入 ANX Reader 的备份文件”选择 ZIP，按步骤校验并合并书籍、笔记、进度、阅读记录、文件夹和标签。导入前自动备份，重复导入保留现有记录；范围及兼容要求在导入界面说明。
- **朗读与平台兼容**：改进后台跨章节预取与缓冲状态，优化 Windows 系统语音启动兼容性。Android 播放器通知明确静音、无振动，短暂音频打断只暂停和恢复一次，用户主动暂停优先。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.7) · [Gitee 安装包](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.7)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议备份书库。Android 沿用原签名；macOS 退出旧应用后，使用 DMG 拖入应用程序覆盖安装。

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 使用 ad-hoc 签名，未做 Apple 公证。
- Windows 需 WebView2 Runtime；安装器没有商业 Authenticode 签名。
- Linux DEB 面向 Debian 13，请使用 APT 安装依赖。
- iOS IPA 需用自己的有效签名配置签署主应用及 Share Extension 后安装。

Gitee 先移除旧应用发行版，再上传同一批 GitHub 原包；校验通过后更新下载清单。GitHub 保留历史发行版及源码标签，独立模型镜像不变。

对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.7) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.7.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.7/docs/RELEASING.md)。许可与版权信息见同标签 LICENSE、NOTICE、UPSTREAM.md 和 LICENSES。

## English

Modu **1.1.7 (build 10052)** adds Markdown books, pinned books/folders, batch folder management, adjustable scrolling steps, expanded annotation colors and embedded search zoom. Landscape tablet and desktop side margins are corrected.

The AI dictionary uses the current model's knowledge first, with optional Wiktionary, Wikipedia and Baidu Baike lookup, without sending book contents or requiring a separate search API key. Mind maps support fullscreen viewing, zoom/pan and collapsible nodes. Exported notes link back to their original reading position.

WebDAV sync improves conditional-write checks, duplicate-book reconciliation and safe log compaction. Advanced settings imports ANX Reader ZIP backups with validation, deduplication and a pre-import database snapshot. Background narration and Windows system voice compatibility are improved; Android player notifications are silent and transient audio interruptions resume only once.

Upgrade in place after backing up. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows requires WebView2, and iOS requires your own valid signing. Gitee receives identical, hash-verified GitHub packages.
