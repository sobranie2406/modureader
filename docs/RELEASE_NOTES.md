# 默读 / Modu 1.1.3 正式版

版本：**macOS 1.1.3+10037；其他平台 1.1.3+10036**。基于 Anx Reader 和 ReadAny（Reader Any）的 GPL-3.0-or-later 独立修改版本，保留原作者版权与许可。

## macOS 修订包（10037）

- 修复调节应用亮度后无法鼠标选字、点击、翻页或使用方向键的问题。改为不接收鼠标事件、不改变焦点的原生调光层。
- Mac 更新包改用外部浏览器下载，避免应用沙盒下载引发“应用程序无法打开”。仍优先 GitHub，连接失败尝试 Gitee，并提供手动镜像入口。浏览器下载交由浏览器处理，应用不声称已验证或安装该文件。
- 仅替换 macOS ARM64、Intel DMG 及校验文件；其他平台保持原包。**已安装 1.1.3 的 Mac 用户请使用浏览器重新下载并覆盖安装**，不要使用旧版应用内缓存的 DMG；同版本构建号更新不会触发现有客户端的版本提示。不要卸载或清空数据。
- 仍为 ad-hoc 签名，未经 Apple 公证；此修改不等同于 Developer ID 签名或公证。
- macOS 完整对应源码使用独立标签 [macos-1.1.3-10037](https://github.com/sobranie2406/modureader/tree/macos-1.1.3-10037)（[源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/macos-1.1.3-10037.zip)）；原 v1.1.3 标签保留给其他平台，不移动。

## 本次修复

- **朗读故障与通知权限**：Edge 正文朗读不再修改服务的只读配置，并延长正文合成等待时间；同名系统声线使用“名称＋语言区域”独立选择，旧设置自动迁移。Android 声明通知权限，在首次前台朗读时申请，拒绝不阻止朗读、不反复申请；设置 → 朗读新增系统通知管理入口。系统设置开关的厂商行为仍需实机验证。
- **TXT 笔记导出**：摘录与笔记以横线和“笔记”标签分隔，笔记末尾标注最后修改时间，未修改时显示创建时间，精确到分钟并使用本机时区；旧记录缺少时间时明确标记未知。不改变 Markdown、CSV 和复制格式。
- **通知栏朗读播放器**：显示“正在朗读/已暂停”、书名和当前章节；上一段、播放/暂停、下一段、停止退出四个控制，暂停时保持可用。章节信息直接跟随朗读游标，后台跨章无需等待阅读页刷新。通知外观及按钮布局由系统决定；停止朗读不会退出应用。
- **紧凑亮度面板**：左侧自动亮度（跟随系统），中间滑杆调节 APP 亮度，右侧夜间模式切换阅读页暗色配色。手动拖动关闭自动亮度；夜间模式独立于亮度，不覆盖原有配色、背景图和自动主题设置，关闭后恢复。不会修改系统亮度。
- **中英文独立字体**：阅读样式新增英文字体选择，默认跟随正文；可单独导入并应用 TTF/OTF。使用字符范围区分拉丁字母、数字与汉字、中文标点，兼容横排、竖排和注释。仅覆盖英文时保留书籍自身的中文字体，不拆分文字节点，不改变批注定位。固定版式 PDF 不重排字体。
- **8 套自定义 CSS 方案**：支持独立命名、编辑和切换，可分别保存竖排、横排、精排等样式。每本书在本机记住自己的选择，也可跟随默认或把当前方案设为默认。旧 CSS 自动保留在第一套；切换方案前保存当前编辑。方案共享，修改会影响使用该方案的书籍；选择方案不自动改变阅读方向。
- **更新检查自动切换镜像**：仍优先 GitHub；DNS/连接失败、连接重置、超时、TLS 握手或证书失败，以及任意 HTTP 请求错误（包括 401、403、404、407、429、5xx）均自动尝试 Gitee。不再因 GitHub 返回普通 403 而停留在“服务器限制请求”。
- **安装包下载同样回退**：GitHub 下载遇到上述错误时，清理部分文件，从 Gitee 重新下载同版本、同架构安装包。两站使用同一次构建的原始文件。
- **安全校验保留**：切换来源不会关闭 HTTPS 证书验证。无效更新清单、不安全重定向、SHA-256/大小不符、主动取消、磁盘或程序错误仍停止，不绕过校验安装。
- **错误提示准确区分**：明确限流和普通拒绝访问分别显示；两个来源都失败才提示失败，不误报“已是最新版”。
- **镜像发布顺序固定**：Gitee 每次先删除旧应用发行版及附件，再上传新版；仅保留最新正式版。GitHub 保留 1.1.0 起的历史版本。不删除源码标签、分支或独立模型镜像。镜像切换期间可能短暂不可用，全部安装包校验通过后才更新自动更新清单。

本次保留 1.1.2 的字体导入自动应用、阅读亮度调节、向量化前置校验、竖排阅读与数据迁移等功能。向量模型不内嵌，仍从 Hugging Face（默认）或 Gitee 按需下载。

## 升级说明

旧客户端若已经无法检查更新，请手动下载安装包覆盖升级；新的回退逻辑需升级后生效。**不要先卸载或清空应用数据**，升级前建议导出书库备份。

本次替换先前的 1.1.3+10035 安装包。已安装该构建的用户请手动覆盖升级到 10036；同版本构建号更新不会触发现有客户端的版本提示。

## 下载与完整对应源码

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.3) · [Gitee 安装包镜像](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.3)

Gitee 仅存放安装包、说明与更新清单，不上传应用源码。每个安装包附 SHA-256；镜像从公开下载入口逐包验证大小与摘要，确保与 GitHub 相同。没有验证完成的镜像不宣称发布完成。

免费完整对应源码：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.3) · [源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.3.zip) · [构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.3/docs/RELEASING.md)。许可与来源见同标签的 LICENSE、NOTICE、UPSTREAM.md 和依赖锁文件。

## 平台与验证范围

共九个安装包：Android ARM64/x64、macOS ARM64/x64、Windows ARM64/x64、Linux ARM64/x64、iOS ARM64。

- Android 沿用原签名，安装需系统确认。
- macOS 为 ad-hoc 签名，未经 Apple 公证；退出旧应用后使用 DMG 覆盖安装。
- Windows 附对应架构 VC++ CRT，仍需 WebView2 Runtime，暂无商业签名。
- Linux 面向 Debian 13，不保证其他发行版兼容。
- iOS IPA 未分发签名，需要自行合法签署主应用及 Share Extension，不能在应用内直接安装。

本次更新相关 49 项自动化测试通过，覆盖 GitHub 优先、网络/HTTP/TLS 回退、取消、无效清单、下载完整性及界面交互。正式发布由全平台构建及 CI 质量检查共同把关；模拟故障不等于所有网络和设备实测。

## English

Modu **1.1.3 (build 10036)** adds eight named, editable CSS profiles with per-book choices on this device, a shared default and automatic preservation of legacy CSS in the first slot. Editing a shared profile affects books using it; choosing a profile does not automatically change reading direction. Users on build 10035 should manually upgrade in place because existing clients do not notify about build-only updates.

Chinese/body and English fonts can now be selected separately. English follows the body face by default; independent imports affect only English. Unicode ranges retain Chinese glyphs and punctuation, including publisher faces, in horizontal/vertical reflowable text and footnotes. No text-node splitting is used, preserving selection and annotation anchors. Fixed-layout PDFs are not re-typeset.

This release also fixes GitHub-to-Gitee update fallback. Checks and downloads still prefer GitHub, but any network, timeout, TLS or HTTP request failure now tries the official Gitee mirror, including ordinary HTTP 403/404 responses. Downloads restart cleanly against the same version, architecture, size and SHA-256.

HTTPS verification remains enabled on both sources. Invalid metadata, unsafe redirects, integrity failures, cancellation, storage and programming errors never bypass validation. Rate limits and access denials are distinguished; failure is not reported as “up to date”.

Gitee publication now always removes old application releases and attachments **before** publishing the new release. A short mirror gap is possible; update metadata is published only after all packages pass verification. GitHub keeps releases from 1.1.0 onward. Source tags, branches and the separate model mirror are preserved. Gitee carries binaries/docs/metadata only; [free corresponding source](https://github.com/sobranie2406/modureader/tree/v1.1.3) and [source ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.3.zip) remain on GitHub.

Older clients affected by the update-check bug may require one manual in-place upgrade. Back up first; do not uninstall or clear app data. Models remain on demand. Nine packages target Android, macOS, Windows and Debian 13 on ARM64/x64, plus iOS ARM64. macOS is unnotarized, Windows lacks commercial signing, and iOS requires your own signing. All 49 update-focused tests pass; platform builds and CI checks gate publication.
