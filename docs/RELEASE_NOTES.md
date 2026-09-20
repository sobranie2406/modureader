# 默读 / Modu 1.1.0 正式版

版本：**1.1.0+10029**。来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留原作者版权与许可，是 GPL-3.0-or-later 独立修改版本。

## 本次更新

- **后台朗读与恢复**：Android 媒体通知提供播放/暂停、上一段、下一段及停止；跨章文本加载不再等待前台页面布局。语速和音调在滑块松手时提交，丢弃旧参数请求；播放器停止、释放或恢复失败后允许重建重试，避免一次错误让后续朗读持续失效。
- **可选向量索引同步**：「设置 → 同步 → 同步向量化数据」，各设备默认关闭。电脑索引可经 WebDAV 复用到手机；以实际书籍文件 SHA-256 匹配，不以书名或设备数据库编号配对，完整校验后才写入。接收端需先下载同一份书籍；查询仍需匹配模型。
- **AI 复用书籍索引**：移除重复的“建立知识库”入口，统一从书籍菜单排队向量化；自由对话正文检索复用关键词/向量混合检索，向量不可用时回退关键词。阅读技能继续遵守当前章节、选文和阅读范围。
- **自定义本地字典**：设置中导入并命名 MDX 或 StarDict 字典，支持启用、停用、重命名和删除；选中文字可查询已启用字典。字典不内嵌，不自动下载，不参加同步。
- **统一书籍菜单**：长按与封面三点使用同一套操作；分享、替换文件和释放空间直接列出，修复同步刷新期间菜单回调丢失。
- **快速标记菜单开关**：移动端右上角增加“标记后弹出菜单”按钮，默认关闭；可选择松手仅保存高亮，或保存后立即显示选中菜单。
- **AI 供应商管理**：内置供应商可恢复初始接口、模型和参数，同时清空已存 API Key、重置密钥轮转并恢复默认启用状态；自定义供应商支持列表滑动删除和详情页删除，均需确认。
- **下载方式保持不变**：应用更新优先 Gitee、失败回退 GitHub，校验大小与 SHA-256，不静默安装。四个向量模型仍按需下载，来源可选 Hugging Face（默认）或 Gitee，安装包不内嵌模型。

## 使用与隐私提示

- 升级前建议备份书库。无需清空 WebDAV；需要索引同步的设备应一同升级并开启开关。
- 索引附件包含原文片段与向量，存于 `modu/knowledge-v1`，**不使用 API Key 同步密码加密**。请使用 HTTPS 和可信服务器。单本上限 128 MiB；不自动清理历史索引。关闭开关不删除既有索引，模型权重与密钥不随索引传输。
- 字典以纯文本显示释义；支持 MDX 1/2 的未压缩或 zlib 数据、StarDict 2.4.2/3.0.0 及配套压缩文件。加密、LZO、MDX 3、MDD 多媒体和 DSL 不在本次支持范围，详见[字典说明](https://github.com/sobranie2406/modureader/blob/v1.1.0/docs/LOCAL_DICTIONARIES.md)。请自行取得合法字典文件。
- 恢复供应商默认值会立即删除该配置的密钥，无法通过取消编辑找回；需要重新填写才可调用需密钥的服务。不会删除书籍和笔记。

## 下载与对应源码

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.1.0) · [Gitee 安装包镜像](https://gitee.com/sobranie2406/modureader/releases/tag/v1.1.0)

Gitee 仅托管安装包、说明与更新清单，不上传应用源码。两站分发同一次构建的原始文件，不二次打包；每包附 SHA-256。镜像逐包下载验证后才更新自动更新清单，尚未就绪时客户端可回退 GitHub。

**对应版本完整源码（免费获取）**：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.1.0)、[源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.0.zip)、[构建说明](https://github.com/sobranie2406/modureader/blob/v1.1.0/docs/RELEASING.md)。包含依赖锁定、构建脚本及版权声明：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.1.0/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.1.0/NOTICE)、[UPSTREAM](https://github.com/sobranie2406/modureader/blob/v1.1.0/UPSTREAM.md)。

## 安装包与验证范围

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，Android 8+；系统确认后安装 |
| macOS | ARM64 / Intel x64 | DMG，ad-hoc 签名，未公证；退出旧应用后拖入 Applications 替换 |
| Windows | x64 / ARM64 | EXE，附 VC++ CRT，需 WebView2 Runtime，无商业签名 |
| Linux | x64 / ARM64 | Debian 13 DEB，不保证其他发行版兼容 |
| iOS | ARM64 | iOS 16+ IPA，须自行合法签署主应用及 Share Extension；应用内只能下载/导出 |

全平台构建、回归测试和九包完整性检查通过后才创建正式发布，详见[构建记录](https://github.com/sobranie2406/modureader/actions)。自动化覆盖索引错配/损坏/取消/并发、朗读生命周期和参数恢复、字典格式与菜单交互；并不等于所有设备实测。vivo 长时间锁屏、厂商省电策略、通知交互和大体积商业字典仍需对应真机验证，不能保证系统永不回收后台程序。

## English

Modu **1.1.0 (build 10029)** is an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny.

- Android media playback controls and chapter loading independent of foreground layout; safer speech-rate updates and recovery after native audio-player failures.
- Optional WebDAV index sync, off per device by default. Indexes match actual book bytes by SHA-256 and are validated before local installation. Download the identical book first; queries still require the matching model. Index files include book excerpts and are not encrypted by API-key sync; use a trusted HTTPS server. Limit: 128 MiB per book.
- AI text searches reuse the shared hybrid index; duplicate index-building UI is removed. Reading skills retain their chapter/selection scope.
- Import, name and manage local MDX/StarDict dictionaries; query selected text offline. No dictionaries are bundled or synced. Text-only MDX 1/2 uncompressed/zlib and StarDict 2.4.2/3.0.0 are supported; encrypted/LZO/MDX 3, MDD media and DSL are unsupported.
- Unified long-press and three-dot book menus remain actionable during sync refresh. Mobile Quick mark can optionally open the selection menu after saving.
- Built-in provider reset clears saved API keys and restores default enabled state and parameters. Custom providers can be deleted from their detail page or by swiping the list, with confirmation.

Embedding models remain on-demand downloads from Hugging Face (default) or Gitee. App updates prefer Gitee with GitHub fallback and size/SHA-256 validation; installation requires user action. Both sites distribute identical binaries. Gitee contains packages/docs/update metadata only; [free corresponding source](https://github.com/sobranie2406/modureader/tree/v1.1.0) and [source ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.1.0.zip) are on GitHub.

Nine native packages: Android ARM64/x64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB and iOS ARM64 IPA. Android retains its signing identity; macOS is unnotarized, Windows lacks commercial signing, and iOS requires your own valid signing. Back up before upgrading. CI checks do not replace physical-device tests, particularly vendor background restrictions and long-duration locked-screen playback.
