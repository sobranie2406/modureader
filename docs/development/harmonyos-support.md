# Native HarmonyOS support — preparation, not a released target

Status on 2026-10-07: **cloud build integration in progress, not device-verified**. An `ohos/`
directory is not evidence of platform support. Android APKs, including APKs
running on older Huawei devices, are not native HarmonyOS NEXT packages.
The target is a HAP application using Flutter OH and native ArkTS adapters,
not an Android compatibility layer. Do not add it to the release matrix yet.

## Work completed in this preparation pass

- Made native OS classification explicitly testable. `ohos` is distinct from
  `android` and `linux`; unknown platforms fail instead of being guessed.
- Changed the OHOS download/staging path to the application sandbox. It no
  longer tries desktop `HOME/Downloads` or Android storage permissions.
  This is **not** a public document export implementation.
- Updated the inherited Harmony application identity/version metadata for the
  current source snapshot and localized template descriptions. Removed an
  inherited cloud `client_id` that is not referenced by Modu code. Version
  metadata must be synchronized with `pubspec.yaml` at each future build.
- Added a read-only dependency/toolchain audit and regression tests. It scans
  resolved runtime manifests instead of treating a plugin's Android support
  as OHOS support. It also reports FFI/native-hook dependencies for review.
- Left the shared dependency graph, existing clients, sync configuration,
  release workflow and real user data unchanged.

## Run the audit

From `modu_app`, after dependencies have already been resolved:

```sh
dart run scripts/dev/check_harmony.dart
```

Optional environment variables `MODU_OHOS_FLUTTER` and `MODU_HARMONY_SDK` point
to explicit, independently installed SDK directories. The script checks their
presence only; it does not certify versions, accept licenses, download SDKs,
select a signing identity, install packages on devices or access cloud data.
`dart run` itself may prepare normal Dart build-hook artifacts.

A nonzero exit code means prerequisites or required adapters are missing.
Desktop/Android-specific implementation packages appear in the inventory but
do not by themselves block readiness: their parent plugin registration and
platform guards must be reviewed. Even a zero exit code is **not** a release
gate pass: native channels, ABI assets, HAP compilation and device verification
are separate checks.

## Observed blockers

By user decision, full compilation runs in the cloud, not on the local Mac.
The independently installed Flutter OH 3.41.9+ohos-1.0.2 (Dart 3.11.5) was
verified, then moved to Trash on 2026-10-07 with its private package cache.
The incomplete DevEco 6.1.1 installer was also moved to Trash; DevEco Studio
and the HarmonyOS SDK were never installed. Existing Android/desktop tooling
was left unchanged. No local HDC or signing identity has been provisioned.
Unsigned build profiles now require API 26 compilation, retain the API 24
target and minimum API 17, and use modelVersion 26.0.0. The normal desktop/Android dependency graph remains
unchanged. The Harmony-only overlay pins upstream adapters for preferences,
paths, database, picker, package info, connectivity, links, audio and WebView,
including their federated implementations. A declaration is not runtime proof:

| Area | Required work |
| --- | --- |
| Startup and storage | Adapt `shared_preferences`, `path_provider`, `package_info_plus`, `sqflite`; preserve the same database schema and record identifiers |
| Reading and PDF | Adapt `flutter_inappwebview`, ArkWeb JavaScript callbacks, local reader-server access, selection gestures and image/PDF rendering |
| Import/export | Adapt `file_picker` and replace/adapt `flutter_file_dialog`; use document-provider URIs and scoped access, never assume every returned URI is a local path |
| Audio | Adapt `audio_service`, `audio_session`, playback, focus/interruption events and background-session lifecycle; startup currently awaits audio initialization |
| System speech | The existing build explicitly excludes OHOS system TTS; add and test a native adapter before enabling it |
| OCR and local embeddings | Validate `flutter_onnxruntime`, ONNX binaries and the Rust `hf_tokenizers` native build hook against the OHOS ABI; Android `.so` libraries are not proof of compatibility |
| Device integrations | Review battery, keep-awake, connectivity, sharing, permissions, links and save-to-gallery adapters |
| Custom platform channels | Review brightness, selection expansion, folder import and other Modu channels individually; do not silently substitute no-op handlers |

The `hf_tokenizers` source currently requires Dart >=3.10. Selecting an old
Flutter OH SDK solely because it can generate `ohos/` will not satisfy all
dependencies. Check actual Dart constraints and framework APIs against a pinned
SDK release. Do not downgrade the shared Android/iOS/desktop dependencies to
force an OHOS solve.

## Next implementation sequence

1. Provision Flutter OH and Huawei command-line tools on an isolated CI runner,
   not the user's Mac; inspect exact released versions and licenses. Generate a disposable template with that
   toolchain and reconcile the missing profiles with `ohos/`, without
   overwriting Modu identity/resources. Keep signing material local.
2. Resolve pinned OHOS forks in an **isolated build workspace**, including
   federated platform packages and native dependencies. Keep normal builds on
   their current package graph. Record upstream revisions and licenses before
   adopting code. Do not pin guessed repository branches or moving HEADs.
3. Bring up preferences, paths and database migration, then the bookshelf,
   import and ArkWeb-based EPUB/PDF reader. Verify both empty installs and
   upgrading an existing native test installation without clearing data.
4. Connect document pickers, sharing, audio, app links and custom ArkTS
   channels. Do not claim a feature works merely because it no longer throws
   `MissingPluginException`. Any reduced-feature preview must disclose and
   obtain agreement on its scope.
5. Port ONNX/tokenizer assets and OCR with cancellation/memory tests. Online
   AI is not an implicit replacement for local processing and must not receive
   book text without the user's existing explicit service configuration.
6. Run actual-device tests: pagination/selection, PDFs/crop/OCR, import/export,
   background narration, lifecycle/restart, encrypted settings, WebDAV and
   object-storage synchronization, and existing-platform regressions. Build,
   sign and inspect a HAP before advertising native HarmonyOS support.

## Cloud compilation / local signing policy (2026-10-07)

`.github/workflows/harmony-cloud.yml` is a separate, manual, experimental job.
It does not change `build.yaml`, the supported release matrix or existing
WebDAV/object-storage settings. It pins Flutter OH to tag
`3.41.9+ohos-1.0.2` and verifies commit
`62357a93d653bf844f730bb1f4b7cc9e2139d14e`. All SDKs and the Pub cache live on
the ephemeral runner, not in the source repository or on the local Mac.

The workflow is being validated on the isolated `codex/harmony-cloud` branch;
neither `main` nor the normal release workflow is changed. Its narrowly scoped
push trigger permits initial validation without installing a workflow on main.
Dependency resolution and actual HAP compilation are separate from local
fixture tests. The readiness audit deliberately fails on missing required
adapters or their unresolved federated implementations. Audit-only mode omits
the native SDK check and does not install Huawei tools.

`scripts/harmony/prepare.py` writes a dependency overlay only inside a fresh
Actions checkout and refuses local execution. It also adds the pinned WebView
Windows implementation missing from its upstream manifest to that disposable
root pubspec, since an override alone does not add a package to the graph.
The canonical project pubspec is not rewritten. Adapter revisions are full Git
commits in two JSON manifests, not moving branch names. The overlay preserves
Modu's local icon/tokenizer packages and AI forks, replacing the entire WebView
package family (including Windows) to avoid mixing incompatible interfaces.
The package source changes do not enter other clients' dependency resolution.

Cloud verification has passed official tool download/archive verification and
Rust target setup. The first dependency solve exposed `flutter_test`'s meta
1.17.0 pin versus hooks 2.2.0/record_use's meta >=1.19.0 requirement; the
Harmony-only overlay now selects meta 1.19.0 (Dart >=3.5), while retaining the
Flutter OH intl 0.20.2 pin. A completed HAP is still required for acceptance.

Dependency preflight uses Dart after caching Flutter's common/OHOS engine
artifacts (including sky_engine), with FLUTTER_ROOT explicitly selected. Native
plugin generation uses Flutter pub only after the verified Huawei SDK is set
up. Flutter's OHOS post-processing requires a real SDK even when solving has
already succeeded. Both HOS_SDK_HOME and DEVECO_SDK_HOME select the SDK parent;
OHOS_SDK_HOME selects its default/openharmony native-tool subtree. Node is
explicitly selected from the same official bundle.

The pinned WebView 6.1.5 adapter lacks two APIs used by Modu. A fail-closed,
cloud-only patch copies three verified packages before adding native ArkWeb
focus and a creation-time JavaScript bridge policy. Untrusted web results keep
their bridge disabled; reader callbacks remain available. See
`scripts/harmony/WEBVIEW_PATCH.md`. Existing platform source and PUB_CACHE are
not patched in place.

`patch_ui.py` also copies three exact pub.dev releases into an isolated UI
adapter directory: flex_color_scheme 8.3.0, flutter_math_fork 0.7.4 and mongol
9.3.0. Forty reviewed OHOS case labels share the existing Android/mobile
behavior to cover Flutter OH's additional TargetPlatform enum value. Package
archive identities, edited-file hashes, paths and versions are checked before
patching. No native API is replaced with a no-op and no cache source is edited.

The pinned Flutter OH lacks the newer onReorderItem callback used by two Modu
settings lists. `patch_app.py` adapts those two exact sites only in the runner
checkout, using onReorder and normalizing downward destination indices. The
normal clients retain their existing callback API and drag behavior.

The fixed Flutter OH SDK maps OHOS native-hook inputs to Linux and filters
arbitrary environment variables. Explicit `hooks.user_defines.hf_tokenizers`
therefore select the OHOS Rust triple, SDK, linker and pinned Rust toolchain.
Configure these **after host Dart code generation**, immediately before HAP
compilation. The hook refuses malformed targets, wrong ELF architecture and
glibc dependencies instead of falling back to a Linux binary. System library
availability and device loading still require verification.

Before enabling `build_hap`, a repository owner must configure:

| GitHub setting | Value |
| --- | --- |
| Secret `HARMONY_LINUX_TOOLS_URL` | Authorized official **Linux x64 Command Line Tools ZIP** download URL, not the Mac IDE installer; use a secret because download links may contain expiring tokens |
| Variable `HARMONY_LINUX_TOOLS_SHA256` | Exact SHA-256 from Huawei's download page for that ZIP |
| Variable `HARMONY_TOOLS_LICENSE_ACCEPTED` | `true` only after the owner has reviewed and accepted the applicable command-line tools/SDK terms |

No Huawei account password is needed in CI. Do not circumvent the vendor's
login/license flow or mirror the SDK publicly. Expired download links must be
renewed through the authorized download page. The archive installer expects
the official `sdk/default/openharmony` and bundled Node layout. It prefers the
documented `command-line-tools/bin` OHPM/Hvigor wrappers, with a fallback for
older component-specific `ohpm/bin` and `hvigor/bin` layouts;
if a version changes it, stop and review instead of selecting arbitrary tools.
SDK version compatibility and an actual HAP build remain to be verified.

Cloud run [37572018760](https://github.com/sobranie2406/modureader/actions/runs/37572018760)
passed Dart AOT compilation, the 19 native-hook tests, and the real OHOS ARM64
Rust tokenizer build. ArkTS compilation then exposed an SDK mismatch: the pinned
Flutter engine uses API 26 autofill declarations absent from the API 24 SDK.
The engine already guards those calls on older devices; do not remove its
autofill implementation or disable type checks. Three additional WebView
inference errors have been repaired using explicit types and regression tests.
These repairs still need the next native compilation run.

The official download page lists Linux x64 Command Line Tools 26.0.0.851.
The profile follows the [official API 26 compatibility table](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/deveco-studio-new-features-2600).
On this Mac the new official download was blocked by Chrome with
`ERR_BLOCKED_BY_CLIENT`; user handoff was requested. Until its authorized URL
and official checksum are available, no API 26 tool archive or final HAP has
been verified. Do not reuse the API 24 archive with the new compile profile.

Download recheck on 2026-10-07: the Chinese download page lists Linux x86
6.1.1.418, but clicking it in the available browser disables the link and logs
`Trustdomain has not been initialized, external links cannot be accessed safely`.
No archive or authorized file URL was returned. The English page was also
checked but did not yield a usable Linux download. This is an unresolved
download-page failure, not proof that Huawei's archive itself is corrupt.
The public [Huawei Cloud mirror](https://repo.huaweicloud.com/harmonyos/ohpm/)
only lists releases through 5.1.0; do not silently downgrade the build SDK.

Follow-up: the owner manually downloaded
`commandline-tools-linux-x64-6.1.1.418.zip` (2,141,614,766 bytes). The full file
matches the owner-provided official SHA-256
`39f1368dfcc6a8441f780cda44165e1f873f088680f250c382aa3324e95d9777`,
and ZIP integrity/path checks pass. Archive metadata identifies HarmonyOS
6.1.1, API 24, SDK version 6.1.1.125. The actual bundled Node path is
`command-line-tools/tool/node`, now supported along with the older `node`
layout. No local SDK installation or Linux binary execution was performed.
The authorized CDN URL recovered from the downloaded file's provenance
metadata returned HTTP 206 and a ZIP signature in a range probe on this Mac.
This confirms current local reachability, not GitHub-runner access or permanent
validity; the signed URL can expire. Keep it only in the repository's encrypted
`HARMONY_LINUX_TOOLS_URL` secret, never in source code or logs.

The installer now stages downloads as `.part` and rejects non-ZIP responses
(including login/error HTML), SHA-256 mismatches, invalid ZIP/CRC data and
unsafe member paths before extraction. Failures do not register tool paths.
Local packaging/download validation tests pass; these fixture tests do not
establish that a HAP builds. Full archive validation is recorded separately above.

After adapters and unsigned build profiles are ready, the workflow generates
code, runs `flutter build hap --release --no-codesign --no-pub --target-platform ohos-arm64`, and
collects only `*-unsigned.hap` plus `SHA256SUMS` as seven-day Actions artifacts.
It does not publish a Release or upload complete build/SDK directories.
The collector checks archive structure/CRC, the ARM64 tokenizer ELF header and
its ohos_arm64 native-assets mapping. These checks are not signature verification
or device testing.

Local handoff: obtain the version-matched official HAP signing utility and Mac
HDC only when a build is ready. Java is already present; verify the signing
tool's supported Java version before using it. Keep the keystore, passwords,
Huawei certificate and signed provisioning profile outside the repository.
The debug profile must authorize the test device and match `com.modu.reader`.
Download the unsigned artifact, verify its checksum, sign with the official
tool, verify the resulting signature, then install via HDC on an explicitly
selected device. Unsigned HAPs are not directly installable. No certificates
have been created/imported, no signing tool/HDC has been installed, and no
device has been provisioned by this change. Do not use OpenHarmony sample
keys as a substitute for Huawei retail-device signing credentials.

References: [Huawei command-line tools](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/ide-commandline-get)
and [pipeline setup](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/ide-command-line-building-app-V14).

## Upstream references

- [Flutter OH SDK/engine and supported HAP build commands](https://gitcode.com/CPF-Flutter/flutter_flutter)
- [Flutter OH environment setup](https://gitcode.com/CPF-Flutter/flutter_samples/blob/master/docs/ohos/getting-started/flutter-oh-env-setup.md)
- [Flutter OH build guide](https://gitcode.com/CPF-Flutter/flutter_samples/blob/master/docs/ohos/app-development/flutter-oh-app-build-guide.md)
- [Maintainer plugin catalog and migration notice](https://github.com/OpenHarmony-TPC/flutter_packages)
- [Huawei development-assistant configuration](https://developer.huawei.com/consumer/cn/doc/start/hosdevassistant-config-0000002588511280)

Catalog support is upstream evidence, not acceptance testing of Modu's specific
versions. Native compilation has been attempted in CI, but a complete HAP and
real-device verification are still outstanding.
