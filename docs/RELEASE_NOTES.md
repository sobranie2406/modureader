# 默读 / Modu 1.1.6 正式版

版本：**1.1.6+10049**。

## 本次更新

- **连续朗读与搜索修复**：朗读播放期间持续补充后续段落缓存，减少段落之间的等待；修复选词搜索窗口上下滑动冲突及横屏、键盘展开时的工具栏溢出。版本信息改为读取实际安装包，正确显示构建号。
- **全局设置导入导出**：统一迁移外观、阅读排版、CSS、AI、技能、向量配置、朗读、翻译、搜索、同步、书库、笔记偏好、统计布局及网络设置，支持文件、二维码和 `modu:` 链接。补齐默认值恢复、书摘背景与书库显示偏好，导入前完整校验，兼容旧版配置链接。账号、密码和 API 接口配置由独立开关控制，默认关闭；关闭时导出不包含、导入不覆盖本机凭据。开启后的主动导出为明文，请妥善保管。同步加密及同步密码保持独立。
- **在线朗读按段播放**：Edge、MiMo、OpenAI 兼容及 DashScope 合并同一自然段内相邻句子，按播放段准确高亮，支持上一段、下一段和从选中文字开始朗读。首段优先合成，后续预取；跳转后忽略过期音频和错误。系统朗读保留逐句控制。
- **语音与后台控制**：MiMo 支持通过语速滑块调整实际播放速度；支持描述提示词的接口沿用稳定语速、音色与风格要求。OpenAI 兼容语音增加可编辑提示词与预设。优化暂停恢复、锁屏章节推进和旧任务取消逻辑。
- **图形化 CSS 模板**：32 个命名位置、13 个预设模板，支持颜色、字体、间距、下划线等模块化调节，同时保留自定义代码与正则高亮。参数统一在“设置 → CSS 设置”管理，阅读界面选择应用。
- **选词内置搜索**：支持百度、Bing、谷歌、百度百科、维基百科及自定义引擎；搜索结果在内置浏览器显示，保留弹窗内切换引擎。
- **笔记导出更清晰**：原文使用“原文：【……】”，Markdown 在此基础上突出笔记内容，标注创建或最后修改时间。
- **更新来源选择**：检查更新和下载界面可选择 GitHub 或 Gitee，默认优先 GitHub；网络请求失败时回退镜像，并保留大小与 SHA-256 校验。
- **翻译阅读体验**：全文翻译的停止操作移至工具栏，避免遮挡正文。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.6) · [Gitee 安装包](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.6)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议备份书库。Android 沿用原签名；macOS 退出旧应用后，使用 DMG 拖入应用程序覆盖安装。

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 使用 ad-hoc 签名，未做 Apple 公证。
- Windows 需 WebView2 Runtime；安装器没有商业 Authenticode 签名。
- Linux DEB 面向 Debian 13，请使用 APT 安装依赖。
- iOS IPA 需用自己的有效签名配置签署主应用及 Share Extension 后安装。

Gitee 先移除旧应用发行版，再上传同一批 GitHub 原包；校验通过后更新下载清单。GitHub 保留历史发行版及源码标签，独立模型镜像不变。

对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.6) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.6.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.6/docs/RELEASING.md)。许可与版权信息见同标签 LICENSE、NOTICE、UPSTREAM.md 和 LICENSES。

## English

Modu **1.1.6 (build 10049)** adds paragraph-based online narration with accurate group highlighting and navigation, priority synthesis and rolling prefetch during playback to reduce pauses between paragraphs. MiMo playback speed follows the reader slider; compatible speech services gain editable voice instructions and consistent narration guidance. Pause/resume and background chapter transitions are improved. Selection-search scrolling and compact toolbar layout are fixed, and version details reflect the installed package.

Manage 32 CSS profiles and 13 presets with visual controls in Settings, search selected text in the built-in browser, and export clearer notes with bracketed source text and timestamps. Update checks and downloads offer GitHub/Gitee selection, preferring GitHub by default. Full-text translation controls no longer cover the text.

Global settings transfer supports files, QR images and modu links, including explicit defaults and validation before restore. A separate switch controls accounts, passwords and API configurations in both directions and is off by default. Explicit exports containing credentials are unencrypted; keep them private. WebDAV credential encryption and its local password remain separate.

Upgrade in place after backing up. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows requires WebView2, and iOS requires your own valid signing. Gitee receives identical, hash-verified GitHub packages.
