# 默读 / Modu 1.0.6 正式版

版本：**1.0.6+10018**。来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留原作者版权与许可，是 GPL-3.0-or-later 独立修改版本。

## 本次更新

- **EPUB 脚本权限加固**：Android、Windows 关闭 EPUB JavaScript 时，不再为书籍 iframe 开放脚本权限。macOS、iOS 和采用 WebKit 的 Linux 保留父页面事件兼容权限，但关闭时仍清理书籍活动内容并应用脚本禁用策略。分页和固定布局共用规则，缺失或非法配置默认不开放权限。不再屏蔽相关浏览器警告。设置变化后请重新打开书籍，仅为可信书籍开启脚本。
- **AI 渲染与字号**：高频累计输出按约 80 毫秒合并更新，完成时补齐最后文本；复用未变化的 Markdown，减少整个界面的重复刷新。上翻历史时不再强制回到底部。正文、列表和标题使用一致的字号比例；异常配置回退到 14，修复最小字号 10 时思考区计算越界，保留系统无障碍缩放。
- **技能提示词默认收起**：首页和书内 AI 可从输入区星光按钮展开，新建对话恢复收起。不删除技能，不改变提示词配置或请求策略。
- **未下载书籍向量化提示**：缺少本地文件时提示先下载，不加入失败任务。批量操作跳过缺失书籍并显示数量，其他书继续排队；执行前再次检查文件。
- **阅读时定时同步**：默认关闭，支持 1、2、3、5、10、15、30 分钟和 1 小时。仅在前台阅读页面生效，遵循 WebDAV、自动同步和仅 Wi-Fi 设置；同步已保存笔记、阅读位置及原同步内容，不提交草稿，不额外启用密钥同步。
- **简化同步提示**：过程不弹提示，成功遵循提示开关，失败显示脱敏后的原因。自动预检重试期间不提示，最终失败才提示，主动取消不报失败。
- **动画与导出**：关闭打开书籍动画后，同时禁用路由、封面过渡和淡出，不改变正文翻页方式。思维导图支持完整 PNG、SVG、Markdown、FreeMind（.mm）和 JSON 导出，取消保存不提示成功。
- 四个离线 ONNX 模型及分词器继续内嵌，自动向量化默认关闭。

## 升级与同步注意事项

先备份，使用覆盖安装升级；Android 沿用原项目专用签名。所有同步设备建议保持同一新版。继续兼容 1.0.5 的可靠 ETag 条件写入和无可靠 ETag 独立记录通道，不回退到无条件覆盖整库。

各端使用相同的 `modu` 上级目录，不重复拼接 `/modu`。**不要删除 `modu/record-log-v1/` 或旧数据库**。旧于 1.0.5 的客户端不能识别兼容记录通道，升级期间请暂停旧版自动同步。[记录同步说明](https://github.com/sobranie2406/modureader/blob/v1.0.6/docs/WEBDAV_RECORD_SYNC.md)。

API Key 和远程书库凭据仍按默认关闭的独立加密开关同步，这不代表整个书库已加密。字体和本地向量索引不参与同步。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，Android 8+ |
| macOS | ARM64 / Intel x64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| Windows | x64 / ARM64 | EXE，附带 VC++ CRT，需要 WebView2 Runtime，无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，不保证其他发行版兼容 |
| iOS | ARM64 真机 | iOS 16+ IPA，须自行合法签署主应用及 Share Extension |

共 **9 个程序包及各自 SHA-256**。许可保留在包内和源码中，不另附 notices ZIP。不包含应用商店或 TestFlight 发布。

## 验证范围与限制

- 本地 Flutter **667 项通过、5 项跳过**；阅读器 JavaScript **112 项通过**。包含输出合并、最终文本、历史滚动、字号、技能调用、缺失书籍、同步与脚本权限策略。
- 全平台构建、安装包检查和 CI 回归通过后才发布附件。执行记录见 [Actions](https://github.com/sobranie2406/modureader/actions)。
- 浏览器合成页面验证不等于全部 Android WebView、WKWebView、WPE 的实机验收；本次未在报告中的小米手机测量 AI 帧率。WebKit 兼容分支仍可能产生沙箱组合警告，不代表检测到攻击，也不构成绝对安全保证。
- 未进行真实坚果云数据破坏性测试、长期多端并发或墨水屏设备验收。在线 AI、翻译和 TTS 取决于服务商；Linux 无系统 TTS 后端，需选择在线语音。设备如提示 `No voice selected`，请先获取列表并选择音色。

来源与许可：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.6/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.6/NOTICE)、[UPSTREAM](https://github.com/sobranie2406/modureader/blob/v1.0.6/UPSTREAM.md)、[对应源码](https://github.com/sobranie2406/modureader/tree/v1.0.6)。

## English release notes

**Modu 1.0.6 (build 10018)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.

- Remove iframe script permission on Android and Windows when EPUB scripts are disabled. WKWebView/WPE retain the event-listener workaround, while book sanitization and script restrictions remain active. Malformed policy fails closed; sandbox warnings are no longer suppressed. Reopen books after changing this setting and enable scripts only for trusted EPUBs.
- Coalesce AI updates, flush final text, reuse unchanged Markdown and stop forcing readers away from history. Normalize typography while retaining accessibility scaling. Hide skill prompts by default with a manual toggle.
- Require local files before indexing; skip unavailable books in batch requests. Add opt-in foreground reading sync at one minute through one hour and show only final sync feedback.
- Disable all book-opening transitions using the existing setting. Export complete mind maps as PNG, SVG, Markdown, FreeMind or JSON. Keep all four offline models bundled.

Nine native packages with SHA-256: Android ARM64/x86_64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB and iOS ARM64 IPA. Android retains its signing identity. macOS is unnotarized, Windows has no commercial signature, and iOS requires your own valid signing. Licenses remain inside packages.

Back up before upgrading. Keep syncing devices updated; clients older than 1.0.5 cannot read the compatible record log. Do not delete remote history or legacy databases. Optional encrypted credential sync does not encrypt the whole library.

Local checks: 667 Flutter tests passed, 5 skipped; 112 reader JavaScript tests passed. CI gates publication on build/package checks. Synthetic browser tests do not replace native-WebView acceptance; no frame-rate measurements on the reported Xiaomi device or prolonged real-cloud concurrency tests were performed. WebKit may still emit its sandbox warning. Linux system TTS is unavailable; online services depend on their providers.
