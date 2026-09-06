# 默读 · Modu Reader

[简体中文](README.md) | [English](README_EN.md)

<p align="center"><img src="assets/icon/modu-app-icon.png" width="120" alt="默读应用图标"></p>

**本项目来源于 [Anx Reader](https://github.com/anxcye/anx-reader) 和 [ReadAny（Reader Any）](https://github.com/codedogQBY/ReadAny)。感谢两个项目的原作者和贡献者。**
This is an independently modified derivative, not an official release of either upstream.

默读是基于 Flutter 的开源 AI 阅读器。把电子书、笔记、阅读进度与 AI 问答放在一起：先读书，再围绕当前章节提问；需要语义检索时，为书籍建立本地或远程向量索引。

**本地阅读不需要 AI 账号。** AI、在线翻译和在线语音按需配置，费用与可用性取决于所选服务。各版本更新与使用说明见 [Releases](https://github.com/sobranie2406/modureader/releases)。

[功能介绍](#功能一览) · [界面预览](#界面预览) · [开始使用](#开始使用) · [设置指南](docs/SETTINGS.md) · [下载](#下载)

## 下载

[GitHub Releases](https://github.com/sobranie2406/modureader/releases) · [构建状态](https://github.com/sobranie2406/modureader/actions) · [问题反馈](https://github.com/sobranie2406/modureader/issues)

| 平台 | 已发布架构 | 分发形式与限制 |
| --- | --- | --- |
| Windows | x64、ARM64 | EXE 安装器；支持快捷方式和卸载，未做商业代码签名，需要 WebView2 Runtime |
| Linux | x64、ARM64 | DEB；面向 Debian 13 (trixie)，使用 APT 安装并解析系统依赖 |
| Android | x86_64、arm64-v8a | 项目专用密钥签名的 APK；首次安装请核验下载来源 |
| macOS | x64、ARM64 | DMG；打开后拖入 Applications，未公证，非 App Store 版本 |
| iOS | ARM64 真机 | iOS 16+，**unsigned.ipa**；无 Apple 分发签名，不能直接安装，需要自行合法签名 |

这里的 x64 指 x86-64，ARM64 也是 64 位。iPhone/iPad 没有 x64 真机包。
安装包及 SHA-256 校验文件见 [Releases](https://github.com/sobranie2406/modureader/releases)，请按系统与架构选择。

桌面端使用原生安装包，不再以 ZIP / tar.gz 作为应用安装入口。Android 的 `-notices.zip` 是许可证资料；GitHub 自动提供的 `Source code (zip)` 是源码，两者都不是程序安装包。
不提供绕过操作系统安全机制的脚本。签名、依赖和安装说明见 [发布说明](docs/RELEASING.md)。

## 功能一览

当前版本提供以下阅读、AI 与书库管理功能。

| 模块 | 可以做什么 | 从哪里进入 |
| --- | --- | --- |
| 书架与导入 | 导入 EPUB、PDF、MOBI、AZW3、FB2、TXT；按阅读状态筛选、搜索、分组及管理标签 | 首页「书架」，添加按钮或书籍菜单 |
| 阅读与排版 | 目录跳转、阅读进度、分页/滚动、字体与字号、间距、背景及阅读主题；TXT 按规则转为 EPUB | 阅读页面；设置 → 阅读 |
| 标注与笔记 | 选文标注、记录想法、按章节整理；复制或导出 Markdown、TXT、CSV | 选中文本菜单；首页「笔记」 |
| 阅读统计 | 阅读时长、趋势、热力图与单本书的阅读记录 | 首页「统计」 |
| AI 对话 | 首页快捷提问、书内问答、对话历史；按开启的工具读取书架、目录、章节、笔记和阅读记录 | 首页「AI」；阅读页 AI 面板 |
| AI 阅读技能 | 十个中文内置技能；启用/停用、查看和编辑提示词、新建自定义技能 | 设置 → AI 阅读技能 |
| 语义检索与 RAG | 结合关键词与向量检索；本地索引、后台排队向量化、重新索引 | 书籍菜单；设置 → 向量模型 |
| 翻译 | 免费 Google 翻译、AI 翻译、DeepL/DeepLX；选文和阅读页全文翻译入口 | 设置 → 翻译；阅读页下方工具区 |
| 朗读 | 系统语音、Edge TTS、Xiaomi MiMo 和兼容在线服务；声音选择、试听、语速等参数 | 设置 → 朗读；阅读页朗读入口 |
| 同步与备份 | WebDAV 书籍、笔记、阅读进度同步；本地备份；独立加密的 API Key 同步 | 设置 → 同步 |
| 配置迁移 | AI 与 WebDAV 配置代码导入/导出、二维码展示及二维码图片读取 | AI 设置 / 同步 → 配置导入导出 |
| 外观与工具 | 系统/深色/浅色主题、封面显示、字体导入/下载、网络与日志选项 | 设置 → 外观 / 阅读 / 高级 |
| 问题反馈 | 填写问题与复现步骤，预览后前往 GitHub 提交 | 设置 → 提交 Bug |

### 围绕阅读内容使用 AI

首页 AI 适合书架、笔记和阅读记录相关的提问；阅读页 AI 适合当前书籍、章节或选中文字。首页提供一组快捷提示词，书内则使用已启用的阅读技能。两者的上下文不同，不应把首页问题自动当作“当前章节”的问题。

在「设置 → AI 设置 → 供应商配置中心」中添加或编辑模型，可分别设置接口地址、模型名称、API Key、温度、最大输出 Token 和上下文轮数。支持 OpenAI 兼容、Claude、Gemini 等协议；预设包含 OpenAI、Claude、Gemini、DeepSeek、智谱 GLM 和 OpenRouter，也可自定义兼容接口。模型列表、工具调用和参数范围仍取决于服务商实际支持情况。

AI 工具可以按需开关，包括查书、查笔记、检索正文、读取章节、查看阅读记录和生成思维导图等。AI 输出可能出错；全书总结受已获取正文、检索结果和模型上下文长度限制，不保证一次请求完整读完任意长书。

### 十个中文阅读技能

| 技能 | 用途 |
| --- | --- |
| 本章总结 | 梳理当前章节的主要内容、情节和主题 |
| 全书总结 | 概括已获取的全书内容与结构 |
| 概念解析 | 解释概念、术语与抽象观点 |
| 论证分析 | 拆解论点、推理与支持证据 |
| 人物追踪 | 整理人物关系及发展变化 |
| 金句摘录 | 提取值得记录的原文片段 |
| 阅读指南 | 生成阅读建议、讨论问题与反思方向 |
| 智能翻译 | 结合书籍语境翻译内容 |
| 词汇助手 | 解释生词、习语和专业表达 |
| 思维导图 | 将内容整理为层级结构 |

点击技能可打开提示词，修改后保存，也可恢复默认；自定义技能与内置技能一起出现在阅读 AI 面板中。「回忆前文」「翻译与词典」「全文翻译」等功能提示词也集中在同一设置页管理。

### 书籍向量化与本地模型

在书籍弹出菜单中选择「向量化」或「重新向量化」。不同书籍进入后台队列，不必停留在索引页面；任务状态和失败提示用于判断索引是否真正完成。要自动处理新书，还需在「设置 → 向量模型」同时启用向量模型和「导入后自动向量化」。自动向量化默认关闭。

| 本地 ONNX 模型 | 适用语言 | 向量维度 |
| --- | --- | --- |
| all-MiniLM-L6-v2 | 英文 | 384 |
| BGE Small EN v1.5 | 英文 | 384 |
| BGE Small ZH v1.5 | 中文 | 512 |
| Multilingual E5 Small | 多语言 | 384 |

应用**内嵌以上四个模型及分词器**，无需另行下载或填写 API Key 即可进行本地向量计算。默认选择中文 BGE，自动向量化默认关闭。模型资源合计约 208 MiB，首次使用会在本机准备文件。也可手动选择远程嵌入 API。切换模型后应对旧书重新向量化；聊天和向量模型是两套配置。

本地嵌入只表示向量计算在本机完成：若使用远程聊天、远程嵌入、翻译或语音接口，相关文本仍会发送给所选服务，不应将整个 AI 工作流宣传为完全离线。

### 翻译与朗读

选中文字或打开阅读页下方工具区即可翻译，支持 Google 翻译、AI 翻译和 DeepL/DeepLX。

朗读支持播放、暂停、恢复、上一句/下一句与章节切换。系统语音使用设备声音；在线语音可选择服务、音色和朗读参数。Xiaomi MiMo 提供内置音色与文字设计音色，支持 MP3/WAV，风格、语速和音高通过自然语言指令控制。语音合成或播放失败时会暂停并保留当前位置，便于重试。

### 同步与密钥安全

- WebDAV 用于同步书库、笔记和阅读进度，不需要使用默读专属云账号。
- 「同步 API Key」默认关闭，独立于 WebDAV 总开关；开启时需要设置独立密码并确认风险。
- 敏感服务配置以 **AES-256-GCM** 加密后写入同步数据库。其他设备需要同一密码；密码不随数据库同步，遗失无法找回。
- 加密不代表书籍、笔记和整个备份都被加密，也不能代替可信的 WebDAV 服务与强密码。
- **配置代码和二维码不是加密数据**，可能包含密码或 API Key。不要放入公开截图、Issue 或聊天群；它们与加密密钥同步是不同功能。

## 界面预览

以下为默读 macOS 实际界面，使用项目原创示例书。截图来自较早构建，供布局参考；具体选项与默认值以安装版本为准。

### 书籍阅读：正文、字体与阅读主题

原创示例书《阅读，让思考慢下来》的实际 EPUB 阅读界面，展示单列排版、中文字体、浅色阅读主题和底部进度信息。字号、行间距、分栏等可在阅读设置中调整。

![默读 EPUB 正文阅读：原创示例书、单列排版与浅色主题](docs/images/reading-epub-macos.jpg)

### 书内 AI：一边阅读，一边提问

阅读页可展开 AI 侧栏，保留左侧正文。右侧提供本章总结、全书总结、概念解析、论证分析、人物追踪、金句摘录、阅读指南、智能翻译、词汇助手和思维导图十个技能入口，也可以输入自己的问题。

![默读书内 AI 侧栏：左侧正文与右侧十个阅读技能入口](docs/images/reading-ai-panel-macos.jpg)

### 首页 AI：从快捷问题开始

首页集中展示十二个书库与阅读记录快捷问题，涉及最近阅读、笔记、未读书籍、阅读时长和书架整理；输入区另有解释、总结、分析等通用提问入口。

![默读首页 AI：十二个快捷问题和通用提问入口](docs/images/ai-home-prompts-macos.jpg)

截图展示阅读和 AI 操作入口；可[下载原创示例 EPUB](docs/examples/modu-reading-demo.epub)自行体验。

<details>
<summary>更多界面：章节目录、AI 技能管理与本地向量模型</summary>

### 章节目录与书签

![默读目录导航：搜索章节、跳转章节和查看阅读位置](docs/images/reading-toc-macos.jpg)

### AI 阅读技能与提示词管理

![默读 AI 阅读技能设置](docs/images/ai-reading-skills-macos.jpg)

### 本地向量模型与自动索引设置

![默读向量模型设置](docs/images/vector-models-macos.jpg)

</details>

## 开始使用

1. 从 [Releases](https://github.com/sobranie2406/modureader/releases) 下载对应系统和架构的包，先阅读该平台的安装限制。
2. 在书架添加电子书，打开后即可阅读；不使用 AI 时无需填写任何 API Key。
3. 需要 AI 时，在「设置 → AI 设置」配置模型，并先做连接测试。
4. 需要语义检索时，直接从书籍菜单手动建立索引，默认使用内嵌中文模型；其他模型及远程接口可在「向量模型」中选择。
5. 按需选择翻译、朗读与同步服务。详细操作、参数含义和安全注意事项见[设置指南](docs/SETTINGS.md)。

## 问题反馈

各版本的更新记录、适用范围及注意事项统一见 [Release 说明](https://github.com/sobranie2406/modureader/releases)。

发现问题时，请在本仓库 [Issues](https://github.com/sobranie2406/modureader/issues) 提供版本、系统与架构、复现步骤和不含私人资料的示例。请勿提交 API Key、WebDAV 密码或配置二维码。

## 从源码构建

固定 Flutter 版本记录在 [.github/flutter-version](.github/flutter-version)，依赖锁定在 pubspec.lock。
需要对应平台的 Flutter 原生工具链；本地 tokenizer 的源码编译还需要 Rust（移动端需相应 Rust target）。

```sh
python3 scripts/release/bundle_models.py # Python 3.11+，下载并校验固定版本模型，仅构建时联网
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter test --concurrency 1
# 在对应宿主平台运行：
flutter build macos --release --build-name "$(python3 scripts/release/verify_mobile.py --apple-build-name)"
# Android 的 release 签名先按 docs/RELEASING.md 配置
flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi
```

完整可复现的构建/打包步骤以 [.github/workflows/build.yaml](.github/workflows/build.yaml) 和 scripts/release 为准。
Dart 包名暂时保留 anx_reader，以兼容现有 import；用户可见品牌及应用 ID 为 Modu / com.modu.reader。

## 开源许可与来源

整体按 **GPL-3.0-or-later** 发布，见 [LICENSE](LICENSE)。
Anx Reader 的 MIT 版权与许可保留在 [LICENSES/Anx-Reader-MIT.txt](LICENSES/Anx-Reader-MIT.txt)；
ReadAny 的版权与许可保留在 [LICENSES/ReadAny-GPL-3.0-or-later.txt](LICENSES/ReadAny-GPL-3.0-or-later.txt)。
固定上游提交、修改范围和第三方归属见 [UPSTREAM.md](UPSTREAM.md)、[NOTICE](NOTICE)。
分发二进制时请保留许可、注明修改，并提供对应版本的完整源码与构建脚本。

[隐私说明](PRIVACY.md) · [安全报告](SECURITY.md) · [参与贡献](CONTRIBUTING.md)
