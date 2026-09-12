# 默读 / Modu 1.0.5 正式版

版本：**1.0.5+10017**。本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留原作者版权与许可，是按 GPL-3.0-or-later 发布的独立修改版本。

## 本次更新

- **防止旧页面覆盖同步进度**：锁屏、退后台和关闭阅读器不再用缓存位置刷新阅读时间，只保存实际阅读操作。事务内检查位置版本，拒绝旧页面回写并刷新阅读位置。主动往回阅读仍正常保存，不采用“最远进度”规则。
- **笔记冲突保护**：同步后刷新打开的阅读器和笔记。保存时核对原记录，冲突时保留草稿并提示，不覆盖新版笔记、不恢复已删除笔记。调整划线颜色不顺带覆盖新摘录。
- **无可靠 ETag 的 WebDAV 兼容**：用独立合成文件验证服务器条件写入能力；可靠服务继续使用 ETag。其他服务使用内容散列命名的独立记录批次，不无条件覆盖共享数据库。中断上传持久排队，上传后读回校验；ETag 恢复后仍合并兼容记录。
- **章节切换优化**：保留相邻章节资源预取，新章节字体和布局准备好再替换旧页面，避免默认字体闪现和重复排版。去掉切章固定等待和滑入空白边界的动画；墨水屏模式禁用翻页动画。仍需加载与排版，不保证零延迟。
- **纳入此前 10016 修正**：兼容 Anx 导入的空阅读位置与越界进度；修正书末翻页边界；改善跨平台临时选区和焦点；书籍菜单支持单独选择向量模型，未选择时跟随默认。
- **保留四个内嵌模型**：MiniLM、BGE-en、BGE-zh、E5 及分词器继续随安装包提供，自动向量化默认关闭。

## 升级与同步注意事项

**请先备份，并将所有参与同步的设备升级到 1.0.5；升级期间暂停旧版自动同步。** 旧版不识别新的兼容记录通道，也没有旧页面回写保护，不能保证新旧混用的同步完整性。

各端使用相同的 `modu` 上级目录，不重复拼接 `/modu`。保留旧数据库，不需要手动改名或清空服务器。新增的 `modu/record-log-v1/` 是同步数据，**不要删除**。批次与本地缓存暂不自动压缩，会逐渐增长，达到安全扫描限额时明确停止而不是忽略数据。详情见[记录同步说明](https://github.com/sobranie2406/modureader/blob/v1.0.5/docs/WEBDAV_RECORD_SYNC.md)。

Android 沿用原专用签名，构建号 10017 高于此前正式及本地版本，可覆盖升级，请勿先卸载。API Key 和远程书库凭据仍只按默认关闭的独立加密同步开关发送；这不代表书籍、笔记和整个数据库已加密。字体和向量索引不参与同步。不要公开配置代码、二维码或密钥。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，Android 8+ |
| macOS | Apple Silicon ARM64 / Intel x64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| Windows | x64 / ARM64 | EXE，附带 VC++ CRT，需要 WebView2 Runtime，无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，不保证其他发行版兼容 |
| iOS | ARM64 真机 | iOS 16+ IPA，无分发签名，须自行合法签署主应用及 Share Extension |

共 **9 个程序包及各自 SHA-256**。不提供独立 notices ZIP，许可保留在包内和源码中。不包含应用商店或 TestFlight 发布。

## 验证范围

- 本地 Flutter 回归 **577 项通过、5 项跳过**；阅读器 JavaScript **105 项通过**。包含可靠与无可靠 ETag 两种通道的双端合成数据库测试、旧页面回写拒绝、真正回退阅读、笔记冲突与草稿保留。
- 合成 HTTP 服务验证 ETag 能力检测与兼容日志；合成章节浏览器验证字体等待、前后切章及滚动布局。未使用个人书籍或真实云端数据进行破坏性测试。
- 发布流程在全平台构建、包校验和自动回归完成后才上传完整附件；具体执行记录见 [Actions](https://github.com/sobranie2406/modureader/actions)。
- **尚未完成本次改动在实际墨水屏、坚果云账号写入及长期多端并发下的验收**。构建与模拟测试不等于所有目标设备实测。在线 AI、翻译及 TTS 依赖服务商，未全面验收全部接口；Linux 无系统 TTS 后端，需选在线语音。

许可与来源：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.5/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.5/NOTICE)、[第三方许可证](https://github.com/sobranie2406/modureader/tree/v1.0.5/LICENSES)、[UPSTREAM](https://github.com/sobranie2406/modureader/blob/v1.0.5/UPSTREAM.md)、[对应源码](https://github.com/sobranie2406/modureader/tree/v1.0.5)。

## English release notes

**Modu 1.0.5 (build 10017)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.

- Prevent a suspended reader from rewriting an old position with a new timestamp. Save actual reading actions only; reject stale writes transactionally and refresh the open reader after sync. Deliberate backward reading remains supported.
- Protect newer or deleted notes against stale edits. Keep the draft and show a conflict instead of overwriting another device's changes. Refresh annotations without deleting bookmarks.
- Probe conditional-write correctness using isolated synthetic files. Reliable ETag servers retain conditional database writes; other servers use content-addressed immutable record batches with durable pending uploads and read-back verification. Both paths read the compatible history. Never fall back to unconditional shared-database overwrites.
- Prepare chapter fonts and layout before replacing the visible page. Retain adjacent-resource prefetching, avoid duplicate layout and fixed transition delays, and disable animations in e-ink mode. Chapter changes can still require loading and layout.
- Include earlier build 10016 fixes for nullable/out-of-range Anx progress, book-end navigation, selection/focus and per-book embedding model choices. Keep all four offline ONNX models bundled; automatic indexing remains off by default.

**Back up and upgrade every syncing device to 1.0.5; pause older clients during the upgrade.** Older clients do not understand the compatible record log and lack stale-reader protection. Do not remove `modu/record-log-v1/` or the legacy databases. History and local caches currently grow without automatic compaction; safety limits stop an incomplete scan. Use the same remote parent directory on every device.

Nine native packages with SHA-256: Android ARM64/x86_64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB, iOS ARM64 IPA. Android keeps its signing identity. macOS is unnotarized, Windows has no commercial signature, and iOS requires your own valid signing. Licenses stay inside packages; no separate notices ZIP.

Local verification: 577 Flutter tests passed, 5 skipped; 105 reader JavaScript tests passed. Synthetic dual-device tests cover both transport modes, stale positions, intentional backward reading and note conflicts. CI gates publication on builds and package checks. This is not real-device acceptance on e-ink hardware, live Nutstore write testing or prolonged multi-device concurrency validation. Optional encrypted credential sync remains off by default; it does not encrypt the entire library.
