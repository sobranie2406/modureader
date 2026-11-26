# Modu 1.3.12

Build / 构建：**10191** · Stable / 正式版

### English

- Feat(bookshelf): Create collections from first-level subfolders when importing or linking a local folder, or importing a remote folder. Existing books keep their collections. ([Issue #99](https://github.com/sobranie2406/modureader/issues/99)) Thanks [@guo1505208031-design](https://github.com/guo1505208031-design).
- Feat(remote-library): Browse and download books from read-only FTP sources. FTP and WebDAV keep separate settings.
- Feat(tts): Add DeepSeek narration with Stella and Tide voices. ([PR #98](https://github.com/sobranie2406/modureader/pull/98)) Thanks [@RuizeSun](https://github.com/RuizeSun).
- Feat(linux): Use the same x64 AppImage on Ubuntu 24.04, Ubuntu 26.04 and Arch Linux.
- Fix(weread): Support WeRead API 1.0.6 and keep displaying lookup results when the service prompts for an upgrade.
- Fix(ocr): Distinguish image decoding, model loading and inference failures in Windows OCR logs. ([Issue #85](https://github.com/sobranie2406/modureader/issues/85))

### 简体中文

- Feat(bookshelf): 本地文件夹导入、原位添加和远程文件夹导入可按一级子文件夹创建合集，重复书保留原合集。([Issue #99](https://github.com/sobranie2406/modureader/issues/99)) 感谢 [@guo1505208031-design](https://github.com/guo1505208031-design)。
- Feat(remote-library): 远程书库支持通过只读 FTP 浏览和下载书籍，FTP 和 WebDAV 分别保存配置。
- Feat(tts): 新增 DeepSeek 朗读，可选海星和暗潮两种音色。([PR #98](https://github.com/sobranie2406/modureader/pull/98)) 感谢 [@RuizeSun](https://github.com/RuizeSun)。
- Feat(linux): Ubuntu 24.04、Ubuntu 26.04 和 Arch Linux 共用一个 x64 AppImage。
- Fix(weread): 适配微信读书 API 1.0.6，收到接口升级提示时照常显示查询结果。
- Fix(ocr): Windows OCR 日志可区分图片解码、模型加载和推理失败。([Issue #85](https://github.com/sobranie2406/modureader/issues/85))

### Downloads / 下载

Android ARM64 · iOS ARM64 · macOS ARM64 / x64 · Windows ARM64 / x64 · Debian 13 DEB ARM64 / x64 · Linux x64 AppImage · HarmonyOS ARM64.

Sign the iOS IPA and HarmonyOS HAP before installing. macOS packages use ad-hoc signing. Windows requires WebView2. For AppImage dependencies and Ubuntu 24.04's Bubblewrap profile, see the installation guide.

iOS IPA 和鸿蒙 HAP 需自行签名。macOS 安装包使用临时签名。Windows 需要 WebView2。AppImage 运行依赖及 Ubuntu 24.04 的 Bubblewrap 启用步骤见安装说明。

[Source / 源码](https://github.com/sobranie2406/modureader/tree/v1.3.12) · [Installation / 安装说明](https://github.com/sobranie2406/modureader/blob/v1.3.12/docs/RELEASING.md) · [License](https://github.com/sobranie2406/modureader/blob/v1.3.12/LICENSE) · [Notice](https://github.com/sobranie2406/modureader/blob/v1.3.12/NOTICE)
