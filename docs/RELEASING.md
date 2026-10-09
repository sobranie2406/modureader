# Building, releasing and installing Modu

Single-edition guide in English. Prepared for stable **1.2.4+10093**, 2026-10-09.

Modu is an independently modified derivative of Anx Reader (MIT) and ReadAny (GPL-3.0-or-later). Packages retain licenses; each release links its corresponding source, NOTICE and attribution. No separate notices ZIP is distributed.

## Build toolchain

Use the SDK pinned in [.github/flutter-version](../.github/flutter-version): Flutter 3.47.2 for 1.2.4. Run flutter pub get, flutter gen-l10n and build_runner before building. CI uses native platform runners. Windows ARM64 applies scripts/release/windows-arm64-sdk.mjs to accommodate host identification in the CI SDK, then verifies output PE architecture.

The tokenizer retains its original Rust implementation in third_party/hf_tokenizers. Mobile targets cross-compile with the corresponding Rust target and Flutter NDK / Apple SDK; do not substitute a fake tokenizer.

Android Rust links with 16 KB maximum/common page alignment; packaging checks ELF LOAD segments and APK ZIP alignment for native libraries. macOS/iOS builds append --build-name using the output of scripts/release/verify_mobile.py --apple-build-name, converting a prerelease marketing version such as 0.1.0-beta.1 to a valid 0.1.0. The build number still comes from pubspec's + suffix; packaging verifies it. Filenames/releases retain preview identifiers. These packaging corrections originally entered build 6326; old build 6325 caches do not contain them.

Windows packaging copies architecture-matched app-local VC++ CRT DLLs from the current Visual Studio Redist directory, verifies architecture and records versions/hashes in WINDOWS-RUNTIME.txt. Do not download DLLs from unofficial sites or install them into system directories. Missing redistributables fail packaging. Microsoft's redistribution terms apply separately from the app's GPL source.

Embedding and OCR weights are **not bundled**. Packages contain pinned metadata and SHA-256 manifests; users download models on demand. Existing verified local models can be reused. CI obtains isolated inference fixtures with scripts/release/bundle_models.py, without --install-assets. Production package checks reject bundled embedding weights. Android fixtures belong only in test APKs; desktop tests download from a local test server before offline inference. See [model mirrors](MODEL_MIRROR.md), [UPSTREAM](../UPSTREAM.md) and LICENSES for source and license details.

Linux packages target Debian 13 (trixie) and require GTK3, WPE WebKit 2.0, WPEBackend-FDO, libwpe, epoxy, GStreamer and audio plugins. Other distributions may require source builds. Windows needs Microsoft Edge WebView2 Runtime.

## Installation

| Platform | Installation and requirements |
| --- | --- |
| macOS | Open the processor-matched DMG and drag Modu.app to Applications. ARM64 is Apple Silicon; x64 is Intel. |
| Windows | Run the matching -setup.exe. Installation defaults to the current user with an optional desktop shortcut; uninstall through installed apps. VC++ CRT is included; WebView2 is required and not automatically downloaded. |
| Linux | On Debian 13, run sudo apt install ./Modu-VERSION-linux-ARCH.deb. Start from the app menu or modureader command. sudo apt remove modureader does not actively clear the personal library. x64 corresponds to amd64; ARM64 to arm64. |
| Android | Install the ARM64 APK. Updates must retain the same project signing key. Android x64 is not distributed. |
| iOS | The ARM64 IPA requires iOS 16+ and your own valid signing for the app and Share Extension. It cannot be installed directly without signing. |
| HarmonyOS | Native ARM64 HAP, unsigned and not yet device-validated. Sign locally with a valid HarmonyOS certificate/profile and install using the official tools. Android signing is not interchangeable. |

Mac disk images expose **only Modu.app and the Applications shortcut**. Attribution and licenses remain inside Contents/Resources/Distribution; packaging re-signs and verifies the app afterward. Other installers likewise keep necessary documents inside app resources/install directories rather than placing separate documentation packages in the release.

Check and download share one update-source selector, initially GitHub. A check falling back to Gitee switches the whole workflow. Check again after manual changes; do not switch sources during downloading. macOS downloads go to the default browser, not the app's sandbox cache; the app cannot report browser completion or hash verification. Other platforms retain in-app downloads and verification.

If an older in-app macOS update reports that Modu cannot open and system logs indicate creation without user consent, download the official DMG again through a browser and replace the app. Do not reuse the old in-app cache, clear the library, disable system protection or strip quarantine in update code. This workaround is not Developer ID signing or notarization.

## Package layout and signatures

Native installers are generated by scripts/release/native_installers.py. Windows uses pinned, SHA-256-verified Inno Setup 6.7.3; the installer engine architecture and packaged app architecture are distinct. Linux uses dpkg-deb and desktop-file-validate. macOS uses hdiutil and read-only mounts to verify signatures, architecture and layout.

Starting with 1.2.2, full releases contain **nine packages and nine SHA-256 files (18 assets)**: Android ARM64, iOS ARM64, ARM64/x64 for macOS, Windows and Linux, plus an unsigned native HarmonyOS ARM64 HAP. Android x64 is an internal emulator target only: do not package it, upload it or add it to update manifests. This policy does not delete historical releases. Omitting unsigned/unnotarized filename suffixes does not confer signing or notarization.

- Android uses a dedicated project key, never committed to Git. CI secrets are ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD and ANDROID_KEY_ALIAS. Gradle's local key.properties supports storeFile/storePassword/keyAlias/keyPassword. Rebuilds and updates retain the same key.
- macOS packages use ad-hoc signing, without Apple Developer ID notarization. Do not disable system-wide security; inspect source and build/sign locally if preferred.
- Windows installers/apps have no commercial Authenticode signature. Verify the source and SHA-256.
- iOS releases have no distribution signature and no App Store/TestFlight distribution. Sign the app and Share Extension with your own valid account/profiles. There is no x64 iPhone package.

Linux packages include the ONNX Runtime 1.22.0 shared library omitted by an older plugin layout. patchelf makes library lookup relative to installation paths rather than CI paths. Pinned official runtime downloads are hash-checked, with provenance in LINUX-RUNTIME.txt and licenses retained. Historical repackaging fixed distribution, not app business code.

## Documentation conventions

- README.md is the English homepage; README_zh.md is the Chinese homepage. README_EN.md redirects the legacy English entry. Describe current features, entry points, screenshots and installation without accumulating per-preview change sections.
- SETTINGS, PRIVACY, CONTRIBUTING and SECURITY have English defaults and separate _zh editions, with reciprocal language links. Other current guides use English when maintained as a single edition.
- [Documentation index](README.md) distinguishes current guides from historical releases/test evidence. Historical versions, test counts and limits remain historical; third-party originals and licenses are preserved.
- Update both homepages and paired user documents when functionality changes. User guide screenshots show actual layout; pair phone settings with Mac results and separate English/Chinese content.
- docs/RELEASE_NOTES.md prepares the current release description. Published changes must also update the corresponding release, not overwrite an older release with a new version's text.
- Starting with **1.2.0**, stable and preview notes use **English first, 简体中文 second**, in separate sections on both GitHub and Gitee. Do not reorder older versions or remove installation warnings, checksums or source links.
- For newly written release notes and changelog entries, use one concise change per Markdown bullet in the form `- Type(scope): Description`, following the supplied ANX-style example. Use `Feat` for features, `Fix` for fixes, `Perf` for performance, `Ci` for build/release automation, `Docs` for documentation and `Chore` for maintenance. Omit `(scope)` only for genuinely project-wide changes. Use stable module names such as `reader`, `tts`, `sync`, `bookshelf`, `ai`, `appearance`, `android` and `l10n`.
- Keep the same item order, type and scope in the English and Chinese sections. Describe actual Modu changes in the release's source range; do not copy another project's feature claims, issue numbers or credits. Add linked Issue/PR references and contributor thanks only when verified and relevant. Keep limitations and validation status accurate; installation/signing warnings, checksums and source links remain separate from the change bullets. Do not rewrite published historical releases merely to apply this style.

Example of the change-list format (not a published release):

```markdown
## English

- Feat(tts): Add configurable online speech lookahead, synthesis size and concurrency, paragraph pauses, cache retention and cache clearing; keep system TTS unchanged.
- Fix(tts): Allow a fresh synthesis request after a shared cached request times out.

## 简体中文

- Feat(tts): 新增在线朗读缓冲量、合成字数、并发数、段落停顿、缓存保留及清理设置，系统 TTS 保持原逻辑。
- Fix(tts): 修复共享缓存请求超时后无法重新发起语音合成的问题。
```

## Release procedure

1. Update pubspec.yaml and release notes; run relevant security checks and regression tests. Distinguish builds, automated checks and device validation.
2. Run Modu Packages with selected targets and the intended release tag, or push an authorized version tag. CI builds platform assets in parallel; create the source tag/release only after verification. Never retarget an existing tag to different source.
3. Failed targets must not produce apparently successful assets. Fix and rebuild them; a release asset proves production, not full device acceptance.
4. Retain LICENSE/NOTICE inside packages and SOURCE.txt inside desktop installations. Publish hashes and the exact tagged source. Prerelease tags create prereleases. A full stable release must verify all nine packages; scoped previews publish only the requested targets. The Harmony reusable workflow builds the same commit, verifies native assets and version/build identity, and never receives signing keys. Its failure blocks publication.
5. Do not run upstream store publishing or signing-service workflows. Modu uses its own Telegram release notifier described below.
6. Mirror the identical original packages following [UPDATE_MIRROR.md](UPDATE_MIRROR.md). On Gitee, confirm deletion authority and that GitHub retains the old release, then delete only the old app release/assets before uploading the new release. Verify every hash before updating the manifest. Retain local packages for retries; do not publish an unverified manifest. Do not delete model mirrors, source, tags or branches. GitHub retains release history from 1.1.0 onward.

## Telegram release announcements

The dedicated ModuReader bot posts to channel `-1004343451406`. Give it only the channel permission to post messages, and store its BotFather token as the repository Actions secret `TELEGRAM_BOT_TOKEN`. Never commit the token or put it in release notes.

`.github/workflows/telegram-release.yml` announces published stable and prerelease versions. It preserves the complete bilingual release body in its published order (English first, 简体中文 second), and includes the exact Release/download link. Long notes are split into numbered messages without dropping content. Drafts are rejected. The workflow has read-only repository permissions and uses only Python's standard library plus the official Telegram Bot API.

`Modu Packages` calls this reusable workflow after the release job succeeds: releases created by `GITHUB_TOKEN` do not trigger another `release` workflow. Releases published manually trigger it through `release: published`. Failed builds, ordinary commits and unpublished drafts send nothing. The notification is a separate job; it cannot prevent an already published release from existing.

For the initial announcement or recovery, run **Modu Telegram Release** with a published `release_tag` (or `latest` for the latest stable version). Manual runs and reruns send a new announcement, so check the channel before retrying a timeout or rerunning an already successful job. Automatic retries occur only after an explicit Telegram rate-limit rejection. Editing release notes alone does not send a second post.

Current automation is .github/workflows/build.yaml, pr-check.yml and scripts/release/. Fastlane/store files are historical templates, not Modu's distribution path.

The historical Native desktop installers workflow can repackage existing assets after verifying their hashes and tag identity, without recompiling the app or moving tags. INSTALLER-SOURCE.txt records packaging-script source and original hashes. This requires old assets to remain available; new releases use the normal build workflow.

[Source repository](https://github.com/sobranie2406/modureader) · [Settings](SETTINGS.md) · [Privacy](../PRIVACY.md) · [Upstream](../UPSTREAM.md)
