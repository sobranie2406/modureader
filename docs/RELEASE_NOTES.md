# Modu 1.2.1 · Stable

## English

**Modu 1.2.1 (build 10086)** includes the following changes since stable **1.2.0**.

- Fix TXT / Markdown downloads failing checksum validation after conversion to EPUB. New imports retain their source identity while checking the stored file; devices retaining older local books repair metadata during sync. Upgrade and sync the device holding the local book before retrying its download elsewhere. Do not delete or release the only local copy.
- Improve WebDAV startup, new-device synchronization, error reporting and privacy-safe metadata diagnostics. Retain legacy database compatibility, database integrity validation, conditional writes and conflict checks.
- Automatically recognize Jianguoyun WebDAV and coalesce repeated automatic-sync triggers: subsequent starts are at least ten minutes apart. A conservative per-device/account budget allows up to 480 requests in a rolling half-hour. Request budgets and server cooldowns survive restarts; other devices and apps still share the provider's account limits.
- Reduce repeated book/cover listings, redundant Basic-authentication OPTIONS probes and unchanged maintenance requests. Schedule old replaced-file cleanup instead of running it every sync. Ordinary WebDAV servers keep their usual automatic-sync frequency; HTTP 429/503 cooldown and Retry-After handling apply to all providers.
- Improve PDF and scanned-book rendering, raster reuse and tap-to-turn responsiveness. Strengthen paper-background whitening and improve enhancement adjustment feedback. Ordinary text-book reading remains separate from scanned-page processing.
- Selection AI defaults to including context, with selected-text-only still available. Explicit scope choices are preserved in settings.
- Add the QQ community to About and Bug reports / Feature requests: group **1009765685**, copyable group number and zoomable original invitation code.

Eight installers, each with SHA-256: Android ARM64; iOS ARM64; macOS, Windows and Linux ARM64/x64. Android x64 is not distributed. Mac disk images contain only Modu.app and the Applications shortcut.

Back up and upgrade in place. Android retains the project signing key. macOS uses ad-hoc signing and is not notarized; Windows requires WebView2; Linux packages target Debian 13; iOS requires your own valid signing for the app and Share Extension. Models remain on-demand downloads.

[Corresponding source](https://github.com/sobranie2406/modureader/tree/v1.2.1) · [Changes since 1.2.0](https://github.com/sobranie2406/modureader/compare/v1.2.0...v1.2.1) · [Installation guide](https://github.com/sobranie2406/modureader/blob/v1.2.1/docs/RELEASING.md)

---

## 简体中文

**Modu 1.2.1（构建 10086）**，以下为 **1.2.0 正式版以来**的变化。

- 修复 TXT、Markdown 转为 EPUB 后，云端下载因文件校验不一致而失败。新导入保留原始书籍身份并校验实际存储文件；持有旧版本地书籍的设备会在同步时修复相关元数据。请先升级并同步保留本地书籍的设备，再到其他设备重试下载；不要删除原书或释放唯一的本地副本。
- 改善 WebDAV 启动、新设备同步、错误提示及脱敏诊断；保留旧数据库兼容、完整性校验、条件写入和防冲突检查。
- 自动识别坚果云 WebDAV，合并反复修改设置等操作触发的自动同步，后续自动同步至少间隔 10 分钟。同一设备、同一账号采用滚动半小时最多 480 次请求的保守预算；预算及服务端冷却跨重启保留。其他设备和应用仍会共同消耗坚果云账号的访问额度。
- 减少同轮书籍及封面重复扫描、Basic 认证的重复 OPTIONS 请求和无变化维护请求；旧替换文件清理改为定期执行。其他 WebDAV 保留原有自动同步频率，各服务器均遵循 429／503 冷却及 Retry-After 提示。
- 优化 PDF、扫描图片书渲染与页面缓存复用，修复点击图片区域无法翻页，改善翻页响应；增强纸张底色增白处理及调节反馈。普通文字书仍使用独立的阅读处理逻辑。
- 划词 AI 默认结合上下文，继续保留“仅选中文字”选项，用户明确选择的范围随设置保存。
- “关于”和“问题反馈与功能建议”增加默读 QQ 交流群：**1009765685**，支持复制群号及放大查看原始二维码。

共 **8 个安装包**，各附 SHA-256：Android ARM64、iOS ARM64，以及 macOS、Windows、Linux 的 ARM64／x64；不发布安卓 x64。Mac 安装盘仅展示 Modu.app 和 Applications 快捷入口。

请先备份，再覆盖升级，不要先卸载或清空数据。Android 沿用原签名；macOS 为 ad-hoc 签名且未公证；Windows 需要 WebView2；Linux 面向 Debian 13；iOS 需自行签名主应用及 Share Extension。模型继续按需下载。

[对应源码](https://github.com/sobranie2406/modureader/tree/v1.2.1) · [1.2.0 至 1.2.1 源码差异](https://github.com/sobranie2406/modureader/compare/v1.2.0...v1.2.1) · [安装说明](https://github.com/sobranie2406/modureader/blob/v1.2.1/docs/RELEASING.md)
