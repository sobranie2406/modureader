# 默读 / Modu Beta 4 · Android build 6332 / other platforms 6331

## Android 热修复 · 6332

- 替换本页 ARM64 和 x86_64 两个安卓 APK，版本仍为 Beta4，构建号由 6331 升到 6332。沿用原签名，可直接覆盖安装；无需卸载或删除书籍。其他平台附件保持 6331，不变更原 Beta4 标签。
- 修复发布混淆破坏 ONNX Java/JNI 接口：保留 `ai.onnxruntime.**` 的类及成员，防止原生代码找不到 `TensorInfo` 及输出张量构造函数而终止进程。这是四个模型共用的风险，不是 iQOO 专属问题。
- 用户提供的 6331 堆栈与发布 APK 原生库 Build ID 一致，`0x97e4` 对应 `convertToTensorInfo` 的 JNI 方法查找；公开 APK 缺少原名 `TensorInfo`。新打包检查会拒绝该旧 APK，且同时检查类定义和原生构造函数签名，不以字符串存在代替验证。
- 增加 Android 16 x86_64 模拟器上的 Release 混淆包推理测试，覆盖四个内嵌模型及 16/512/64 token 输入；以热修复流水线结果为准。模拟器测试不能替代 iQOO Neo8 / Android 16 与原 EPUB 的长书验收。
- 下载后请在关于页面确认 **0.1.0-beta.4+6332**；若仍退出，请预览并提交新的崩溃诊断。此前内存优化继续保留，但不是这次已定位 JNI 崩溃的修复替代品。

### Android hotfix (English)

The ARM64 and x86_64 APKs on this release are replaced with build **6332**, retaining the original signing identity for in-place upgrades. Other platform packages remain build 6331 and the original Beta4 tag is unchanged. The hotfix preserves ONNX Runtime's JNI-accessed Java classes and constructors through R8. The original APK was missing the unrenamed `TensorInfo` class at the native method lookup identified in the submitted crash stack. Packaging now checks actual DEX definitions and constructor signatures. An Android 16 x86_64 emulator test exercises all four models against the minified release; see its CI result. This does not replace long-book verification on the reported iQOO device. Corresponding hotfix source is identified in the updated Android notices attachments.

## 原 Beta4 更新说明 / Original Beta4 notes (6331)

本项目来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，是独立修改版，不是上游官方发行版。按 GPL-3.0-or-later 发布，保留上游许可及版权。

## 本次修正

- 修正四个本地向量模型共用的内存叠加风险：EPUB 提取完成即释放专用后台 WebView；本地模型在索引落盘前等待释放；向量使用紧凑 Float64 存储，不再保留大量逐元素对象。
- 索引逐条写入并等待磁盘写入完成，不再一次生成整本书的大 JSON 字符串。书籍内容哈希改为增量计算，保持旧哈希算法兼容。
- “已索引”标签改读小型完成记录，不再为刷新标签完整解析向量文件。索引缺片段、向量数量/维度不一致或出现无效数值时不能提交；中途取消保留旧的完整索引。
- 任务开始持久保存构建中标记，进程意外退出后不会把旧索引当作本次任务完成。**Beta3 已发生的崩溃不能靠新标记追溯判断。**
- 提交 Bug 新增默认关闭的“附带崩溃日志”可选框、日志预览及独立设备环境开关。保留少量脱敏操作记录；Android 读取系统退出原因及可用原生堆栈，macOS/iOS 接入 MetricKit，Windows 接入原生异常堆栈，Linux 读取系统保留的本应用 coredump 摘要。
- 日志不自动上传、不进入 WebDAV、不放入 URL，不包含原始内存转储、书籍正文、API Key、账号、用户路径、设备标识或任意异常文本。先预览，确认后复制，再由用户粘贴并提交公开 GitHub Issue。
- 四个模型和分词器继续内嵌；默认本地中文 BGE，自动向量化默认关闭。保留原有阅读、朗读、翻译、AI 阅读技能及加密密钥同步设置。

## 已验证与仍待确认

- 本地完整 Flutter 回归 276 项通过、2 项跳过；18 项打包工具测试通过。新增保存/释放顺序、索引完整性、取消、标签小记录和脱敏测试。各平台构建与原生测试结果见 CI 和验证文档。
- 主机合成对照：5,000 个片段、512 维向量，索引约 41 MiB。旧式保存并刷新标签后的 RSS 约 593 MiB，改后约 248 MiB。**这是 macOS Dart 进程测试，没有加载 ONNX，也不是 Android 真机或原 EPUB 的复现，不能视为原闪退唯一根因的证明。**
- 仍需在 **iQOO Neo8 / Android 16** 和原 EPUB 上复测。若仍退出，请重新打开 App，在“设置 → 提交 Bug”中勾选设备环境和崩溃日志，预览后提交。可用记录取决于系统保留情况，不能承诺捕获系统强杀或全部原生崩溃。
- Apple 诊断可能延迟送达，报告区间不是精确崩溃时间；Windows fail-fast、损坏堆栈和强杀可能绕过处理器；Linux 需要 systemd-coredump 与读取权限。不会开启系统转储或申请管理员权限。
- **升级兼容**：旧版不超过 4 MiB 的索引可自动生成完成记录；更大的旧索引不会为了显示标签自动整本读取，可能暂不显示“已索引”，请手动重新向量化一次。旧索引文件和原书保留，显式搜索仍可尝试读取旧索引。索引文件大小不是 EPUB 文件大小。
- 本机 iOS 整包构建缺少 Xcode iOS 平台组件；原生 iOS 插件 ARM64 类型检查已通过，发行 IPA 由 GitHub Actions 构建。构建和自动化测试不等于所有平台业务功能都已真机验收。

详见 [崩溃诊断与隐私验证](https://github.com/sobranie2406/modureader/blob/v0.1.0-beta.4/docs/crash-feedback-verification.md) 和 [Beta4 索引内存验证](https://github.com/sobranie2406/modureader/blob/v0.1.0-beta.4/docs/beta4-index-memory-verification.md)。

## 升级与安装

新标签 `v0.1.0-beta.4`，构建号 `6331`；Beta1/2/3 保留，不覆盖旧版。Android 沿用默读专用签名，可覆盖升级；请先备份重要数据，不要为更新直接卸载旧版。

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | 专用签名 APK，非 Play Store 版 |
| Windows | x64 / ARM64 | EXE 安装器，附带 VC++ CRT，仍需 WebView2；无商业代码签名 |
| Linux | x64 / ARM64 | Debian 13 (trixie) DEB，使用 APT 安装，不保证其他发行版兼容 |
| macOS | Intel x64 / Apple Silicon ARM64 | DMG，ad-hoc 签名，未经 Apple Developer ID 公证 |
| iOS | ARM64 真机 | iOS 16+ 未签名 IPA，主程序及 Share Extension 需自行合法签名，不能直接安装 |

目标为 9 个应用包，以本页实际附件为准；各包附 SHA-256。许可说明 ZIP 是附件，不是统一格式的安装包。

## 功能边界

- Linux 没有系统 TTS 后端；用户需主动选择在线语音，不会自动上传正文。在线语音播放仍需目标设备验证。
- 密码 PDF 暂不支持，扫描 PDF 没有 OCR；不保证 DRM 书籍支持。文字层、目录及文件排版影响提取和索引。
- 免费翻译与 Edge TTS 依赖网络，可能限流或改变；付费 AI/翻译/语音需有效配置。API 预设不保证长期可用。
- 远程 AI、翻译和语音会向所选服务发送相应文本。不要公开 API Key、同步密码、配置代码或私人书籍。
- 不提供签名服务、上游商店版本、Notion/Obsidian 专用导出或全部上游格式支持承诺。
- README 的早期 macOS 截图只展示界面入口，不是接口可用性证明；以实际安装版本为准。

## English summary

Beta 4 (build 6331) addresses shared indexing memory risks across all four bundled local embedding models: extraction WebViews are disposed immediately, model teardown is awaited before persistence, vectors use compact storage, content hashing is incremental, and JSON is written with bounded per-row backpressure. Bookshelf badges read a small commit summary instead of deserializing the full vector index.

Incomplete/invalid vectors cannot replace a completed index. Cancellation preserves the previous index, and a persistent in-progress marker prevents interrupted builds from being presented as completed.

Bug reporting now offers an **off-by-default, previewable crash-diagnostics checkbox**, with separately controlled device/environment information. Android system exit traces, Apple MetricKit, Windows native exceptions and Linux systemd summaries are integrated on a best-effort basis. Reports exclude raw memory dumps, book text, credentials, personal paths and device identifiers. No automatic upload, WebDAV inclusion or diagnostic URL payload; the user previews, copies and submits the public issue.

Host-only synthetic comparison: 5,000 chunks × 512 dimensions, approximately 41 MiB index. RSS after saving and refreshing a badge was about 593 MiB with the previous path versus 248 MiB with the bounded path. This used macOS Dart without ONNX, **not the reported EPUB on iQOO Neo8 / Android 16**. Device verification remains necessary; these changes do not establish a sole crash cause or guarantee that every crash is fixed.

Legacy indexes above 4 MiB require one manual rebuild to regain the verified bookshelf badge. Existing books/index files are preserved. Smaller legacy indexes migrate their summary lazily. Apple delivery may be delayed; Windows fail-fast/force-kill and Linux systems without accessible systemd records may have no stack.

Android retains the original signing identity for in-place upgrades. All four models remain bundled; local Chinese BGE is the default and automatic indexing stays off. Beta1/2/3 remain available. Back up important data before upgrading.

Distribution targets: Android ARM64/x86_64 APK, Windows x64/ARM64 EXE, Debian 13 x64/ARM64 DEB, macOS Intel/Apple Silicon DMG, and **unsigned iOS ARM64 IPA**. macOS is unnotarized. iOS requires your own valid signing and cannot be installed directly. Checksums accompany the actual assets.

Derived from Anx Reader and ReadAny, with upstream attribution and licenses retained. CI compilation, installer checks and unit tests do not constitute complete device acceptance.
