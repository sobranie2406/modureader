# 发布与安装说明

本项目来源于 Anx Reader (MIT) 和 ReadAny (GPL-3.0-or-later)，是独立修改版本。源码、许可及 NOTICE 随包提供。

## 构建

固定 SDK：Flutter 3.47.2。先运行 flutter pub get、flutter gen-l10n 和 build_runner。CI 使用各平台原生 runner，Windows ARM64 使用 scripts/release/windows-arm64-sdk.mjs 对 CI SDK 的宿主识别做显式兼容补丁，再验证生成文件的 PE 架构。
分词器使用 third_party/hf_tokenizers 中保留原始 Rust 实现的兼容版本；移动端通过 Rust target 和 Flutter 提供的 NDK / Apple SDK 交叉编译，不使用假分词器替代。

Linux 包面向 Debian 13 (trixie)，运行需 GTK3、WPE WebKit 2.0、WPEBackend-FDO、libwpe、epoxy、GStreamer 及音频插件；不同发行版可能需要自行从源码构建。Windows 需要 Microsoft Edge WebView2 Runtime。

## 各平台安装方式

- macOS：下载对应处理器的 `.dmg`，打开后将 `Modu.app` 拖到 `Applications`。ARM64 对应 Apple Silicon，x64 对应 Intel。
- Windows：下载对应处理器的 `-setup.exe`，运行安装向导。默认仅为当前用户安装，可选桌面快捷方式；在系统“已安装的应用”中卸载。应用仍需要 Microsoft Edge WebView2 Runtime，安装器不自动下载运行库。
- Linux：下载 `.deb`，在 Debian 13 中执行 `sudo apt install ./Modu-版本-linux-架构.deb`，由 APT 安装所需系统依赖；从应用菜单或 `modureader` 命令启动。卸载使用 `sudo apt remove modureader`，不会主动清除个人书库。x64 对应 Debian amd64，ARM64 对应 arm64。不宣称兼容其他发行版。
- Android：安装对应 ABI 的 `.apk`，更新时沿用同一专用签名。
- iOS：`.ipa` 保留未签名标记，需自行合法签名后安装，详见下节。

桌面制品通过 `scripts/release/native_installers.py` 生成。Windows 使用固定版本且校验 SHA-256 的 Inno Setup 6.7.3；安装器引擎与应用架构是两个概念，包内程序按 x64 / ARM64 原生构建并校验。Linux 依赖 `dpkg-deb` 和 `desktop-file-validate`；macOS 使用系统 `hdiutil`，生成后只读挂载并校验应用签名与架构。Android 的 `-notices.zip` 只是许可证附件，不是安装包。

## 签名

- Android 使用本项目专用签名密钥；密钥不提交 Git。CI 使用 ANDROID_KEYSTORE_BASE64、ANDROID_KEYSTORE_PASSWORD、ANDROID_KEY_ALIAS 三个 Secrets。重建/更新 APK 必须沿用同一密钥。android/key.properties 可按 Gradle 的 storeFile/storePassword/keyAlias/keyPassword 配置。
- macOS 包仅作 ad-hoc 签名，没有 Apple Developer ID 公证。不要关闭整个系统的安全保护；可自行审查源码并本地构建/签名。
- Windows 首版安装器和应用没有商业 Authenticode 签名；请核对下载来源和 SHA-256。
- iOS unsigned.ipa 要求 iOS 16 或更新版本，是 ARM64 真机应用容器，**没有分发签名、不能直接安装**。需用自己的开发者账号和合法配置为主应用及 Share Extension 签名。没有 x64 iPhone 安装包，也没有 App Store / TestFlight 发布。

## 发布流程

1. 更新 pubspec.yaml 和发布说明，运行安全扫描与回归测试。
2. 只在本仓库创建版本标签；GitHub Actions 并行生成各平台/架构制品。
3. 失败的目标不产生冒充成功的附件；修复后重新构建。最终 release 的附件才表示已产出。
4. 各包附 SOURCE.txt、LICENSE、NOTICE；Release 发布校验和与对应标签源码。初始版本保持 prerelease。
5. 不运行上游 App Store、Play Store、Telegram 通知或签名服务流程。

历史压缩包迁移可手动运行 `Native desktop installers` 工作流：校验现有附件与标签源码身份后，仅重新封装安装器，不重新编译应用、不移动既有标签。`INSTALLER-SOURCE.txt` 单独记录安装脚本提交和原始附件校验和。此迁移流程依赖旧附件仍在 Release；迁移完成后的新版本直接使用常规构建流程。

对应源码： https://github.com/sobranie2406/modureader 。依赖的固定版本、源地址、许可见锁文件及 UPSTREAM.md；发行包自带 Flutter 生成的第三方许可汇总。
