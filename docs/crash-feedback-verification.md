# Optional crash diagnostics and device environment verification

> Historical record. This preserves the two implementation-verification stages and their original results and limitations, including older feedback labels and Beta3 references. See the [documentation index](README.md) and the [current settings guide](SETTINGS.md) for Modu 1.2.0+10082, and [issue triage](issue-triage.md) for the current feedback entry. This documentation update did not rerun tests, build apps, inspect real crash records or reproduce device crashes.

## Workflow recorded at the time

Settings → Report a bug → describe the problem → optionally select “Include crash logs” → expand the log preview → preview and confirm the report → copy the complete report and open GitHub → the user pastes, reviews and submits it.

Logs were excluded by default. Deselecting removed already-loaded logs. During asynchronous loading, submission/copying of an incomplete report was disabled. Loading failure could be retried, and ordinary feedback remained available. Reports were not uploaded automatically and logs were not placed in the URL.

“Include device and runtime environment” independently controlled platform version, device model, CPU architecture, available memory-capacity information and Modu version/build. Fields varied by platform; missing fields were not guessed. Hostnames, user-assigned device names, accounts, serial numbers, IMEI, Android ID, device UUID, product ID and system build fingerprints were not exported.

## Cross-platform and system capability boundaries

- Android, iOS, macOS, Windows and Linux shared a local diagnostic journal: Flutter exceptions, types and app-source locations of unhandled main-isolate errors, session start/exit and vector-task stages/progress. Exception messages, ordinary logs, user file paths, book titles/text, URLs and keys were excluded. The latest 16 entries were retained with an approximately 30 KB file limit, outside WebDAV sync.
- The next launch retained previous records. A session without a confirmed normal exit was marked “previous session end not confirmed”; forced closure or system reclamation was not automatically classified as a crash.
- On Android 11+, opting in read available recent system abnormal-exit records for this app: reason, status code, time and sampled RSS/PSS. Android 12+ attempted native tombstone reading, retaining only up to 32 frames from the faulting thread with relative PCs, public library names and ELF Build IDs. At most three records were used, with a 1 MiB read limit per raw trace. Raw traces were neither written to disk nor shared; memory contents, log buffers, exception messages, thread names and full paths were ignored.
- Android exit records could originate from the same app before an upgrade. Missing local diagnostics or phase checkpoints from old versions could not be reconstructed.
- iOS/macOS integrated native MetricKit. Plugin registration subscribed to diagnostics and processed system-retained historical payloads. After asynchronous delivery, only up to 32 faulting-thread frames with known module names, module offsets, binary UUIDs, numeric exception types/signals, app version and report interval were saved in the app's support directory. At most three reports totaling 32 KB were retained, written atomically and excluded from system backups. Binary UUIDs identify code for symbolication, not devices. User `.ips` directories were not scanned and raw payloads were not persisted. Report intervals were not exact crash times. Delayed delivery, non-delivery and missing faulting threads were explicitly reported.
- Windows integrated `SetUnhandledExceptionFilter` + `StackWalk64`, with x64/ARM64 context branches. An app-specific record file was pre-opened at startup. On an exception, error code/time/build were written and flushed before attempting up to 32 frames, retaining only public DLL names, relative PCs and PE timestamps/image sizes. The next launch recovered the prior record. No minidump, exception parameters or symbol-server startup were included. Previous exception handlers and system exit behavior were preserved. Corrupted stacks, fail-fast, replacement of the handler by another component and system force-kill were not guaranteed to be captured. Windows compilation and actual subprocess-crash verification were still required at this stage.
- Linux read system-native records rather than installing a custom signal handler. After opt-in, it ran `coredumpctl --no-pager -1 --since=7 days ago info COREDUMP_EXE=<current executable absolute path>` via an argument array, targeting the latest record for this executable, with a 256 KiB total pipeline limit and five-second timeout. Failed exits or oversized output caused raw output to be discarded. Only the signal and public modules/offsets from the first thread stack provided by the system were exported; that thread was not assumed to be the faulting thread. It did not read core memory, run `dump`/`debug`, enable dumps or elevate privileges. Missing systemd-coredump, insufficient permissions, a changed installation path or cleared records were reported as unavailable. Support for all Linux distributions was not promised.
- No platform exported raw memory. Errors confined to child isolates and not forwarded, resource exhaustion or system force-kill could leave only the last operation record, or no record. Diagnostics stayed outside WebDAV sync.
- Adding diagnostics did not establish a fix for the recurring iQOO crashes or promise capture of every crash type.

Android official interfaces/formats: [ApplicationExitInfo](https://developer.android.com/reference/android/app/ApplicationExitInfo), [tombstone.proto](https://android.googlesource.com/platform/system/core/+/refs/heads/main/debuggerd/proto/tombstone.proto).

## Index state

A persistent `.building` marker was written before rebuilding and removed on normal completion, cancellation or a caught failure. Unexpected process termination left it behind. While present, the bookshelf could not label a book “indexed” from an old index or in-memory cache, though the old file was preserved for recovery. Logs distinguished extraction, preparation, embedding, saving and completion.

This only applied to rebuilds started after marker support was added. An indexed badge after an older-version crash could represent an old index or saving that completed before exit; the badge alone could not establish the cause.

## Stage one verification: local events and Android

- Full Flutter regression: **258 passed, two skipped**. Coverage included feedback service, diagnostic sanitization, optional checkboxes, copy after confirmation, asynchronous cancellation, device fields and index markers. File-by-file static analysis passed for the added diagnostic and marker code.
- Android ARM64 Debug and macOS Debug builds passed. Neither app was launched for real crash testing; Windows/Linux/iOS were not built or checked on devices in that round.
- Synthetic exceptions, private-field sentinels, synthetic tombstones, a mocked browser and clipboard were used. No real issue was submitted and no user books or service keys were read.
- No iQOO Neo8 was connected and no actual phone crash was induced.
- GitHub Release and README were not changed in that round; unverified claims were not placed on the homepage.

## Stage two verification: other native platforms

- Full Flutter regression: **267 passed, two skipped**; **34 feedback-related tests passed**. Added Apple/Windows/Linux format filtering, damaged/oversized input, pipeline timeouts and output-limit tests used synthetic data, without reading actual system crash records or submitting issues.
- Apple native Swift summary tests compiled and passed: faulting-thread selection, public-module allowlist, nested-stack traversal, 32-frame limit, damaged/oversized JSON and privacy sentinels.
- macOS Debug built successfully, confirming plugin registration and MetricKit linkage. No real app crash or actual asynchronous system delivery was verified.
- The full iOS app build was blocked by the local Xcode environment: `xcodebuild -showdestinations` reported `iOS 26.5 is not installed`, with no available build destination. SDK headers did not establish that the required platform components were installed. Components were not installed without authorization; this was not counted as a successful build.
- Using the local iOS SDK and Flutter iOS framework, the complete Apple plugin, including its iOS registration branch, passed `swiftc -typecheck -target arm64-apple-ios16.0`. This was native-code type checking, not an iOS app build or device diagnostic verification.
- Windows/Linux had not been built on their target systems or verified through the complete system-crash reading path. Windows supplied independent test source `test/native/WindowsCrashRecorderTest.cpp` for an isolated test account/VM only. It was not linked into the app and added no user-triggerable crash entry.
- Beta3 Release was not updated. New collectors could not reconstruct Windows stacks unrecorded by older versions, and did not establish a fix for the original vectorization crashes.

## Native test commands and symbolication

Apple summary test (macOS):

```sh
swiftc third_party/modu_native_crash/darwin/Classes/NativeCrashSummary.swift test/native/AppleCrashSummaryTest.swift -o /tmp/modu-apple-crash-summary-test
/tmp/modu-apple-crash-summary-test
```

Windows independent test (x64/ARM64 Native Tools developer command prompt in an isolated test account):

```bat
cl /std:c++17 /EHsc /W4 /WX /wd4100 /DUNICODE /D_UNICODE /DFLUTTER_VERSION_BUILD=6330 test\native\WindowsCrashRecorderTest.cpp windows\runner\native_crash_recorder.cpp /Fe:modu-crash-test.exe /link dbghelp.lib shell32.lib ole32.lib
modu-crash-test.exe
```

This test launches its own subprocess, induces a test exception and verifies readability on the next launch. Public module-relative offsets require binaries and dSYM/PDB/ELF debug symbols from the **same version and architecture as the crash**. Offsets or host-test results must not be treated as the cause of a phone crash.

Official references: [Apple MetricKit](https://developer.apple.com/documentation/metrickit/mxmetricmanager), [Apple callStackTree JSON](https://developer.apple.com/documentation/metrickit/mxcallstacktree/jsonrepresentation()), [Windows unhandled exception API](https://learn.microsoft.com/en-us/windows/win32/api/errhandlingapi/nf-errhandlingapi-setunhandledexceptionfilter), [StackWalk64](https://learn.microsoft.com/en-us/windows/win32/api/dbghelp/nf-dbghelp-stackwalk), [systemd coredumpctl](https://github.com/systemd/systemd/blob/main/man/coredumpctl.xml).
