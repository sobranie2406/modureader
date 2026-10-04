# Android local inference and haptics removal checks (2026-09-05)

> Historical record of the Beta1-era checks and Debug package described below; this is not certification of the latest 1.2.0 release. See the [documentation index](README.md).

## Problem and evidence limits

A user reported that tapping “Test inference” for each of the four bundled models crashed the app on a Xiaomi 15 Ultra.
The Android version, crash stack and a connected device were unavailable, so the final root cause on that phone could not be confirmed.

All four models shared the Android native library from flutter_onnxruntime 1.8.4, which originally pinned ONNX Runtime 1.23.0.
Upstream reports described SIGILL on some ARM Android devices with 1.23.x due to incorrect CPU instruction detection; Dart exception handling cannot intercept such process crashes.

- Native crash report: <https://github.com/microsoft/onnxruntime/issues/27282>
- Follow-up reports and fix confirmation: <https://github.com/microsoft/onnxruntime/issues/27884>
- SME1/SME2 distinction fix: <https://github.com/microsoft/onnxruntime/pull/25760>

## Changes in this round

- Pinned only Android's onnxruntime-android to 1.24.3, retaining CPU inference and the existing single-session serial scheduling. Apple/Windows/Linux runtime versions were unchanged.
- Tried 1.24.4, but Maven Central had no Android artifact; the build failed and that configuration was not retained. Comparing upstream 1.24.3 and 1.24.4 showed no CPU detection or MLAS changes in the latter; 1.24.3 already contained the SME1/SME2 fix and had an official Android artifact. Licenses were updated to match the actual version.
- Removed the vibration service, developer vibration test page, related settings and strings in 16 languages, and two vibration plugins.
- Disabled bottom-navigation feedback and used Manifest merger rules to prevent dependencies from reintroducing the VIBRATE permission. The Android Activity disabled DecorView haptic feedback, covering Flutter's long-press feedback path. The system keyboard's own vibration settings were unchanged.
- Regenerated CocoaPods lockfiles to remove the vibration plugins and align them with the existing Flutter plugins. Apple ONNX remained at 1.23.0; the Apple runtime was not upgraded.

## Verified

- Full Flutter suite: 205 passed, 2 skipped (network tests requiring explicit enablement).
- Platform regression checks for the final version configuration: 3 passed.
- Reader JavaScript regressions: 10 passed; release packaging script tests: 18 passed.
- Gradle debugRuntimeClasspath: the rule replaced 1.23.0 with 1.24.3.
- ONNX and JNI libraries for ARM64 / x86_64 in the official 1.24.3 AAR passed 64-bit architecture and 16 KB ELF LOAD alignment checks.
- Android ARM64 Debug APK built successfully; architecture and 16 KB ELF alignment checks passed for 7 native libraries. APK zipalign 16 KB checks and v2 signature validation passed.
- ONNX and JNI merge inputs matched the official 1.24.3 AAR exactly; libraries in the APK matched the build's stripped outputs exactly. Whole-file hashes of the AAR libraries and final APK libraries should not be compared directly because the build strips symbols.
- The APK contained all four ONNX models and updated licenses; the final permission list did not include VIBRATE.

Local test package: `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk` (about 246 MiB).
SHA-256: `4569628afae1ac88c20e2c814101a7d4db7fc09ee7057fdc61c5bc1a47efbf1f`.
This was Debug-signed, not an official update package, and could not be guaranteed to install over an existing Beta1. Do not uninstall the existing app merely to install it and lose books, notes or settings. No officially signed version was rebuilt or published.

## Device acceptance still pending

1. Preserve existing app data and test Chinese BGE, English BGE, MiniLM and E5 individually in a test version with the same official signature. Record actual output dimensions and whether the app crashes.
2. Queue book vectorization while reading other books; verify completion, cancellation and re-vectorization.
3. Check that bottom-navigation switching, statistics cards, long-press menus and text selection no longer trigger app vibration.
4. If crashes persist, collect the Android crash buffer during reproduction and distinguish SIGILL, SIGSEGV, Java exceptions and system low-memory termination before applying a targeted fix. Remove private information before sharing logs.

This round did not constitute acceptance of the fix on a device and did not automatically commit code or replace the GitHub Beta1 release package.
