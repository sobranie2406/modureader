# 默读 / Modu 1.0.1 正式版

版本：**1.0.1+10001**。本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，是保留上游版权与许可的独立修改版，按 GPL-3.0-or-later 发布。

## 本次更新

- **每模型关闭推理**：新建或编辑 AI 模型时可选择「推理强度 → 关闭推理」。全文翻译遵循所选模型参数，适配不同服务的关闭字段。能否关闭取决于模型和接口，不保证所有服务支持或一定提速。
- **移动端连续高亮合并**：翻页后继续划选时，同一章节文档内首尾相连、同色且无批注的高亮合并为一条。支持反向、重叠及补齐间隔；中间漏字、隔有图片、不同颜色或已有批注时保持独立。不是拖拽自动翻页，不跨章节文件合并，PDF/固定版式不支持。
- **移动端内嵌图片适配**：可重排阅读页面按可用宽高等比缩小图片，处理图片容器固定尺寸；旋转或窗口变化时重新计算，桌面排版不变。
- **注释框自适应**：随内容调整宽高，外框面积不超过当前可见阅读窗口的 25%；长注释可在框内滚动，短注释自动收缩。
- **跨章节连续朗读**：切章暂时被翻页锁阻挡时等待并重试同一章，从空章或章末开始时继续下一章。系统和在线语音衔接下一章标题与正文；WebView 无有效返回不再误判为全书结束。保留手动停止、定时停止及失败暂停。
- **WebDAV 同步目录改为 `modu`**：数据库、书籍、封面、单书下载及连接测试统一使用该目录，与独立「远程书库」的用户自选目录无关。

## 升级必读：WebDAV 目录迁移

本次修改应用同步路径，**不会自动重命名、合并或删除服务器上的旧 `anx` / `Anx` 目录**，也不会自动从旧目录读取数据。

1. 暂停所有设备的 WebDAV 同步，备份本地数据及服务器旧同步目录。
2. 要沿用旧数据，请将服务器上的 `anx`（或 `Anx`）目录改名为 **`modu`**。若已有 `modu`，先分别备份并确认保留哪份数据，**不要直接覆盖**。
3. 将参与同步的设备全部升级到 1.0.1，再恢复同步。旧版本仍使用旧目录，混用会造成两套互不同步的数据。
4. 服务器地址仍填写同步目录的上级地址，不要额外拼接 `/modu`。不迁移时，新版使用新的 `modu` 同步空间。

API Key 同步仍默认关闭，独立于同步总开关；开启时以 AES-256-GCM 加密写入数据库，各设备需同一独立密码。**这不是对整本书或整个数据库文件的加密。** 配置代码和二维码不是加密数据，请勿公开。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | 沿用项目专用签名的 APK，可覆盖升级；请勿先卸载旧版 |
| Windows | x64 / ARM64 | EXE 安装器，附带 VC++ CRT，需要 WebView2 Runtime；无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，使用 APT 安装；不保证其他发行版兼容 |
| macOS | Intel x64 / Apple Silicon ARM64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| iOS | ARM64 真机 | iOS 16+ 未签名 IPA，需自行合法签署主程序和 Share Extension，不能直接安装 |

共 **9 个程序包**，均附 SHA-256。Android `-notices.zip` 是许可附件，不是安装包。iPhone/iPad 没有 x64 真机包；此发布不包括 App Store、TestFlight 或 Play Store 上架。

## 验证范围与已知限制

- 发布前本地 Flutter 回归 **339 项通过、2 项跳过**；阅读器 JavaScript 回归 **51 项通过**。涵盖推理请求适配、高亮合并及事务回滚、图片/注释尺寸、跨章朗读、WebDAV 路径与密钥同步。
- 系统与在线朗读跨章测试使用模拟语音后端；未使用个人 API Key 或私人书籍在线实测，不代表每个服务和设备均完成实际音频播放验收。
- 图片及注释布局使用合成内容进行了浏览器检查；Android/iOS 真机图片、连续高亮手感和跨章朗读仍需复测。扫描 PDF 无 OCR。
- 各平台构建、架构/签名/安装器检查，以及 Android 36 x86_64 模拟器对四个内嵌模型的 Release 推理检查以本次 GitHub Actions 为准。构建通过不等于所有平台业务均完成真机验收。
- 此版不宣称解决所有向量化闪退。**iQOO Neo8 / Android 16 与用户原 EPUB 的长书索引仍需复测**。可在「设置 → 提交 Bug」勾选环境和脱敏崩溃诊断，预览后提交。
- Linux 无系统 TTS 后端，需选择在线语音。未选系统声音的新安装可先获取并选择声音。Apple 系统诊断可能延迟，部分退出原因无法获取原生堆栈。
- 在线 AI、向量、翻译和朗读会向所选服务发送相关文本；本地嵌入不代表整个 AI 流程离线。免费接口可能限流或变化，第三方接口需有效配置。

## English release notes

**Modu 1.0.1 (build 10001)** is a stable release derived from Anx Reader and ReadAny, retaining upstream attribution and licenses under GPL-3.0-or-later.

### Changes

- Per-model **Off** reasoning, also used by the model selected for full-text translation. Provider-specific request fields are adapted; actual support and speed depend on the model/service.
- Mobile quick marks merge adjacent same-color highlights across pages **within one chapter document**, preserving comments and non-contiguous marks. No automatic page-turn selection or cross-chapter/PDF merge.
- Mobile inline images fit the available reading area proportionally, including after rotation. Desktop image layout is unchanged.
- Footnote popups resize to content, limited to **25% of the visible reader viewport area**, with internal scrolling for long notes.
- Continuous TTS waits for temporarily locked chapter navigation, handles empty chapters and starts the next chapter with its heading. Missing WebView replies are errors, not a false end-of-book. Manual stops, timers and error pauses remain effective.
- All WebDAV sync paths use **`modu`**, separate from the read-only remote library connection.

### WebDAV migration

Pause sync on all devices and back up local and remote data. Rename the server folder `anx` (or `Anx`) to `modu` **before resuming sync**, and upgrade every syncing device. Do not overwrite an existing `modu` folder. Keep the endpoint at the parent directory; do not append `/modu` again. The app does not automatically rename, merge, delete or read the old folder. Without migration, it uses a separate sync space.

### Packages and verification

Nine application packages: Android ARM64/x86_64 APK, Windows x64/ARM64 EXE, Debian 13 x64/ARM64 DEB, Intel/Apple Silicon macOS DMG, and iOS ARM64 unsigned IPA. Android retains its signing identity; macOS is unnotarized, Windows lacks commercial signing, and iOS requires your own valid signing. Back up before upgrading. License ZIPs are attachments, not installers. SHA-256 files accompany the packages.

Local regressions: **339 Flutter tests passed, 2 skipped; 51 reader JavaScript tests passed**. TTS tests use mock backends; browser checks use synthetic content. Real-device acceptance of the new mobile behavior, long-book indexing on the reported iQOO device and user-server WebDAV migration remain unverified. CI provides platform build, package and targeted native-test results, not a guarantee that every feature works on every device.

API-key sync remains separately enabled and encrypted; configuration codes/QRs are not encrypted. Never submit keys, private books or unreviewed diagnostics to public issues.
