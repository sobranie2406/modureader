# 默读 / Modu 1.0.8 正式版

版本：**1.0.8+10026**。来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留原作者版权与许可，是 GPL-3.0-or-later 独立修改版本。

## 本次更新

- **注释字号**：弹出注释框文字调整为正文字号的 80%，继续保留屏幕 25% 面积上限、底部留白和长注释滚动。
- **WebDAV 同步**：同步记录目录及分片目录忽略明确的系统辅助文件 `.DS_Store`、`Thumbs.db`、`desktop.ini`，避免浏览服务器目录后出现“同步数据格式或完整性校验失败”。只忽略这些确切名称的普通文件；未知文件、异常目录及真实同步数据的格式、哈希和完整性校验仍保留。无需清空 WebDAV，也无需删除同步数据库。
- **翻译结果**：过滤 AI 返回的 `<think>` 思考内容，避免写入书籍译文。处理大小写、分段输出及不完整标签，未结束的思考内容不会展示为译文。
- **翻译控制**：提供明确的停止翻译入口，停止后取消请求并丢弃迟到结果；关闭书籍或重开应用不会自动恢复上次翻译任务。翻译优先处理当前可见段落，避免启动时同时提交大量整章内容。
- **书内搜索**：输入关键词后只列出结果，不自动跳到第一处，也不改动原阅读位置。点击结果或上一处/下一处才跳转，保留返回原处、匹配计数及关闭按钮。
- **替换书籍后的远程文件**：对新版记录到的明确文件替换，在同步完成、核对两端引用及文件内容后，将不再被引用的旧文件从 `modu/data/file/` 移出。先保存并验证 `modu/replaced-files-v1/` 下的恢复副本，再删除原路径；失败则延后处理，不影响已完成的数据同步。不会按文件名猜测或批量清除无法确认来源的历史文件。**恢复副本仍占用云端空间，本次不是永久清理功能。**
- **特殊文件名**：修正 WebDAV 删除请求中中文、`#`、`%` 等文件名的路径编码。
- 继续内嵌四个离线 ONNX 模型及分词器，自动向量化默认关闭。

## 升级与同步注意事项

建议先备份并覆盖安装。Android 沿用原项目专用签名；参与同步的设备建议全部升级，旧客户端仍可能被系统辅助文件阻断。本次不更改已有书籍、笔记和阅读位置的同步格式。

各端使用相同的 modu 上级目录，不重复拼接 /modu。**不要删除 modu/record-log-v1/ 或旧数据库**。旧于 1.0.5 的客户端不能识别无可靠 ETag 的兼容记录通道，升级期间请暂停旧版自动同步。[记录同步说明](https://github.com/sobranie2406/modureader/blob/v1.0.8/docs/WEBDAV_RECORD_SYNC.md)。

API Key 和远程书库凭据仍按默认关闭的独立加密开关同步，不代表整个书库已加密。字体和本地向量索引不参与同步。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，Android 8+ |
| macOS | ARM64 / Intel x64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| Windows | x64 / ARM64 | EXE，附带 VC++ CRT，需要 WebView2 Runtime，无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，不保证其他发行版兼容 |
| iOS | ARM64 真机 | iOS 16+ IPA，须自行合法签署主应用及 Share Extension，不能直接安装 |

全平台发布包含 **9 个程序包及各自 SHA-256**。许可保留在包内和源码中，不另附 notices ZIP。不包含应用商店或 TestFlight 发布。

## 验证范围与限制

- 本地 Flutter **717 项通过、5 项跳过**，阅读器 JavaScript **163 项通过**。
- 同步测试覆盖两类写入能力、根目录及分片中的系统辅助文件，并确认未知文件、同名目录和损坏的真实记录仍被拒绝。
- 回归测试覆盖翻译停止/重启/迟到结果隔离、搜索结果不自动跳转、替换文件引用检查、恢复副本校验及失败重试。
- 发布由全平台构建、安装包架构/校验和检查和 CI 回归共同把关，全部通过后才创建正式发布。执行记录见 [Actions](https://github.com/sobranie2406/modureader/actions)。
- 本次回归不等于各平台的全部实机验收，也不代表已验证长期多端并发。恢复副本用于降低不参与新版协议的旧客户端并发写入风险；清理与云端更新不是一个跨文件原子事务。
- 在线 AI、翻译和 TTS 取决于服务商；Linux 无系统 TTS 后端，需选择在线语音。连续滚动仍限横排流式书籍；固定版式、竖排及开启书籍脚本的内容沿用对应阅读路径。

来源与许可：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.8/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.8/NOTICE)、[UPSTREAM](https://github.com/sobranie2406/modureader/blob/v1.0.8/UPSTREAM.md)、[对应源码](https://github.com/sobranie2406/modureader/tree/v1.0.8)。

## English release notes

**Modu 1.0.8 (build 10026)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.

- Display footnotes at 80% of the reader font size, retaining the 25%-of-screen area cap, end padding and scrolling for longer notes.
- Ignore exact known system sidecar files (`.DS_Store`, `Thumbs.db`, `desktop.ini`) in the WebDAV record log and its shards. Unknown files, directories and corrupt records still fail validation. Do not clear your remote library or delete synchronization databases.
- Remove AI `<think>` output from translations, including partial streamed reasoning. Add explicit stop controls, cancel requests and reject late results. Reopening a book or the app does not restart translation. Translate visible paragraphs serially instead of eagerly submitting whole chapters.
- Show search results without automatically navigating to the first match. Navigate only when a result or previous/next match is selected; retain return-to-origin controls and match counts.
- Track explicit book-file replacements made by this version. After successful synchronization and reference/content checks, preserve a verified recovery copy outside `data/file` before removing the obsolete path. Unknown historical files remain untouched. Recovery copies still consume cloud space; this is not permanent garbage collection.
- Encode special characters correctly in WebDAV deletion paths. Keep all four offline embedding models bundled.

Nine native packages with SHA-256: Android ARM64/x86_64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB and iOS ARM64 IPA. Android retains its signing identity. macOS is unnotarized, Windows has no commercial signature, and iOS requires your own valid signing. Licenses remain inside packages.

Back up before upgrading and update all syncing devices. Clients older than 1.0.5 cannot read the compatible record log. Do not delete remote history or legacy databases. Optional encrypted credential sync does not encrypt the whole library.

Local checks: 717 Flutter tests passed, 5 skipped; 163 reader JavaScript tests passed. CI gates publication on builds, regression tests and package verification. These checks do not replace physical-device or prolonged multi-device concurrency testing. Recovery copies mitigate legacy-client races; cleanup and remote updates are not a single cross-file atomic transaction.
