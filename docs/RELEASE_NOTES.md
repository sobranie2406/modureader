# 默读 / Modu 1.1.11 正式版

版本：**1.1.11+10072**。

## 本次更新

- **选区自由调整**：安卓仅在首次长按时自动扩展到所在词语或整段；随后拖动选区不会再次强制匹配，也不会被锁回原来的范围。
- **选词手柄直接显示**：自动扩展后立即显示两端拖动手柄，不必再点一次；工具栏预留手柄操作空间。
- **AI 回答完整保存**：修复流式输出正常结束被误判为取消的问题，避免回答末尾丢字、完成后的回答未正确保存，以及重新打开历史记录时回答空白。此前未写入的历史回答无法凭空恢复，可重新生成。
- **阅读 AI 连续追问**：在当前对话或打开的历史对话中输入新问题，保留已有问答上下文继续回答；明确新建对话、发起新的技能或划词任务时才开始独立对话。
- **历史入口更直观**：使用时钟图标，移到右上角更多选项左侧；同时修复手机窄屏上模型名称及时间的布局溢出。
- **说明文档更新**：中英文 README 同步说明自动选词、选区调整和多轮对话行为。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.11) · [Gitee 安装包](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.11)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议备份书库。Android 沿用原签名；macOS 退出旧应用后，使用 DMG 拖入应用程序覆盖安装。

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 使用 ad-hoc 签名，未做 Apple 公证。
- Windows 需 WebView2 Runtime；安装器没有商业 Authenticode 签名。
- Linux DEB 面向 Debian 13，请使用 APT 安装依赖。
- iOS IPA 需用自己的有效签名配置签署主应用及 Share Extension 后安装。

GitHub 保留历史发行版及源码标签；Gitee 替换旧应用发行版，提供同一批安装包和校验文件。独立模型镜像不变。

对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.11) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.11.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.11/docs/RELEASING.md)。许可与版权信息见同标签 LICENSE、NOTICE、UPSTREAM.md 和 LICENSES。

## English

Modu **1.1.11 (build 10072)** fixes repeated selection snapping on Android. Automatic expansion runs only on the initial long press, then displays draggable handles immediately so the selected range remains freely adjustable.

AI stream completion no longer incorrectly cancels the request, preventing missing answer endings and unsaved answers that appeared blank when reopening history. Answers that were never written by earlier versions cannot be reconstructed; regenerate them if needed.

Manually typed follow-up questions continue the current reader conversation, including conversations restored from history. Explicit new chats and new skill or selection tasks remain independent. The history clock icon now sits beside the options menu, and narrow-screen history rows no longer overflow.

Upgrade in place after backing up. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows requires WebView2, and iOS requires your own valid signing. Gitee receives identical, hash-verified GitHub packages.
