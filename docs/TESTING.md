# Testing policy and historical evidence

> Current testing policy applies to 1.2.0. Historical records below concern the pre-public-Beta baseline and 0.1.0-beta.1 checks stated there; they are not certification of the latest 1.2.0 release. See the [documentation index](README.md).

## Current testing policy for 1.2.0

Released baseline: Modu **1.2.0+10082**, source revision [77dc238f](https://github.com/sobranie2406/modureader/tree/77dc238fb2ae2ce02455bd80c500ee9fd140f219). Released-version facts in this overview refer to that revision. Use the publishing repository and this source revision to identify the release; an identically named upstream tag is not the same product.

Record the exact source revision, version/build, platform, architecture, commands, results and skipped tests for each verification run. Historical counts below remain evidence of their original runs and must not be presented as current totals.

The released revision's quality workflow, [pr-check.yml](https://github.com/sobranie2406/modureader/blob/77dc238fb2ae2ce02455bd80c500ee9fd140f219/.github/workflows/pr-check.yml), runs Flutter analysis and tests, the native inference worker lifecycle regression, Python release/package and project checks, and reader JavaScript regressions. Its [package workflow](https://github.com/sobranie2406/modureader/blob/77dc238fb2ae2ce02455bd80c500ee9fd140f219/.github/workflows/build.yaml) adds native build and package validation. Report analyzer/plugin failures, warnings and skipped network or device tests explicitly; a configured workflow or successful compilation alone is not runtime acceptance.

Keep automated checks, browser fixtures, installer/signature/architecture checks and installed-device acceptance separate. Use synthetic books and test credentials, and enable live network tests explicitly. Verify affected behavior on the relevant native platforms before claiming device acceptance; browser or host-only checks cannot establish that result.

For 1.2.0, the distribution scope is eight packages: Android ARM64, iOS ARM64, and ARM64/x64 for macOS, Windows and Linux, each with SHA-256. Android x64 remains an internal emulator target. The [release and installation instructions at 77dc238f](https://github.com/sobranie2406/modureader/blob/77dc238fb2ae2ce02455bd80c500ee9fd140f219/docs/RELEASING.md) record that release's package, signing and source requirements; consult the [maintained instructions](RELEASING.md) for subsequent policy changes. Fastlane metadata is a historical development template rather than a current distribution path.

This overview states policy; it does not report a new test run, package build or 1.2.0 certification.

## Historical evidence: testing scope

Baseline before the first public Beta: Flutter 161 passed, 2 tests requiring explicit network enablement skipped; JavaScript 8 passed; release architecture validation 4 passed.
Synthetic PDF / EPUB fixtures are in docs/qa/2026-09-05/full-audit/fixtures and contain no private data.

Actual macOS UI checks covered normal/password-protected/corrupt PDF imports, automatic indexing and re-vectorization, PDF contents/page numbers, EPUB body display, native fullscreen and return, and selected settings and encryption prompts.
These checks did not establish acceptance of all AI, TTS, translation, footnotes, backup restoration, long-running queues or all platforms.
CI compilation results and device runtime results must be recorded separately. An empty package or workflow configuration alone must not be treated as success.

Linux CI identified and fixed missing platform detection and the related directory/database branches. Native packaging separately verified ELF/PE/Mach-O architectures; Android checked the dedicated signing certificate fingerprint; macOS verified ad-hoc signing; Linux checked dynamic library linkage. These checks did not mean that all platforms' interactive features had been tested on devices.

### Release package review (2026-09-05)

- Local Flutter business tests were rerun: 163 passed, including explicitly enabled live Edge TTS MP3 synthesis and free Google translation tests; JavaScript 8 passed; packaging checks 5 passed. Network tests used fixed synthetic text, with no private books or paid API keys.
- The macOS ARM64 release package launched successfully and was confirmed as version 0.1.0-beta.1. Settings categories, ten AI reading skills, prompt-preview dialogs and the catalog of four local vector models opened successfully. Two README screenshots came from this release package.
- The same release package imported a synthetic PDF through the file picker, displayed English and Chinese body text and image pages, and completed page turns. Automatic indexing of that book failed because the selected local model had not been downloaded; successful import was not treated as successful vectorization. This round did not cover EPUB, password-protected/corrupt PDF or all reading operations.
- A separately added fresh-install system-narration probe reproduced `No voice selected for TtsService.system`: without a selected voice, the business method failed before calling native speak. This probe was not included in the preceding 163 existing passing tests and still required a fix.
- Source and plugin inventories confirmed that Linux system TTS was not implemented, although settings still displayed and selected it by default. Linux device verification was incomplete; this did not imply that online TTS was also unavailable.
- Windows, Linux, Android and iOS release packages had not completed full GUI acceptance. Partial macOS success likewise did not establish complete acceptance of paid AI, real model inference, audio playback, WebDAV servers or destructive backup restoration.

### Native installer review (2026-09-05)

All six desktop targets in [workflow 33953107529](https://github.com/sobranie2406/modureader/actions/runs/33953107529) passed; packaging unit tests increased to 10.

- macOS x64 / ARM64: DMG generation, disk-image integrity checks, read-only mounting, the Applications drag-and-drop link, deep ad-hoc application signing, native architecture and source-record checks.
- Windows x64 / ARM64: actual silent EXE installation in temporary CI systems of the corresponding architecture, application and DLL architecture checks, uninstallation, and checks that synthetic files outside the installation directory were retained. A race in the ARM64 test's wait for the uninstaller to clean itself up was fixed.
- Linux x64 / ARM64: actual APT installation of the DEB and system dependencies in Debian 13 containers, checks of the menu entry, ELF architecture and dynamic linkage of the main executable and bundled shared libraries, followed by actual uninstallation.
- These Linux checks identified and fixed a missing physical ONNX Runtime library in the original archive and a plugin dependency on absolute CI paths. The new DEB included the same-version official library and used relative RPATH. The old tar.gz was no longer offered as the application download entry.

These were installer and runtime-dependency checks, not full Windows / Linux GUI acceptance, and did not mean that the TTS business issues above had been fixed. Application business code was not recompiled in this round; Android / iOS packages were unchanged.
