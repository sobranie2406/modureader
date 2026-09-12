# 默读 / Modu 1.0.4 正式版

版本：**1.0.4+10013**。本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留原作者版权与许可，是按 GPL-3.0-or-later 发布的独立修改版本。

## 本次更新

- **内嵌本地向量模型**：包含 MiniLM、BGE-en、BGE-zh、E5 四个固定版本 ONNX 模型及分词器，校验大小与 SHA-256。首次使用从包内提取到缓存，无需联网下载，有效缓存可复用。默认中文 BGE，自动向量化默认关闭。安装包因此增大，仍保留手动下载兼容入口。
- **Windows 阅读器稳定性**：修复 WebView 空 JavaScript 返回值处理及 Flutter 引擎与 COM 的退出顺序；针对小 TXT、PDF、EPUB 提取路径补充原生回归。个别安装器“文件损坏”反馈未获得下载文件哈希，不能将应用内修复当作该问题的根因确认。
- **相邻章节预加载**：打开章节后延迟预取前后相邻章节资源，最多缓存三个章节，前台阅读优先，过大章节按需加载。字体和页面排版仍需计算，不保证切章零延迟。
- **WebDAV 自动同步恢复**：启动、回前台后延迟约两秒；短暂网络失败有限重试，持续认证拒绝仍明确提示。同步期间的新请求合并排队，避免并行写入。
- **间歇缺失 ETag 的兼容**：PROPFIND 缺少强 ETag 时向同一数据库文件发起 HEAD 补查；必要时重新读取并合并。保持条件写入和有限冲突重试，绝不降级为无条件覆盖。持续缺失时保留本机改动并停止上传；日志区分“无需上传”和“实际发布数据库”。
- **注释显示**：桌面测量实际换行，在阅读窗口面积 **25%** 上限内优先完整展开，不固定成偏宽、偏矮的弹框。过长时允许框内滚动。**桌面与移动端均保留末尾留白**，避免最后一行贴边、裁切。
- **设置名称统一**：「书库 WebDAV」改为「远程书库设置」，配置不变，仍独立于数据同步连接。

## 升级与隐私

构建号 10013 高于 1.0.3 正式版及 10011、10012 本地构建。Android 沿用默读原专用签名，可覆盖升级；请勿先卸载，升级前建议备份。

继续使用数据库 8 的记录级合并，不新增同步格式迁移。所有设备配置同一个 modu 上级目录，不重复拼接 /modu。强 ETag 与正确执行条件写入仍是并发保护前提。[同步与迁移说明](https://github.com/sobranie2406/modureader/blob/v1.0.4/docs/WEBDAV_RECORD_SYNC.md)。

API Key 和远程书库凭据仍跟随独立、默认关闭的加密同步开关，使用单独密码与 AES-256-GCM。书籍、笔记和整个数据库并不因此全部加密。字体、主题图片和向量索引留在各端；显式配置代码与二维码未加密，不要公开。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，Android 8+ |
| macOS | Apple Silicon ARM64 / Intel x64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| Windows | x64 / ARM64 | EXE，附带 VC++ CRT，需要 WebView2 Runtime，无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，不保证其他发行版兼容 |
| iOS | ARM64 真机 | iOS 16+ IPA，无分发签名，须自行合法签署主应用及 Share Extension |

共 **9 个程序包及各自 SHA-256**。不提供独立 notices ZIP；许可证保留在包内和源码中。没有 x64 iPhone 包，不包含应用商店或 TestFlight 发布。

## 验证范围与限制

- 发布流程运行 Flutter、阅读器 JavaScript、打包和项目身份回归测试；各平台构建和包校验通过后才发布完整附件，见 [GitHub Actions](https://github.com/sobranie2406/modureader/actions)。
- 先行 1.0.3+10012 的 macOS ARM64 DMG 与 Android ARM64 APK 已构建，检查过模型资源、架构、签名完整性、Android 16 KB 对齐和 Release DEX 中的 ONNX JNI 接口；这不是最终 1.0.4 所有平台的实机功能验收。
- 合成内容的浏览器验证覆盖短、中、长注释、25% 面积限制和滚动到底的末行；移动端横竖屏及留白有自动回归。尚未在截图原书和所有字体上逐一验证。
- 已授权 WebDAV 只读检查中，多轮认证和强 ETag 读取正常；手机冷启动时的间歇故障没有现场复现。只读检查不能证明条件写入正确，也不能替代长期双端并发测试。
- Windows 先行诊断构建验证了小 TXT/PDF/EPUB 路径；iQOO Neo8 / Android 16 原书长时间向量化及其他厂商偶发退出仍需实机复测，不宣称排除全部卡死或闪退。
- 在线 AI、翻译、TTS 依赖网络与服务商，未全面验收全部接口。Linux 无系统 TTS 后端，需选在线语音。
- 提交问题时可预览并勾选附带脱敏诊断；不要上传个人书籍、密钥或完整配置代码。

许可及对应源码：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.4/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.4/NOTICE)、[第三方许可证](https://github.com/sobranie2406/modureader/tree/v1.0.4/LICENSES)、[来源](https://github.com/sobranie2406/modureader/blob/v1.0.4/UPSTREAM.md)、[v1.0.4 源码](https://github.com/sobranie2406/modureader/tree/v1.0.4)。

## English release notes

**Modu 1.0.4 (build 10013)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.

### Changes

- Bundle four pinned, hash-verified ONNX models and tokenizers for offline use. Valid caches are reused; Chinese BGE remains the default and automatic indexing remains off. Installers are larger; manual download remains a fallback.
- Fix Windows null JavaScript replies and native engine/COM shutdown ordering. Add tiny TXT/PDF/EPUB regression coverage. A reported corrupt installer remains unconfirmed without the downloaded file hash.
- Preload adjacent chapter resources with a bounded three-section cache and foreground priority. Oversized chapters remain on demand; layout can still cause delay.
- Delay foreground automatic WebDAV sync, retry temporary connection failures and coalesce requests. Recover missing ETags through HEAD on the same resource and bounded re-read/re-merge attempts. Never overwrite databases unconditionally.
- Measure desktop footnote wrapping within 25% of the reading viewport. Long notes can scroll; desktop and mobile retain end padding so the last line remains reachable.
- Rename the connection entry to **Remote library settings** without changing stored settings or the separate sync connection.

### Packages, upgrades and privacy

Nine native packages plus SHA-256: Android ARM64/x86_64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB, and iOS ARM64 IPA. Android uses the existing signing identity. macOS is unnotarized, Windows has no commercial signature, and iOS requires your own valid signing. No standalone notices ZIP.

Build 10013 upgrades earlier builds; back up first and do not uninstall Android before updating. Database 8 record sync is unchanged. Use the same remote parent directory on all devices. Strong ETags and correctly implemented conditional writes remain required. Optional credential encryption does not encrypt books, notes or the entire database. Explicit configuration codes and QR images are not encrypted.

### Validation limits

CI runs regressions, native builds and package checks before publishing the complete set. Earlier build 10012 passed macOS ARM64/Android ARM64 package checks, not final all-platform acceptance. Synthetic browser tests cover footnote sizing and end visibility; mobile sizing/padding has regression coverage. The original reported book and every custom font have not been verified.

Authorized WebDAV read-only probes returned valid authentication and stable strong ETags; mobile cold-start failures were not reproduced, and read-only probes do not verify conditional writes. Long-book indexing on the reported iQOO/Android 16 device, all online providers and prolonged concurrent sync still need real-device testing. Review diagnostics and never share private books or credentials.
