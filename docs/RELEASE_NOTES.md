# 默读 / Modu 1.0.7 正式版

版本：**1.0.7+10025**。来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留原作者版权与许可，是 GPL-3.0-or-later 独立修改版本。

## 本次更新

- **连续滚动**：关闭书籍脚本时，横排流式书籍使用有界预加载窗口跨章滚动，提前准备相邻章节，修正章末点击重复翻页。普通翻页不再不断生成返回记录，明确跳转仍支持返回。TTS 保留正在朗读章节的文档与游标，完成后继续下一章。
- **书内搜索**：入口放在翻译与书签之间，使用浮动搜索框。正文对真实文字范围显示浅蓝色选中式高亮，不再绘制外围框；修正跨标签、重复匹配、章末命中和文字偏移。底部支持上一处、下一处、当前/总数、返回搜索前位置及关闭；取消搜索会清除缓存章节的标记。
- **批注定位**：补齐预加载章节批注图层的留白和尺寸初始化，统一正文与图层坐标转换。返回缓存章节或发生内部滚动时更新标记和点击范围，不修改已有批注数据。
- **注释排版**：弹出注释字号为正文设置的 70%；保留不超过屏幕 25% 面积的自适应尺寸和底部留白，过长注释仍可滚动。
- **AI 阅读技能**：对话恢复默认显示技能标签；技能消息显示名称，隐藏长提示词正文。完整提示词仍用于模型请求，并可在技能设置中查看和编辑。
- **Windows 操作与向量化**：修复方向键与 Ctrl+[ / Ctrl+] 翻页；原生模型推理使用后台串行工作线程，分词与索引准备移出界面线程；修复插件销毁时访问已停止的 Flutter 通道导致正常关闭崩溃，保留退出和取消检查。
- **Android 链接关联**：不再把默读注册为普通网页链接的打开程序；保留本地电子书打开及主动分享导入。
- 继续内嵌四个离线 ONNX 模型及分词器，自动向量化默认关闭。

## 升级与同步注意事项

建议先备份并覆盖安装。Android 沿用原项目专用签名；各同步设备建议保持同一新版。本次不更改已有书籍、笔记和阅读位置的同步格式。

各端使用相同的 modu 上级目录，不重复拼接 /modu。**不要删除 modu/record-log-v1/ 或旧数据库**。旧于 1.0.5 的客户端不能识别无可靠 ETag 的兼容记录通道，升级期间请暂停旧版自动同步。[记录同步说明](https://github.com/sobranie2406/modureader/blob/v1.0.7/docs/WEBDAV_RECORD_SYNC.md)。

API Key 和远程书库凭据仍按默认关闭的独立加密开关同步，不代表整个书库已加密。字体和本地向量索引不参与同步。

## 安装包

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，Android 8+ |
| macOS | ARM64 / Intel x64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| Windows | x64 / ARM64 | EXE，附带 VC++ CRT，需要 WebView2 Runtime，无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，不保证其他发行版兼容 |
| iOS | ARM64 真机 | iOS 16+ IPA，须自行合法签署主应用及 Share Extension，不能直接安装 |

共 **9 个程序包及各自 SHA-256**。许可保留在包内和源码中，不另附 notices ZIP。不包含应用商店或 TestFlight 发布。

## 验证范围与限制

- 本地 Flutter **686 项通过、5 项跳过**，Python **47 项通过**，阅读器 JavaScript **156 项通过**。
- 发布由全平台构建、安装包架构/校验和检查和 CI 回归共同把关，全部通过后才创建正式发布。执行记录见 [Actions](https://github.com/sobranie2406/modureader/actions)。
- 浏览器合成书验证了 18 个精确搜索命中、跨章往返、新增批注、字号变化和重开章节；批注检查覆盖 33 个状态，坐标误差小于 1 CSS 像素。
- 浏览器检查不是所有 Android WebView、WKWebView、WPE 的实机验收。逐渐累积式批注漂移未在 Chrome 中完整复现；已修正的坐标转换、内部滚动和缓存恢复路径另有回归覆盖。
- Windows 后台推理有工作线程生命周期测试，仍需在报告设备上评估界面延迟与长书连续向量化。不以编译或 CI 推理成功代替真实设备性能验收。
- 连续滚动限横排流式书籍；固定版式、竖排及开启书籍脚本的内容沿用对应阅读路径。WebKit 兼容分支仍可能产生沙箱组合警告，请仅为可信书籍开启脚本。
- 未进行真实坚果云数据破坏性测试、长期多端并发或墨水屏设备全面验收。在线 AI、翻译和 TTS 取决于服务商；Linux 无系统 TTS 后端，需选择在线语音。

来源与许可：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.7/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.7/NOTICE)、[UPSTREAM](https://github.com/sobranie2406/modureader/blob/v1.0.7/UPSTREAM.md)、[对应源码](https://github.com/sobranie2406/modureader/tree/v1.0.7)。

## English release notes

**Modu 1.0.7 (build 10025)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.

- Add bounded continuous chapter scrolling for horizontal reflowable books with scripts disabled, prepare adjacent chapters earlier, and fix repeated page turns at chapter boundaries. Preserve the active speech document and cursor through chapter transitions.
- Add a floating in-book search dialog and previous/next match, current/total count, return-to-origin and close controls. Highlight exact text ranges like a selection, without outer boxes. Correct inline-tag, repeated-match, Unicode-offset and end-of-chapter cases.
- Initialize annotation overlays when preloaded chapters become active; map chapter and overlay coordinates consistently, and refresh marks after internal scrolling or cached-chapter activation. Existing annotation data is unchanged.
- Display footnotes at 70% of the reader font size, with the existing 25%-of-screen area limit, end padding and scrolling for longer notes.
- Keep AI skill shortcuts visible. Skill messages show names instead of long prompt text; full prompts remain in model requests and skill settings.
- Restore Windows arrow-key and Ctrl+[ / Ctrl+] paging. Move Windows native inference to a serial background worker and move tokenization/index preparation off the UI isolate. Fix normal-close crashes caused by accessing the stopped Flutter messenger during plugin destruction; retain lifecycle and cancellation checks.
- Stop claiming ordinary web links on Android. Retain local ebook opening and explicit share/import flows. Keep all four offline embedding models bundled.

Nine native packages with SHA-256: Android ARM64/x86_64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB and iOS ARM64 IPA. Android retains its signing identity. macOS is unnotarized, Windows has no commercial signature, and iOS requires your own valid signing. Licenses remain inside packages.

Back up before upgrading. Keep syncing devices updated; clients older than 1.0.5 cannot read the compatible record log. Do not delete remote history or legacy databases. Optional encrypted credential sync does not encrypt the whole library.

Local checks: 686 Flutter tests passed, 5 skipped; 47 Python tests and 156 reader JavaScript tests passed. Browser checks covered 18 exact search matches and 33 annotation/navigation states. CI gates publication on builds, regression tests and package verification. Browser tests do not replace native-WebView acceptance or Windows performance measurements. Progressive backward drift was not fully reproduced in Chrome; coordinate, scroll and cache paths have dedicated regression coverage. No destructive real-cloud or prolonged concurrency testing was performed.
