# 发布与安装说明

本项目来源于 Anx Reader (MIT) 和 ReadAny (GPL-3.0-or-later)，是独立修改版本。源码、许可及 NOTICE 随包提供。

## 构建

固定 SDK：Flutter 3.47.2。先运行 flutter pub get、flutter gen-l10n 和 build_runner。CI 使用各平台原生 runner，Windows ARM64 显式指定目标架构。
分词器使用 third_party/hf_tokenizers 中保留原始 Rust 实现的兼容版本；移动端通过 Rust target 和 Flutter 提供的 NDK / Apple SDK 交叉编译，不使用假分词器替代。

Linux 包面向 Ubuntu 24.04，运行需 GTK3、WPE WebKit 1.1（或兼容 2.0）、WPEBackend-FDO、libwpe、epoxy、GStreamer 及音频插件；不同发行版可能需要自行从源码构建。Windows 需要 Microsoft Edge WebView2 Runtime。

## 签名

- Android 使用本项目专用签名密钥；密钥不提交 Git。CI 使用 ANDROID_KEYSTORE_BASE64、ANDROID_KEYSTORE_PASSWORD、ANDROID_KEY_ALIAS 三个 Secrets。重建/更新 APK 必须沿用同一密钥。android/key.properties 可按 Gradle 的 storeFile/storePassword/keyAlias/keyPassword 配置。
- macOS 包仅作 ad-hoc 签名，没有 Apple Developer ID 公证。不要关闭整个系统的安全保护；可自行审查源码并本地构建/签名。
- Windows 首版便携包没有商业 Authenticode 签名；请核对下载来源和 SHA-256。
- iOS unsigned.ipa 是 ARM64 真机应用容器，**没有分发签名、不能直接安装**。需用自己的开发者账号和合法配置为主应用及 Share Extension 签名。没有 x64 iPhone 安装包，也没有 App Store / TestFlight 发布。

## 发布流程

1. 更新 pubspec.yaml 和发布说明，运行安全扫描与回归测试。
2. 只在本仓库创建版本标签；GitHub Actions 并行生成各平台/架构制品。
3. 失败的目标不产生冒充成功的附件；修复后重新构建。最终 release 的附件才表示已产出。
4. 各包附 SOURCE.txt、LICENSE、NOTICE；Release 发布校验和与对应标签源码。初始版本保持 prerelease。
5. 不运行上游 App Store、Play Store、Telegram 通知或签名服务流程。

对应源码： https://github.com/sobranie2406/modureader 。依赖的固定版本、源地址、许可见锁文件及 UPSTREAM.md；发行包自带 Flutter 生成的第三方许可汇总。
