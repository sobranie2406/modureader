# 默读 / Modu 1.0.0 正式版

版本：**1.0.0+10000**。来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，是独立修改版，按 GPL-3.0-or-later 发布并保留上游版权与许可。历史 Beta 版本继续保留。

## 功能与本次更新

- 保留本地书架、EPUB/PDF 等格式导入、阅读排版、背景主题、目录、书签、笔记、统计、翻译和朗读。
- 新增首页「远程书库」：连接独立 WebDAV 书籍目录，浏览文件夹、筛选当前目录、下载并导入本地书架。支持进度、取消与重复检查，单文件最多 512 MiB，一次下载一本；离开标签会取消未完成的下载。
- 新增「设置 → 书库 WebDAV」，与原有同步分开，只读取和下载，不修改服务器文件。支持匿名或 Basic 用户名/密码认证；默认 HTTPS，可明确确认风险后允许 HTTP。不跟随重定向，请使用最终目录地址。地址与用户名只保存在本机，不参加设置导出/同步；密码仅本次运行有效，退出后需重填。
- 新增移动端「快速标记」：开启阅读页画笔按钮后，手指直接划选文字，松手保存高亮，不弹出选字菜单。支持同页跨行、反向及跨段落选取；常驻退出按钮恢复普通手势。默认关闭，桌面不显示；已有批注不会被覆盖。PDF、扫描图片与固定版式暂不支持，也不进行拖拽自动跨页。
- 标注传入阅读器改用 JSON 编码，正确处理引号、换行和反斜杠；文件重复检查使用流式 MD5，避免一次读取整本书。
- 保留十个可编辑 AI 阅读技能、各模型独立参数、混合 RAG、书籍排队索引，以及四个内嵌 ONNX 模型和分词器。默认本地中文 BGE，自动索引默认关闭。
- 包含 Beta4 Android 热修复：保留 ONNX Java/JNI 类与构造函数，防止 Release 混淆造成原生方法查找失败。打包检查实际 DEX 定义，CI 对混淆 Release 执行四模型推理测试。
- 保留索引内存优化、完整性检查和异常中断标记、可预览的脱敏崩溃诊断，以及独立开关和加密密码控制的 API Key 同步。

## 安装与升级

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | 项目专用签名 APK，沿用 Beta 签名，可覆盖升级 |
| Windows | x64 / ARM64 | EXE 安装器，附带 VC++ CRT，仍需 WebView2 Runtime；无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，使用 APT 安装；不保证其他发行版兼容 |
| macOS | Intel x64 / Apple Silicon ARM64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| iOS | ARM64 真机 | iOS 16+ 未签名 IPA，需自行合法签署主程序及 Share Extension，不能直接安装 |

本版本提供 **9 个程序包**及 SHA-256。安卓 `-notices.zip` 为许可附件，不是安装包。iPhone/iPad 没有 x64 真机包；未发布 App Store、TestFlight 或 Play Store 版本。更新前请备份重要数据，不要先卸载旧版。独立的 WebDAV macOS 预览版有不同应用标识，不会自动迁移其测试书架。

## 已验证与未验证范围

- 本地 Flutter 回归：296 项通过、2 项跳过。阅读器 JavaScript 回归：27 项通过，包含快速标记、原阅读业务、背景和 TTS。正式源码新增发行附件集合完整性与校验和检查，阻止缺包或混入其他版本。
- Chromium 移动模拟已验证真实触摸的正向、反向跨段划选、CFI 定位还原、无原生 Selection、无误滚动及退出后恢复普通手势。测试使用原创 HTML 和测试保存回调，**不是 Flutter 真机端到端验收**。
- WebDAV 鉴权、中文目录、下载、取消、路径/重定向安全边界与配置保存有自动化测试；macOS 预览界面已启动，但**用户实际服务器以及下载后打开阅读的完整真机链路尚未验收**。
- 全平台构建、安装器检查及原生测试以本次 GitHub Actions 结果为准。构建、单元测试和模拟器推理不等于所有业务功能均已完成真机验收。
- **iQOO Neo8 / Android 16 与原 EPUB 的长书向量化仍需复测**。JNI 修复有针对性检查，但不承诺所有设备和书籍都不会崩溃。可在「设置 → 提交 Bug」勾选环境与崩溃日志，预览后提交。
- 快速标记的 Android/iOS 原生 WebView 真机触摸、屏幕布局与系统中断恢复仍需设备验收。
- Apple 诊断可能延迟；Windows 强杀/fail-fast、Linux 无 systemd-coredump 或权限不足时可能无堆栈。不自动上传诊断，不包含原始内存、正文、密钥或完整用户路径；不能保证捕获所有退出。

## 服务与隐私边界

- API Key 同步默认关闭，独立于 WebDAV 总开关；敏感配置经 AES-256-GCM 加密后写入同步数据库，需要各设备使用同一独立密码。这不是对全部书籍或整个备份的加密。
- 配置代码与二维码不加密，可能包含账号和密钥，勿公开；远程书库连接不加入这些导出。
- 在线 AI、向量、翻译和朗读会向所选服务发送相关文本。Edge TTS 与免费翻译可能限流或改变；付费接口需要有效账户。本地嵌入不代表整个 AI 流程离线。
- Linux 没有系统 TTS 后端，需主动选择在线语音，在线播放仍需目标设备验证。
- 密码 PDF 暂不支持，扫描 PDF 无 OCR，不承诺 DRM 兼容。文字层与排版影响提取。旧版超过 4 MiB 的索引可能需重新索引才能恢复「已索引」标签；原书和旧索引不会为此删除。
- README 仅介绍功能与使用入口；较早 macOS 截图不是所有 API 与设备可用性的证明。

## English summary

**Modu 1.0.0 (build 10000)** is a regular, non-prerelease distribution derived from Anx Reader and ReadAny. Earlier Beta releases remain available. Upstream attribution and licenses are retained under GPL-3.0-or-later.

New features include a read-only **WebDAV remote library** with folder navigation, downloads and local import, plus **mobile quick marking**: enable the pen tool, swipe across text and release to save a highlight. A persistent Exit control restores normal navigation. Existing comments are preserved. Quick marking is off on entry, absent on desktop and unavailable for PDF/fixed-layout books; it does not automatically select across pages. Remote library credentials are separate from sync: only URL/username are stored locally, and its password is session-only. One download at a time, up to 512 MiB; leaving the tab cancels unfinished downloads.

The release retains ten editable AI reading skills, model-specific parameters, hybrid RAG, queued indexing, four bundled ONNX models, translation, TTS and encrypted opt-in API-key sync. It includes the Beta4 Android ONNX JNI/R8 fix, bounded-memory indexing and previewable crash reporting.

Local regressions: **296 Flutter tests passed, 2 skipped; 27 reader JavaScript tests passed**. Chromium touch tests covered reverse/cross-paragraph selection, CFI round-tripping and restored scrolling, using a synthetic page rather than an end-to-end Flutter device run. Real Android/iOS quick-mark acceptance, user WebDAV compatibility and long-book indexing on the reported iQOO device remain unverified. CI documents package builds and targeted checks, not universal feature acceptance.

Packages: Android ARM64/x86_64 APK; Windows x64/ARM64 EXE; Debian 13 x64/ARM64 DEB; Intel/Apple Silicon macOS DMG; iOS ARM64 **unsigned IPA**. Android retains its original signing key. macOS is unnotarized; Windows has no commercial code signature; iOS requires your own valid signing and cannot install directly. Back up data before upgrading. License ZIPs are attachments, not installers. Checksums and corresponding source accompany the release.

Remote services receive the relevant text. API-key sync is separately enabled and encrypted, but configuration codes/QRs are not encrypted. Do not include credentials, private books or unreviewed diagnostics in public issues.
