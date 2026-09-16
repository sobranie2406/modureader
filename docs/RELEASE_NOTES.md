# 默读 / Modu 1.0.9 正式版

版本：**1.0.9+10027**。来源于 **Anx Reader** 和 **ReadAny（Reader Any）**，保留原作者版权与许可，是 GPL-3.0-or-later 独立修改版本。

## 本次更新

- **应用更新**：启动检查正式版；「设置 → 关于默读 → 版本检查与更新」支持检查、下载、取消及打开安装器。不会自动下载或静默安装。
- **Gitee 优先**：优先读取镜像清单，核对 GitHub 防止镜像滞后。安装包优先镜像；不可用或校验失败时重新下载 GitHub 相同版本，取消不会触发回退。
- **更新安全**：按平台和进程架构选包，校验大小与 SHA-256，安装前再次校验。Android 另验包名、签名和版本，使用系统安装器，不删除书库。
- **按需向量模型**：安装包不再内嵌四模型权重及分词器。「设置 → 向量模型 → 模型下载源」可选 Hugging Face（默认）或 Gitee。只主动下载所需模型，大小/SHA-256 验证通过后离线使用；旧版已准备的完整模型继续复用。保存来源选择，不静默切换。
- **公开模型镜像**：MiniLM、BGE EN、BGE ZH、E5 固定版本及原许可证见 [Gitee 模型镜像](https://gitee.com/sobranie2406/modu-models/releases/tag/models-v1)。E5 分片自动顺序合并并校验完整文件。默认中文 BGE、自动向量化关闭保持不变。

## 下载与对应源码

[GitHub 安装包](https://github.com/sobranie2406/modureader/releases/tag/v1.0.9) · [Gitee 安装包镜像](https://gitee.com/sobranie2406/modureader/releases/tag/v1.0.9)

Gitee 仅托管 Release 安装包、说明及更新清单，不上传应用源码。两站分发同一次构建的原始文件，不二次打包；请用各包的 SHA-256 文件校验。镜像逐包下载验证后才发布更新清单，清单尚未就绪时客户端回退 GitHub。

**对应版本完整源码（免费获取）**：[源码目录](https://github.com/sobranie2406/modureader/tree/v1.0.9)、[源码 ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.0.9.zip)、[构建说明](https://github.com/sobranie2406/modureader/blob/v1.0.9/docs/RELEASING.md)。源码包含依赖锁定与构建脚本。包内保留许可证及版权声明：[LICENSE](https://github.com/sobranie2406/modureader/blob/v1.0.9/LICENSE)、[NOTICE](https://github.com/sobranie2406/modureader/blob/v1.0.9/NOTICE)、[UPSTREAM](https://github.com/sobranie2406/modureader/blob/v1.0.9/UPSTREAM.md)。

## 安装包与限制

| 平台 | 架构 | 格式与限制 |
| --- | --- | --- |
| Android | ARM64 / x86_64 | APK，原专用签名，Android 8+；系统确认后安装 |
| macOS | ARM64 / Intel x64 | DMG，ad-hoc 签名，未公证；退出旧应用后拖入 Applications 替换 |
| Windows | x64 / ARM64 | EXE，附 VC++ CRT，需 WebView2 Runtime，无商业签名 |
| Linux | x64 / ARM64 | Debian 13 DEB，由系统包管理器安装，不保证其他发行版兼容 |
| iOS | ARM64 | iOS 16+ IPA，须自行合法签署主应用及 Share Extension；应用内只能下载/导出 |

九个平台包各附 SHA-256。旧版没有该更新功能，需手动安装本版后使用。升级前建议备份；书籍、笔记、进度和同步协议保持不变。模型下载源与应用更新镜像是独立设置。更新请求不携带书籍、密钥或服务凭据。

## 验证范围

全平台构建、架构/完整安装包集合/SHA-256 及 CI 回归全部通过后才创建正式发布。四模型匿名下载与完整 SHA-256（含 E5 合并）已实测；更新测试覆盖镜像优先、回退、取消、损坏拒绝和附件 CDN。

这不等于全部设备的实机验收。桌面端安装仍须用户按系统提示完成，iOS 仍需自行签名。[构建记录](https://github.com/sobranie2406/modureader/actions)。

## English

Modu 1.0.9 (build 10027), an independent GPL-3.0-or-later derivative of Anx Reader and ReadAny, adds launch-time update checks and About → App updates. Downloads prefer Gitee, fall back to the identical GitHub asset, verify size/SHA-256, and require installation consent. Android also verifies package identity, signing identity and version.

Four embedding models are now downloaded on demand, not bundled. Choose Hugging Face (default) or Gitee under Embedding Models. Existing verified models are reused; E5 parts are streamed together and checked against the original digest. Models run locally after download.

Gitee hosts binaries, documentation and update metadata only. Free corresponding source, dependency metadata and build scripts: [v1.0.9 source](https://github.com/sobranie2406/modureader/tree/v1.0.9), [source ZIP](https://github.com/sobranie2406/modureader/archive/refs/tags/v1.0.9.zip). Licenses and original attribution remain included. Both sites distribute identical binaries/checksums; mirror metadata is published after download verification.

Nine native packages: Android ARM64/x64 APK, macOS ARM64/x64 DMG, Windows ARM64/x64 EXE, Debian 13 ARM64/x64 DEB, iOS ARM64 IPA. Android retains its signing identity. macOS is unnotarized, Windows lacks commercial signing, and iOS requires your own valid signing. Desktop installation is user-assisted. Install this version manually to obtain the updater. CI/package checks do not replace full physical-device testing.
