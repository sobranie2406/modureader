# 默读 / Modu 1.1.2 正式版

版本：**1.1.2+10034**。基于 Anx Reader 和 ReadAny（Reader Any）的 GPL-3.0-or-later 独立修改版本，保留原作者版权与许可。

## 本次更新

- **字体导入自动应用**：成功导入 TTF/OTF 后自动设为正文字体，正在阅读时立即切换，重新打开书籍仍生效。多选时应用最后一个成功导入的字体；取消或全部失败不改变当前选择。同名字体替换使用内容标识避免旧字体缓存。
- **阅读亮度**：阅读工具栏新增亮度入口，可跟随系统或手动调节。Android 使用应用窗口亮度，不修改系统全局设置；其他平台使用应用内遮罩调暗。亮度偏好仅保存在本机，不参加同步。
- **向量化前置校验**：未启用向量模型、模型未下载或文件损坏时，单本与批量向量化明确提示；执行前再次校验。不再把纯关键词索引误当作向量化结果，不删除已有本地索引。
- **GitHub 优先更新和下载**：仅连接失败、超时或服务不可用时回退 Gitee。继续核对同版本、同架构的大小与 SHA-256；校验失败不降级放行。

字体已在 HONOR LGE-AN10 / Android 15 实机验证：导入《京華老宋体 v3.0》即生效，重新开书仍加载该字体。字体不随安装包分发；该结果不代表所有字体和设备均已实测。

## 延续的阅读与数据功能

- **底部导航避让**：书架、远程书库、统计、AI、笔记和设置统一预留悬浮导航空间，适配系统安全区与大字体，避免列表末项、按钮和输入区被遮挡；键盘展开时隐藏底部导航。
- **竖排阅读**：可选红色双层边框和正文分栏线；标题置右、页码置左，中文环境使用中文数字。统一正文与页边背景，修复 macOS 竖排点击翻页和注释交互。
- **注释排版**：按实际段落正文而非上标序号计算 80% 字号；竖排弹窗交换宽高方向，长注释左右滚动。弹窗不超过屏幕面积 25%，尽量完整展示，末尾保留留白。
- **Android 存储迁移**：主要书库数据移至 `Android/data/com.modu.reader/files`。启动时先迁移和校验，再打开数据库与同步；支持中断恢复，冲突时停止而非覆盖，保留旧私有目录的数据副本。
- **向量模型与本地索引**：支持删除已下载模型；较大本地索引采用流式读取，文件上限提高至 1 GiB。移除向量索引 WebDAV 同步入口及运行流程，已有本地索引不删除；书籍、笔记、书签和阅读进度继续同步。
- **替换文件清理**：有可靠替换记录且已无引用的旧书文件，从云端活动书库移入 `modu/replaced-files-v1`，可恢复，避免重复留在 `data/file`；不删除仍被引用的文件。
- **按需下载与更新**：四个向量模型不内嵌，下载源可选 Hugging Face（默认）或 Gitee。应用检查更新和下载安装包优先 GitHub，连接失败时回退 Gitee，检查大小与 SHA-256 后由用户确认安装。

## 升级与数据提示

- 升级前建议导出备份。直接覆盖安装，**不要先卸载或清除数据**；首次迁移请等待完成。迁移按文件校验 SHA-256，数据库及 WAL/SHM 一并处理；遇到新旧文件冲突会提示处理，不会静默切到空书库。
- 密钥、偏好设置、缓存及崩溃诊断仍使用相应私有位置。没有新增用户文件目录，也不扫描内部存储根目录的 Fonts。Android/data 的访问仍受系统限制，卸载应用可能删除其中数据；它不能代替独立备份。
- 本地索引上限提高不意味着低内存设备可以无压力检索任意大书。索引只留本机，各设备按需建立；新版不会自动删除其他用户服务器已有的历史索引。仍运行旧版的设备请关闭索引同步开关。
- 云端旧书移入恢复目录后，活动书库不再重复列出，但恢复目录仍占服务器空间；本次不做不可恢复的批量删除，无需清空 WebDAV。

## 下载与对应源码

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.2) · [Gitee 安装包镜像](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.2)

Gitee 仅托管安装包、说明与更新清单，不上传应用源码。两站分发同一次构建的原始文件，不二次打包；每包附 SHA-256。镜像逐包匿名下载校验通过后才更新备用清单；镜像未就绪时请使用 GitHub。Gitee 只保留最新正式版，GitHub 保留 1.1.0 起的发行版；旧 Release 清理不删除源码标签。

**免费获取完整对应源码**：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.2)、[源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.2.zip)、[构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.2/docs/RELEASING.md)。包含依赖锁定和构建脚本，许可与归属见 [LICENSE](https://github.com/sobranie2406/modureader/blob/v1.1.2/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.1.2/NOTICE)、[UPSTREAM](https://github.com/sobranie2406/modureader/blob/v1.1.2/UPSTREAM.md)。

## 安装包与验证范围

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，沿用原签名，Android 8+；系统确认后安装 |
| macOS | ARM64 / Intel x64 | DMG，ad-hoc 签名，未公证；退出旧应用后拖入 Applications 替换 |
| Windows | x64 / ARM64 | EXE，附 VC++ CRT，需 WebView2 Runtime，无商业签名 |
| Linux | x64 / ARM64 | Debian 13 DEB，不保证其他发行版兼容 |
| iOS | ARM64 | iOS 16+ IPA，须自行合法签署主应用及 Share Extension；应用内只能下载/导出 |

全平台构建、回归测试和九包完整性检查通过后才创建正式发布，见[构建记录](https://github.com/sobranie2406/modureader/actions)。自动化覆盖导航避让、迁移完整性与中断恢复、注释字号、竖排布局、索引读取和文件清理；不等于所有设备实测。Android 真实旧书库迁移、各厂商后台省电限制仍需设备验证。

## English

Modu **1.1.2 (build 10034)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.

New in this release: imported fonts apply immediately and persist, with cancellation/failure preserving the current choice; app brightness controls use Android window brightness or an in-app dimming overlay on other platforms; vectorization checks model enablement and availability before queueing and execution. Update checks and downloads prefer GitHub, with Gitee fallback only for network failures, timeouts or service unavailability; size and SHA-256 verification remain mandatory. Font auto-apply was verified on a physical Android 15 HONOR phone.

Continuing features:

- All home tabs reserve floating-navigation clearance, including large text and safe areas; navigation hides while typing.
- Vertical reading adds optional red frames, column rules, side headers/footers and Chinese page numbers; macOS reader clicks and footnotes are fixed.
- Footnotes use 80% of actual paragraph text size, not the reference marker. Vertical notes scroll horizontally; popups retain the 25% screen-area cap and end padding.
- Android library data migrates to `Android/data/com.modu.reader/files` before database/sync startup, with SHA-256 verification, resumable copying, conflict detection and the original private copy retained. Credentials remain private. Back up first and upgrade in place without uninstalling or clearing data. OS access restrictions still apply; uninstalling can remove external app data.
- Downloaded models can be deleted. Local indexes use streaming reads with a 1 GiB file limit; available RAM still limits practical use. WebDAV vector-index sync is removed, preserving existing local indexes; books, notes and progress still sync. Historical cloud indexes are not automatically deleted; disable index sync on older clients.
- Unreferenced replaced cloud books with reliable replacement records move to a recovery directory rather than remaining in the active library. Recovery files still consume server space.

Models remain on demand from Hugging Face (default) or Gitee. Updates prefer GitHub with verified Gitee fallback and user-confirmed installation. Both sites distribute identical binaries; Gitee contains packages/docs/update metadata only and retains the latest release. GitHub retains releases from 1.1.0 onward; all source tags are preserved. [Free corresponding source](https://github.com/sobranie2406/modureader/tree/v1.1.2) and [source ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.2.zip) are available on GitHub.

Nine packages cover Android ARM64/x64, macOS ARM64/x64, Windows ARM64/x64, Debian 13 ARM64/x64 and iOS ARM64. macOS is unnotarized, Windows lacks commercial signing, and iOS requires your own valid signing. Automated checks do not replace physical-device migration and background-playback testing.
