# Building, releasing and installing Modu

Single-edition guide in English. Prepared for stable **1.3.6+10168**, 2026-11-01.

Modu is an independently modified derivative of Anx Reader (MIT) and ReadAny (GPL-3.0-or-later). Packages retain licenses; each release links its corresponding source, NOTICE and attribution. No separate notices ZIP is distributed.

## Build toolchain

Use the SDK pinned in [.github/flutter-version](../.github/flutter-version): Flutter 3.47.2 for 1.3.6. Run flutter pub get, flutter gen-l10n and build_runner before building. CI uses native platform runners. Windows ARM64 applies scripts/release/windows-arm64-sdk.mjs to accommodate host identification in the CI SDK, then verifies output PE architecture.

Current Android builds use Gradle 9.2.1 (checksum-pinned), AGP 9.0.1 and Kotlin 2.3.20 with `android.builtInKotlin=true`. Gradle 9.2.x's embedded Kotlin 2.2.20 matches the pinned Flutter 3.47.2 build plugin; see the [Gradle compatibility matrix](https://docs.gradle.org/current/userguide/compatibility.html). Keep `android.newDsl=false` while Flutter still uses legacy Android extension APIs ([AGP opt-out](https://developer.android.com/build/releases/agp-9-0-0-release-notes)). The minimum Android version remains API 26.

Library modules with an older compile SDK are raised to API 36 at DSL finalization, without changing their minimum or target SDK. AGP 9 validates library-to-library AAR requirements too; for example, `audio_service`'s old API 33 setting cannot consume its API 34+ dependencies.

`android/modu_builtin_kotlin.gradle` migrates the 14 pinned legacy plugin build scripts into build-only overlays under `build/plugin-gradle/`, following the [Flutter plugin migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors). It removes explicit KGP application/classpath and uses `kotlin.compilerOptions`, preserving each plugin's Java/Kotlin target, runtime sources, dependencies and resources. Neither Pub cache nor other platforms' builds are edited. The normalized source SHA-256 pins in `android/modu_builtin_kotlin.json` fail closed on upstream build-script changes: review the migration when upgrading a plugin, then update/remove its pin. Java/Kotlin target validation is enabled, not suppressed.

The same overlay also migrates deprecated Groovy property assignment syntax, with additional non-Kotlin build scripts pinned in `android/modu_gradle_syntax.json`. Jetifier is disabled: the current dependency graph passes AAR metadata checks without it. `sqflite_android` 2.4.2+2 provides Android 16 Locale/thread API guards; `sqflite_common` is pinned to 2.5.6, before later transaction behavior changes. Database schemas and sync protocols are unchanged.

CI pins command-line tools 16.0 (12266719) and points `cmdline-tools/latest` to the selected installation, preserving the runner's previous directory. The emulator action prepends this path and would otherwise use its outdated XML parser despite a newer tool on PATH.

Validation (2026-10-11): the ARM64 preview.2 APK passed release-signature, native JNI retention and 16 KB ELF/ZIP alignment checks. Full Flutter regression passed 2528 tests with 13 skipped; 60 focused JavaScript tests also passed. Gradle configuration, database-plugin Java compilation and AAR metadata checks pass without the reported Java/Groovy deprecations. Flutter still requires `android.newDsl=false`; its AGP deprecation warning remains visible. SDK parser selection has regression tests; full stable packages must pass the cloud release gates before publishing. These checks do not replace device acceptance.

Build 10107 adds isolated AI menus/history and prevents AI Knowledge follow-ups from invoking book tools. Local regression passed 2,538 Flutter tests (13 skipped), 487 JavaScript tests, and 186 Python checks (15 skipped); the latest focused AI/history/storage checks also passed. Cloud package gates and device acceptance remain separate checks.

Build 10108 adds chapter-document validation and failed-resource invalidation for retry, preserving the outgoing page and reading position. All 585 JavaScript tests pass, including controlled null-document recovery and shared-resource retention. The reader bundle compiles with three existing top-level-await/legacy-target warnings. Xiaomi device revalidation remains pending; these local checks do not replace the full cloud release gates.

Development analysis now uses a vendored Riverpod native analyzer plugin in an isolated tool dependency graph compatible with the pinned Flutter/Dart SDK. The app retains Riverpod 2 runtime dependencies; do not run the removed custom_lint entry. Use `flutter analyze --no-pub` / `dart analyze` and see [local toolchain](development/local-toolchain.md). CI retains analyzer and test gates. Historical build counts above describe 1.2.6, not current release acceptance.

Native library extraction remains enabled through `packagingOptions.jniLibs.useLegacyPackaging=true`. Do not restore the old explicit `android:extractNativeLibs` manifest attribute: AGP 9 rejects that configuration at packaging time. Native JNI and 16 KB alignment verification still apply.

Use `node scripts/build_android.mjs` for local and CI APK builds. It defaults to release ARM64 and accepts Flutter options such as `--build-name=1.2.6-preview.1 --build-number=10103`. It uses existing `android/key.properties`, signing environment variables, or the local ignored `.release-secrets` identity, without printing credentials. It never generates a new signing key.

Do not use `--no-pub` for this build entry. Flutter tests can leave dev plugins in `GeneratedPluginRegistrant.java`; a release build must regenerate the registry with release dependencies. The wrapper rejects `--no-pub` rather than removing `integration_test` from development dependencies, editing generated Java, or suppressing compiler errors. Direct Gradle instrumentation tasks must follow a successful Flutter release build as in CI.

The tokenizer retains its original Rust implementation in third_party/hf_tokenizers. Mobile targets cross-compile with the corresponding Rust target and Flutter NDK / Apple SDK; do not substitute a fake tokenizer.

Android Rust links with 16 KB maximum/common page alignment; packaging checks ELF LOAD segments and APK ZIP alignment for native libraries. macOS/iOS builds append --build-name using the output of scripts/release/verify_mobile.py --apple-build-name, converting a prerelease marketing version such as 0.1.0-beta.1 to a valid 0.1.0. The build number still comes from pubspec's + suffix; packaging verifies it. Filenames/releases retain preview identifiers. These packaging corrections originally entered build 6326; old build 6325 caches do not contain them.

Windows packaging copies architecture-matched app-local VC++ CRT DLLs from the current Visual Studio Redist directory, verifies architecture and records versions/hashes in WINDOWS-RUNTIME.txt. Do not download DLLs from unofficial sites or install them into system directories. Missing redistributables fail packaging. Microsoft's redistribution terms apply separately from the app's GPL source.

Embedding and OCR weights are **not bundled**. Packages contain pinned metadata and SHA-256 manifests; users download models on demand. Existing verified local models can be reused. CI obtains isolated inference fixtures with scripts/release/bundle_models.py, without --install-assets. Production package checks reject bundled embedding weights. Android fixtures belong only in test APKs; desktop tests download from a local test server before offline inference. See [model mirrors](MODEL_MIRROR.md), [UPSTREAM](../UPSTREAM.md) and LICENSES for source and license details.

Linux packages target Debian 13 (trixie) and require GTK3, WPE WebKit 2.0, WPEBackend-FDO, libwpe, epoxy, GStreamer and audio plugins. Other distributions may require source builds. Windows needs Microsoft Edge WebView2 Runtime.

## Installation

| Platform | Installation and requirements |
| --- | --- |
| macOS | Open the universal DMG and drag Modu.app to Applications. It runs natively on Apple Silicon and Intel. |
| Windows | Run the universal -setup.exe; it installs the native x64 or ARM64 payload. Installation defaults to the current user with an optional desktop shortcut; uninstall through installed apps. VC++ CRT is included; WebView2 is required and not automatically downloaded. |
| Linux | On Debian 13, run sudo apt install ./Modu-VERSION-linux-ARCH.deb. Start from the app menu or modureader command. sudo apt remove modureader does not actively clear the personal library. x64 corresponds to amd64; ARM64 to arm64. |
| Android | Install the ARM64 APK. Updates must retain the same project signing key. Android x64 is not distributed. |
| iOS | The ARM64 IPA requires iOS 16+ and your own valid signing for the app and Share Extension. It cannot be installed directly without signing. |
| HarmonyOS | Native ARM64 HAP, unsigned. Sign locally with a valid HarmonyOS certificate/profile and install using the official tools. Android signing is not interchangeable. |

Mac disk images expose **only Modu.app and the Applications shortcut**. Attribution and licenses remain inside Contents/Resources/Distribution; packaging re-signs and verifies the app afterward. Other installers likewise keep necessary documents inside app resources/install directories rather than placing separate documentation packages in the release.

Check and download share one update-source selector, initially GitHub. A check falling back to Gitee switches the whole workflow. Check again after manual changes; do not switch sources during downloading. macOS downloads go to the default browser, not the app's sandbox cache; the app cannot report browser completion or hash verification. Other platforms retain in-app downloads and verification.

If an older in-app macOS update reports that Modu cannot open and system logs indicate creation without user consent, download the official DMG again through a browser and replace the app. Do not reuse the old in-app cache, clear the library, disable system protection or strip quarantine in update code. This workaround is not Developer ID signing or notarization.

## Package layout and signatures

### Windows unattended installation and capture troubleshooting

Modu release installers use Inno Setup, not NSIS. Use `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-`, not `/S`. The current release generator rejects the exact `/S` or `/s` option during initialization (exit code 1) and writes the correct command to the setup log. This change does not apply retroactively to downloaded older installers or installers from the retired standalone packaging path. Older installers can fall back to a wizard and wait for input. Unknown options other than `/S` retain Inno Setup's behavior.

In PowerShell, replace `VERSION` and choose the correct architecture, then wait for the installer and check both its exit status and output:

```powershell
$installer = (Resolve-Path '.\Modu-VERSION-windows-x64-setup.exe').Path
$installDir = Join-Path $env:LOCALAPPDATA 'Programs\Modu'
$setupLog = Join-Path $env:TEMP 'modu-install.log'
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
    ('/DIR="{0}"' -f $installDir), ('/LOG="{0}"' -f $setupLog))
$process = Start-Process -FilePath $installer -ArgumentList $arguments -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installation failed ($($process.ExitCode)); see $setupLog" }
if (!(Test-Path (Join-Path $installDir 'modu.exe'))) { throw "Missing installed executable; see $setupLog" }
```

Inspect the installed application's version as well when updating an existing installation; an old executable's presence alone does not prove an update succeeded. Setup logs are also enabled by default under `%TEMP%` with a `Setup Log ...` filename. For Git Bash, prefix the command with `MSYSNOPATHCONV=1` so MSYS does not rewrite the slash-prefixed options. See the official [command-line options](https://jrsoftware.org/ishelp/topic_setupcmdline.htm) and [exit codes](https://jrsoftware.org/ishelp/topic_setupexitcodes.htm).

A white/black image returned by `PrintWindow` or `BitBlt` is not sufficient evidence that the visible app failed to render. First inspect the on-screen window; try Windows Snipping Tool (`Win+Shift+S`) or a capture tool using Windows.Graphics.Capture. If the visible Modu window itself is blank, record the Modu, Windows and WebView2 versions and export logs for investigation. Do not disable system protection or change rendering backends solely to accommodate a capture API. The existing Windows CI launch/close check verifies that a window becomes visible; it does not validate its pixels or reading behavior.

### Packaging details

Both Mac architectures are still compiled separately. The universal stage merges every Mach-O slice and the Flutter native-asset manifest, verifies matching common resources, re-signs the final app and verifies native launch on Intel and Apple Silicon runners. Windows uses one Inno installer with architecture-specific payload checks; native CI tests cover clean installation and upgrading from 1.3.5 on x64 and ARM64. Linux packaging remains architecture-specific. Old filenames must remain available on both GitHub and Gitee; new clients prefer the universal filenames.

Native installers are generated by scripts/release/native_installers.py. Windows uses pinned, SHA-256-verified Inno Setup 6.7.3; the installer engine architecture and packaged app architecture are distinct. Linux uses dpkg-deb and desktop-file-validate. macOS uses hdiutil and read-only mounts to verify signatures, architecture and layout.

Starting with 1.3.6, full releases contain **seven primary packages plus four compatibility copies, each with a SHA-256 file (22 assets)**: Android ARM64, iOS ARM64, universal macOS, universal Windows, Linux ARM64/x64, and unsigned HarmonyOS ARM64. The four old Mac/Windows architecture filenames contain byte-identical copies of their universal installer, preserving pre-1.3.6 updater compatibility. Versions 1.2.2–1.3.5 used nine primary packages. Android x64 is an internal emulator target only: do not package it, upload it or add it to update manifests. This policy does not delete historical releases. Omitting unsigned/unnotarized filename suffixes does not confer signing or notarization.

- Android uses a dedicated project key, never committed to Git. CI secrets are ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASSWORD and ANDROID_KEY_ALIAS. Gradle's local key.properties supports storeFile/storePassword/keyAlias/keyPassword. Rebuilds and updates retain the same key.
- macOS packages use ad-hoc signing, without Apple Developer ID notarization. Do not disable system-wide security; inspect source and build/sign locally if preferred.
- Windows installers/apps have no commercial Authenticode signature. Verify the source and SHA-256.
- iOS releases have no distribution signature and no App Store/TestFlight distribution. Sign the app and Share Extension with your own valid account/profiles. There is no x64 iPhone package.

Linux packages include the ONNX Runtime 1.22.0 shared library omitted by an older plugin layout. patchelf makes library lookup relative to installation paths rather than CI paths. Pinned official runtime downloads are hash-checked, with provenance in LINUX-RUNTIME.txt and licenses retained. Historical repackaging fixed distribution, not app business code.

## Documentation conventions

- README.md is the default Chinese homepage; README_EN.md is the complete English homepage. README_zh.md retains a compatibility link to the Chinese homepage. Describe current features, entry points, screenshots and installation without accumulating per-preview change sections.
- SETTINGS, PRIVACY, CONTRIBUTING and SECURITY have English defaults and separate _zh editions, with reciprocal language links. Other current guides use English when maintained as a single edition.
- [Documentation index](README.md) distinguishes current guides from historical releases/test evidence. Historical versions, test counts and limits remain historical; third-party originals and licenses are preserved.
- Update both homepages and paired user documents when functionality changes. User guide screenshots show actual layout; pair phone settings with Mac results and separate English/Chinese content.
- docs/RELEASE_NOTES.md prepares the current release description. Published changes must also update the corresponding release, not overwrite an older release with a new version's text.
- Public release notes do not list pending physical-device validation. Keep detailed test coverage in dated testing reports, and retain known compatibility limits and installation requirements without claiming unverified fixes.
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

A stable-release request includes **GitHub and Gitee publication by default**. Gitee is not an optional follow-up and must not be silently skipped. If access, permissions, capacity or verification prevent completion, report the remaining mirror work explicitly; GitHub publication alone is not full release completion.

1. Update pubspec.yaml and release notes; run relevant security checks and regression tests. Distinguish builds, automated checks and device validation.
2. Run Modu Packages with selected targets and the intended release tag, or push an authorized version tag. CI builds platform assets in parallel; create the source tag/release only after verification. Never retarget an existing tag to different source.
3. Failed targets must not produce apparently successful assets. Fix and rebuild them; a release asset proves production, not full device acceptance.
4. Retain LICENSE/NOTICE inside packages and SOURCE.txt inside desktop installations. Publish hashes and the exact tagged source. Prerelease tags create prereleases. A full stable release must verify all seven primary packages and four compatibility copies; scoped previews publish only the requested targets. The Harmony reusable workflow builds the same commit, verifies native assets and version/build identity, and never receives signing keys. Its failure blocks publication.
5. Do not run upstream store publishing or signing-service workflows. Modu uses its own Telegram release notifier described below.
6. Mirror the identical original packages following [UPDATE_MIRROR.md](UPDATE_MIRROR.md). On Gitee, confirm deletion authority and that GitHub retains the old release, then delete only the old app release/assets before uploading the new release. Verify every hash before updating the manifest. Retain local packages for retries; do not publish an unverified manifest. Do not delete model mirrors, source, tags or branches. GitHub retains release history from 1.1.0 onward.

### Completion checklist

- [ ] GitHub has the exact source tag, bilingual notes, all nine installers and nine verified SHA-256 sidecars.
- [ ] Gitee has the same version, notes, filenames and byte-identical installers/sidecars; public downloads, sizes and hashes are verified following [UPDATE_MIRROR.md](UPDATE_MIRROR.md).
- [ ] Only after asset verification, the Gitee `master` branch's `updates/latest.json` is updated and publicly checked for the new version and eight supported installer targets (HarmonyOS remains a manual download).
- [ ] Telegram and QQ jobs are checked separately. Failed or uncertain sends are investigated before retrying; build success is not delivery confirmation. See [QQ release announcements](../scripts/community/README.md).
- [ ] The handoff reports GitHub, Gitee/manifest and both notification results, including any blockers. Do not describe a GitHub-only publication as the completed two-site release.

## Telegram release announcements

The dedicated ModuReader bot posts to channel `-1004343451406`. Give it only the channel permission to post messages, and store its BotFather token as the repository Actions secret `TELEGRAM_BOT_TOKEN`. Never commit the token or put it in release notes.

`.github/workflows/telegram-release.yml` announces published stable and prerelease versions. It preserves the complete bilingual release body in its published order (English first, 简体中文 second), and includes the exact Release/download link. Long notes are split into numbered messages without dropping content. Drafts are rejected. The workflow has read-only repository permissions and uses only Python's standard library plus the official Telegram Bot API.

`Modu Packages` calls this reusable workflow after the release job succeeds: releases created by `GITHUB_TOKEN` do not trigger another `release` workflow. Releases published manually trigger it through `release: published`. Failed builds, ordinary commits and unpublished drafts send nothing. The notification is a separate job; it cannot prevent an already published release from existing.

For the initial announcement or recovery, run **Modu Telegram Release** with a published `release_tag` (or `latest` for the latest stable version). Manual runs and reruns send a new announcement, so check the channel before retrying a timeout or rerunning an already successful job. Automatic retries occur only after an explicit Telegram rate-limit rejection. Editing release notes alone does not send a second post.

Current automation is .github/workflows/build.yaml, pr-check.yml and scripts/release/. Retired Fastlane/store templates and standalone packaging scripts were removed from the active tree on 2026-10-28; Git history retains them.

The historical Native desktop installers workflow can repackage existing assets after verifying their hashes and tag identity, without recompiling the app or moving tags. INSTALLER-SOURCE.txt records packaging-script source and original hashes. This requires old assets to remain available; new releases use the normal build workflow.

[Source repository](https://github.com/sobranie2406/modureader) · [Settings](SETTINGS.md) · [Privacy](../PRIVACY.md) · [Upstream](../UPSTREAM.md)
