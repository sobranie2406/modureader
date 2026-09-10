# 默读 / Modu 1.0.2 正式版

版本：**1.0.2+10004**。本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留上游版权与许可，按 GPL-3.0-or-later 发布，是独立修改版。

## 本次更新

- **WebDAV 记录级合并**：书籍、笔记、书签、分组、标签使用跨设备标识合并，不再按整库文件时间覆盖本机数据库。阅读位置采用最近一次操作而非最远进度；新增阅读时长按事件去重，删除保留标记。字体、主题图片、本机偏好和向量索引不参加书库同步。
- **同步失败与并发保护**：鉴权、网络或解析失败不再误当成远程空库。下载核对元数据，上传使用强 ETag 和条件请求；冲突后重新拉取合并，失败时不无条件覆盖。书籍正文按需下载，书架出现记录不代表全文已经离线可用。
- **启动与字体**：修复数据库迁移期间重复开库；正确处理含中文、空格等字符的本地字体路径及样式转义。
- **翻译界面**：阅读页翻译入口移到上方 AI 旁；选词结果限制标题字号，正文统一排版，长译文在与 AI 对话同规格的弹窗内滚动。
- **远程书库排序筛选**：按名称、服务器添加/修改时间、文件大小升降序排列；支持搜索和格式筛选，缺失日期保持未知。
- **书库 WebDAV 配置迁移**：独立设置支持 `modu:` 代码、二维码展示及图片读取。导入只填写表单，不自动连接或保存。**默认导出密码，可取消勾选；代码和二维码未加密，切勿公开。**
- **移动端仅点击翻页**：阅读样式 → 更多设置 → 其他新增开关，默认关闭。开启后分页模式下滑动、拖动不翻页，也不触发上下拉手势；关闭后恢复滑动。选词、快速标记和滚动模式不受影响。移动端分页同时抑制原生自由拖动。

## 升级前请备份：同步数据库迁移

1. 暂停旧客户端同步，备份各设备和服务器的 `modu` 目录，再将所有同步设备升级至 **1.0.2**。不要让旧整库同步客户端继续写入旧库。
2. 配置仍指向 `modu` 的上级目录，所有设备使用同一地址，**不要重复拼接 /modu**。更早使用 anx / Anx 的版本仍需备份后迁移目录，不要覆盖已有 modu。
3. 首次缺少 `modu/database8.db` 时，新版读取旧 `database7.db` 的临时副本，与本机记录合并后建立新库；旧文件不覆盖、不删除。新库出现后不再反复导入旧库。
4. 服务器须正确支持**强 ETag、If-Match 和 If-None-Match**；不满足要求时会停止更新并报错，不会降级为不安全覆盖。
5. 旧累计阅读时长按同书同日取两端较大值，再加升级后的独立事件。升级前没有保存的事件及删除历史不能精确还原；已丢失的笔记不能凭空恢复。设备应开启自动校时。
6. 云端新文件是同步记录容器，不是可直接覆盖本机数据库的完整备份。为保护离线设备，暂不自动清理云端未引用书籍文件。

详细规则见 [WebDAV 记录合并与迁移](https://github.com/sobranie2406/modureader/blob/v1.0.2/docs/WEBDAV_RECORD_SYNC.md)。API Key 同步仍是独立、默认关闭的开关，以 AES-256-GCM 加密敏感配置，各设备需要同一独立密码；**书籍、笔记和整个数据库并不因此全部加密**。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | 沿用项目专用签名的 APK，可覆盖升级，不要先卸载旧版 |
| Windows | x64 / ARM64 | EXE，附带 VC++ CRT，需要 WebView2 Runtime，无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，使用 APT 安装，不保证其他发行版兼容 |
| macOS | Intel x64 / Apple Silicon ARM64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| iOS | ARM64 真机 | iOS 16+ 未签名 IPA，须自行合法签署主应用和 Share Extension，不能直接安装 |

共 **9 个程序包**，均附 SHA-256，不再提供独立 notices ZIP。许可证保留在应用包及源码仓库中，参见本版本的 [LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.2/LICENSE)、[第三方许可证](https://github.com/sobranie2406/modureader/tree/v1.0.2/LICENSES)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.2/NOTICE)、[来源说明](https://github.com/sobranie2406/modureader/blob/v1.0.2/UPSTREAM.md)及[对应源码](https://github.com/sobranie2406/modureader/tree/v1.0.2)。文件名省略签名状态后缀，实际安装限制仍如上表。没有 x64 iPhone 真机包，不包括应用商店或 TestFlight 发布。构建号 10004 高于本地测试包 10002、10003。

## 验证范围、已知问题与未验证项

- 本次发布前重新执行 Flutter 回归：**427 项通过、3 项跳过**（私人字体样例和两项需显式开启的在线测试）；阅读器 JavaScript **58 项通过**，打包校验 **27 项**、项目标识 **6 项**通过。此前提供私人字体样例时为 428 项通过、2 项跳过。本次标签 CI 再次执行回归，最终结果以对应 GitHub Actions 为准。
- 相同功能代码的本地 **1.0.1+10002** 曾在 macOS ARM64 与 HONOR Magic4 Pro / Android 15 实测双向阅读位置同步、回读较前位置及无修改重复同步；仅使用演示书，没有实测双端同时编辑真实笔记、断网竞争或大书库性能。
- 本地 **1.0.1+10003** 在上述安卓实机验证了仅点击翻页、横纵拖动不翻页、关闭后恢复滑动及重启读取设置。Mac 确认了启动、书架、正文与本地字体显示；截图曾短暂显示正文空白，重新打开后正常，原因尚未确定。Mac 自动化点击/按键响应不稳定，未取得可重复的翻页通过证据。
- 上述真机验证针对先行测试包，**不冒充最终 1.0.2 的全平台真机验收**。CI 执行各平台构建、架构/安装器校验、Windows 与 Debian 安装检查，以及 Android 36 x86_64 模拟器四个内嵌模型的 Release 推理测试；通过不代表全部业务无缺陷。
- 远程书库二维码/代码跨设备迁移、用户服务器长期兼容性、所有字体和在线 AI/翻译/TTS 未完成全面端到端验证。服务器添加时间可能缺失。
- **iQOO Neo8 / Android 16 与用户原 EPUB 的长书索引仍需复测**，不宣称解决所有向量化闪退。可通过设置 → 提交 Bug，勾选环境及脱敏崩溃诊断，预览后提交。
- Linux 没有系统 TTS 后端，应选择在线语音；新安装未选系统声音时可能需要先获取、选择声音。在线服务可能限流或变化，并会收到相关文本；本地向量计算不代表整个 AI 流程离线。
- 切勿上传个人书籍、密钥、完整配置代码/二维码或未经预览的日志。安装器不含开发机的应用数据备份。

## English release notes

**Modu 1.0.2 (build 10004)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny, retaining upstream attribution and licenses.

### Changes

- Record-level WebDAV merging replaces whole-database replacement: stable identities, latest reading actions, deduplicated new reading-time events and deletion markers. Fonts, theme images, device preferences and vector indexes stay local.
- Authentication/network errors are no longer treated as an empty server. Strong ETags and conditional requests protect concurrent writes, with bounded re-fetch/merge retries and no unconditional fallback.
- Fix database initialization and local font paths containing spaces or non-ASCII characters.
- Move translation next to AI; cap heading sizes and show long results in a scrollable popup sized like AI chat.
- Sort remote books by name, server creation/modification time or size in either direction, with search and format filters. Missing dates remain unknown.
- Transfer separate library WebDAV settings using `modu:` codes and QR images. Import only fills the form. **Password export is on by default and can be disabled; codes/QRs are not encrypted.**
- Add a mobile **Tap-only page turning** switch, off by default. In paginated mode it blocks swipe/drag page turns and pull gestures while preserving taps. Selection, Quick mark and scrolling mode remain available.

### Sync migration

Pause old clients and back up every device and the server before upgrading all syncing devices to 1.0.2. Use the same parent endpoint without appending /modu twice. Database 8 initially imports a temporary copy of database 7 when needed, merges it with local records and leaves the old server file untouched. Do not keep old clients writing the legacy database.

Servers must correctly support strong ETags and conditional writes; otherwise updates stop safely. Legacy daily reading totals use the greater value per book/day, then add new independent events. Missing historical events, deletions and lost notes cannot be reconstructed. Keep device clocks synchronized. The new server database is a sync container, not a full local-app backup. Unreferenced server book files are not automatically removed.

### Packages and verification limits

Nine application packages: Android ARM64/x86_64 APK, Windows x64/ARM64 EXE, Debian 13 x64/ARM64 DEB, Intel/Apple Silicon macOS DMG, and iOS ARM64 IPA. Android retains its signing identity. macOS is unnotarized, Windows has no commercial code signature, and iOS requires your own valid signing. SHA-256 files accompany all packages. Filenames omit signing-status suffixes; this does not change their actual signing status. Licenses remain bundled and in the tagged source repository linked above; no separate notices ZIP is published.

Pre-release checks passed **427 Flutter tests (3 skipped: a private font fixture and two opt-in live tests), 58 reader JavaScript tests, 27 packaging tests and 6 project-identity tests**; the tag workflow reruns checks. The earlier 428/2 result included the private font fixture. Local builds 10002/10003 exercised Mac/Android reading-position sync and Android tap-only navigation on HONOR Magic4 Pro / Android 15. They are not final 1.0.2 all-platform acceptance tests. Mac text and local fonts rendered after reopening, but a prior blank capture and unreliable automated navigation remain unconfirmed issues.

CI checks native packages and targeted model inference, not every feature. Long EPUB indexing on the reported iQOO / Android 16 device, large libraries, concurrent offline use, complete QR migration and all online providers remain unverified. API-key sync is separately enabled and encrypted; books, notes and configuration codes are not thereby encrypted. Review diagnostics before sharing and never publish private books or credentials.
