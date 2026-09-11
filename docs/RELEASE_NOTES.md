# 默读 / Modu 1.0.3 正式版

版本：**1.0.3+10010**。本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留上游版权与许可，是按 GPL-3.0-or-later 发布的独立修改版。

## 本次更新

- **本地向量模型按需下载**：四个 ONNX 模型不再内嵌安装包。在「设置 → 向量模型」下载模型和分词器，校验文件大小与 SHA-256 后使用；完整缓存可复用。默认中文 BGE，自动向量化默认关闭；缺少模型时先提示下载，不在索引时自动下载。下载来自 Hugging Face，需联网并保持下载页面打开，中断可重试。
- **远程书库配置保存与同步**：书库登录密码在本机持久保存；配置进入加密设置备份，并跟随现有、默认关闭的「同步 API Key」开关参与加密同步，独立处理修改与删除。不进入明文设置备份。显式代码/二维码导出仍默认包含密码，可取消勾选；**代码和二维码未加密，不要公开**。
- **AI 官方图标**：服务商列表、配置详情、模型选择和对话使用本地打包的官方图标；自定义接口根据服务地址、名称与模型识别品牌，无法识别时用通用图标。不携带 API Key 向网站请求图标。
- **桌面阅读输入**：修复 AI 面板打开后点击正文未恢复键盘焦点的问题。正文方向右/下为下一页，左/上为上一页；AI 输入框中仍用于移动光标。分页模式抑制原生自由横移，未选中文字的有效拖动按翻页处理。
- **安卓首次选字**：长按单字或单词即可触发工具栏，不再要求先拖动选择范围；保留快速标记与选择去重保护。
- **字体与滚动阅读**：章节先等待字体就绪再显示正文，减少默认字体闪现；8 秒超时后可回退，避免字体故障永久空白。滚动模式的点击/快捷键翻页改为阅读区域的 **80%**，保留 **20% 重叠**；自由滚动不变。
- **同步设置修复**：两项同步时间统一显示本地时区；WebDAV 保存后立即刷新地址；数据库备份管理的「取消」正常关闭弹窗，不退出底层设置页。
- **发布附件简化**：只提供各平台原生安装包与 SHA-256，不再提供独立 notices ZIP；许可证仍保留在程序包与源码中。

## 升级与数据安全

构建号 10010 高于 1.0.2 的正式版和 10005—10009 测试版。Android 沿用原专用签名，请覆盖安装，不要先卸载。升级前仍建议备份书籍和设置。

从 1.0.2 升级继续使用数据库 8 的逐条同步，不新增同步库格式迁移。更旧客户端升级时，请暂停旧端同步、备份各设备和服务器，再升级全部同步客户端；各端指向同一 modu 上级目录，不重复拼接 /modu。服务器须支持强 ETag 与条件写入。详见[记录合并与迁移](https://github.com/sobranie2406/modureader/blob/v1.0.3/docs/WEBDAV_RECORD_SYNC.md)。

API Key 与远程书库配置的可选同步使用独立密码和 AES-256-GCM 加密，各端须输入同一密码。**书籍、笔记和整个数据库并不因此全部加密**。字体、主题图片与向量索引仍留在各设备本地；聊天和在线翻译/TTS 仍可能把相关文本发送给所选服务。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，可覆盖升级 |
| macOS | Apple Silicon ARM64 / Intel x64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| Windows | x64 / ARM64 | EXE，附带 VC++ CRT，需要 WebView2 Runtime，无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，使用 APT 安装，不保证其他发行版兼容 |
| iOS | ARM64 真机 | iOS 16+ IPA，无分发签名；须自行合法签署主应用和 Share Extension，不能直接安装 |

共 **9 个程序包及各自 SHA-256**。文件名不含未签名后缀，不改变上述签名状态。没有 x64 iPhone 包，不含应用商店或 TestFlight 发布。

许可与对应源码：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.3/LICENSE)、[第三方许可证](https://github.com/sobranie2406/modureader/tree/v1.0.3/LICENSES)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.3/NOTICE)、[来源](https://github.com/sobranie2406/modureader/blob/v1.0.3/UPSTREAM.md)、[v1.0.3 源码](https://github.com/sobranie2406/modureader/tree/v1.0.3)。

## 验证范围与已知限制

- 发布前本地回归：**460 项 Flutter 测试通过、4 项跳过；71 项阅读器 JS 测试通过；30 项打包测试通过**。跳过项依赖私人字体样例或显式开启的在线测试。标签 CI 重新检查源码、构建与安装器，结果见 [GitHub Actions](https://github.com/sobranie2406/modureader/actions)。
- 先行 **1.0.2+10009** 在 macOS ARM64、荣耀 LGE-AN10 / Android 15 上保留数据覆盖安装并冷启动；两端验证备份弹窗取消。安卓验证单字原地长按即可弹出工具栏，不拖动选区。Mac 验证书籍渲染、同步时间显示与 AI 输入框光标行为；10008 曾验证 AI 面板打开时正文方向键来回翻页。
- 80% 翻页与字体等待通过实际阅读器代码的浏览器测试及自动回归；**10009 安卓滚动模式真机复测未完成**。先行测试包的结果不冒充最终 1.0.3 全平台真机验收，字体、图片与翻译引起的重新排版仍需更多书籍验证。
- CI 对四个按需模型执行有针对性的原生推理检查，测试资源不进入正式包。**iQOO Neo8 / Android 16 与用户原 EPUB 的长书向量化仍需复测**，不宣称排除全部闪退。
- Mac 先行测试中，已开启的 Google 全文翻译出现握手失败/限流；在线 AI、翻译、TTS 依赖网络与服务商，并未全面验收。Linux 没有系统 TTS 后端，应选择在线语音。
- 大书库、长时间并发同步、各厂商 Android WebView、全部字体和二维码跨设备组合未完成全面端到端验证。问题可在「设置 → 提交 Bug」附可预览的环境与脱敏崩溃诊断；不要上传个人书籍、密钥或完整配置代码。

## English release notes

**Modu 1.0.3 (build 10010)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny. Upstream attribution and licenses are retained.

### Changes

- Download the four local ONNX embedding models on demand instead of bundling weights. Model/tokenizer files are checked against pinned sizes and SHA-256 hashes; valid existing caches are reused. Chinese BGE remains the default, and automatic indexing remains off. Downloads use Hugging Face and require connectivity; keep the settings page open and retry interrupted transfers.
- Persist library WebDAV passwords locally. Include library configuration in encrypted backups and optional encrypted API-key sync, with separate updates/deletions, never in plain settings backups. Explicit code/QR export still includes passwords by default and is **not encrypted**.
- Bundle official provider artwork for lists, settings, model pickers and chats. Recognized custom endpoints receive matching icons; unknown providers use a generic icon. No authenticated icon requests are made.
- Restore desktop reader keyboard focus after clicking text with AI chat open. Arrow keys turn pages in the reader but move the cursor in input fields; paginated content no longer freely shifts sideways.
- Show Android selection tools on the initial long press. Wait for chapter fonts before revealing content, with an eight-second fallback. Scroll-mode page turns move 80% of the viewport, leaving 20% overlap; free scrolling is unchanged.
- Display both sync timestamps in local time, immediately refresh saved WebDAV addresses, and fix Cancel in database-backup management.

### Packages, upgrades and security

Nine native packages with SHA-256: Android ARM64/x86_64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB, and iOS ARM64 IPA. Android retains its signing key. macOS is unnotarized, Windows has no commercial signature, and iOS requires your own valid signing. Filename simplification does not remove these restrictions. No standalone notices ZIP; licenses remain bundled and in the tagged source linked above.

Build 10010 upgrades earlier 1.0.2 builds without uninstalling Android. Back up first. Version 1.0.2 users keep the same record-sync format; older clients must follow the database 8 migration guide and use servers with strong ETags and conditional writes. API keys and library credentials are optionally encrypted with a separate shared password; books, notes and the whole database are not thereby encrypted. Fonts and indexes remain local.

### Verification limits

Local checks passed 460 Flutter tests (4 skipped), 71 reader JavaScript tests and 30 packaging tests. Tag CI reruns checks and native package/inference tests. Earlier builds 10008/10009 exercised selected macOS ARM64 and HONOR Android 15 interactions, including first-long-press selection tools and backup Cancel. They are not final 1.0.3 all-platform acceptance tests. Native Android 80% scroll verification was not completed; browser regression checks passed.

Long-book indexing on the reported iQOO/Android 16 device, large concurrent libraries, all fonts and all online providers remain unverified. Google translation showed handshake/rate-limit errors in local testing. Review diagnostics before sharing; never publish private books, credentials or configuration codes.
