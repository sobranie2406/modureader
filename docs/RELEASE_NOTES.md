# 默读 / Modu 1.1.5 正式版

版本：**1.1.5+10046**。基于 Anx Reader 和 ReadAny（Reader Any）的 GPL-3.0-or-later 独立修改版本，保留原作者版权与许可。

## 本次更新

- **全局设置迁移**：在“设置 → 高级 → 全局设置备份”集中导入、导出，支持文件、二维码和 `modu:` 链接，可选择全部或 AI、朗读、同步、远程书库配置。原有分散入口合并。账号、密码和 API Key 默认不导出，可选择包含；主动导出的文件、链接和二维码不加密，请勿公开分享。WebDAV 敏感配置同步仍使用同步密码加密、解密，不迁移同步加密密码。大配置请用文件迁移。
- **CSS 与文字高亮规则**：8 套命名方案支持独立开关、组合启用与导入导出，提供 13 个可编辑预设模板。支持正则匹配文字并设置样式，可限定全部、标题或正文范围；规则执行有超时与数量限制。不支持高亮 API 的环境会提示，不修改书籍原文。
- **MiMo 语音设置**：增加官方音色选择、6 套朗读风格模板、5 套音色设计模板和 8 个可追加的常用提示词。描述可编辑，保存后生效，不混入正文朗读；文字设计模式关闭正文自动润色，描述随全局设置迁移。
- **朗读控制**：选中文字后通过“朗读”从指定位置开始；上一句、下一句保持控制栏，暂停时可连续定位。改进锁屏暂停后的恢复与媒体控制命令顺序，避免延迟暂停覆盖恢复操作。高亮或可选位置元数据异常不再连带中断有效正文；真正的网络、合成或播放错误仍保留位置供重试，不静默跳过正文。
- **字体与阅读加载**：字体加载失败时使用通用字体继续显示；兼容部分 EPUB 的 Kindle 字体声明，避免未选择自定义字体也被错误阻断。优化已加载字体检查和重复样式刷新，取消“正在加载章节与字体”遮挡提示，保留真正的加载错误与重试入口。

## 升级与下载

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.5) · [Gitee 安装包镜像](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.5)

覆盖升级即可，**不要先卸载或清空数据**，升级前建议导出书库备份。Android 沿用原签名。更新检查与下载优先 GitHub，连接、超时、TLS 或 HTTP 请求失败后尝试 Gitee；完整性校验失败不会绕过校验安装。macOS 安装包继续交由外部浏览器下载。

Gitee 只存放安装包、说明和更新清单，不上传应用源码。先删除旧发行版和附件，再上传本次 GitHub 原包；逐包核对大小及 SHA-256 后才更新自动更新清单。切换期间镜像可能短暂不可用。GitHub 保留 1.1.0 起的历史发行版；不删除源码标签、分支或独立模型镜像。

## 平台与签名

九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64，各附 SHA-256。

- macOS 为 ad-hoc 签名，未经 Apple 公证；退出旧应用后使用 DMG 覆盖安装。
- Windows 附对应架构 VC++ CRT，仍需 WebView2 Runtime，暂无商业 Authenticode 签名。
- Linux 面向 Debian 13，不保证其他发行版兼容。
- iOS IPA 没有分发签名，需要自行合法签署主应用及 Share Extension，不能直接安装。
- 向量模型仍按需下载，不内嵌模型，不恢复已取消的向量索引 WebDAV 同步。

对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.5) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.5.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.5/docs/RELEASING.md)。许可与来源见同标签 LICENSE、NOTICE、UPSTREAM.md、LICENSES 和依赖锁文件。

正式发布由完整构建、架构与签名检查及 CI 回归把关。自动化测试不代表所有设备、语音服务或网络条件下均经过实测。针对朗读高亮异常已增加回归，但用户报告的特定手机段落停顿尚未在原机确认消除；MiMo 新增模板未调用真实付费接口试听。

## English

Modu **1.1.5 (build 10046)** centralizes settings transfer in Global settings backup, with files, QR images and `modu:` links. Credentials are opt-in and explicit exports are unencrypted; encrypted WebDAV credential sync remains separate. Large configurations should use file export.

Eight CSS profiles can be independently combined, imported and exported, with 13 editable templates and bounded regex text-highlighting rules. MiMo adds official voice selection, editable style/voice-design templates and prompt suggestions without rewriting book text. Speech supports reading from a selection, persistent sentence navigation and improved lock-screen resume ordering. Optional highlighting/location failures no longer interrupt valid speech text; real audio/network failures still pause for retry.

Font failures fall back to a generic font, malformed Kindle font declarations are handled, redundant font/style work is reduced, and the intrusive loading notice is removed. Actual errors retain retry feedback.

Install in place and back up first. Nine packages cover Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is not notarized, Windows has no commercial signing, and iOS requires your own signing. Gitee receives identical GitHub artifacts; its manifest is updated only after hash verification. Device-specific reported speech stalls remain subject to real-device confirmation, and MiMo templates have not been auditioned using a live paid API.
