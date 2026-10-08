# Android reader animation and AI keyboard regression

## Scope

Real-device investigation of the reported Android book-opening and AI-dialog
jank. The user authorized testing with the existing local library and sending
the current chapter of the selected EPUB to the device's configured DeepSeek
service. No library reset, book deletion, sync-provider change, or publication
was performed. Screenshots, raw frame captures, and book text are not included
in this repository.

Device: Honor LGE-AN10, Android 15, 120 Hz display, 1148 × 2492 test resolution. Source
version: `1.2.3-preview.2+10089`; measurements below use signed profile builds.

## Changes

- Keep the Android native reader outside the Hero overlay. Animate a fixed-size
  cover layer instead, without delaying reader initialization. Other platforms
  retain the previous Hero behavior; disabled/E Ink transitions remain disabled.
- Prefer `initSurfaceAndroidView` through the reader WebView's
  `useHybridComposition: false`, instead of forcing the expensive hybrid path.
  Flutter still owns its platform fallback. A diagnostic build can restore the
  forced hybrid path with
  `--dart-define=MODU_READER_HYBRID_COMPOSITION=true`.
- When the AI body has less than 240 logical pixels of height, use a compact
  composer with draft input, send/stop, and hide-keyboard controls. Keep the
  controller and TextField state while layout changes. This fixes the reproduced
  landscape overflow in which auxiliary controls pushed the editor off-screen.
- Retain the existing reader popup's single keyboard-inset handling. The
  portrait double-inset gap visible in the supplied video did not reproduce on
  this checkout; do not claim a new fix for that already-correct path.

## Device evidence

### Opening and closing the same local EPUB three times

Warm the book once, then repeat: open, wait 2200 ms, close, wait 1800 ms.
Reset Android `dumpsys gfxinfo` immediately before each sequence.

| Profile configuration | Native frames | Native janky frames | Native p95 |
| --- | ---: | ---: | ---: |
| Cover-only Hero candidate, forced hybrid composition | 419 | 145 (34.61%) | 38 ms |
| Fixed-size cover Hero + texture-layer preference | 737 | 64 (8.68%) | 16 ms |
| Same candidate, second three-cycle run | 636 | 88 (13.84%) | 21 ms |

These are Android frame-deadline statistics, **not FPS measurements**. The
number of produced frames differs between configurations. This is a same-device
diagnostic comparison, not a multi-device benchmark or a claim of zero jank.
The comparison also includes cover-layer caching; it does not isolate its
effect from the composition change.

Flutter's separate frame stream for the latter sequence recorded 731 frames:
3 frames exceeded 16.67 ms in build or raster work, none exceeded 33.33 ms;
build p95 2.27 ms, raster p95 8.21 ms. Native and Flutter statistics must not be
combined: Flutter-only timing missed much of the original native composition
cost. At 120 Hz the actual frame budget is approximately 8.33 ms.

### Real AI output and keyboard

The authorized chapter summary completed through the configured service.
During the final 50-second capture, including keyboard open/close and scrolling,
Flutter reported 1008 frames, 6 above 16.67 ms and none above 33.33 ms; build
p95 11.59 ms, raster p95 4.92 ms. This does not demonstrate a sustained 120 FPS,
and varying model response timing prevents a strict generation A/B comparison.

Manual checks passed on the texture-layer candidate:

- Portrait AI composer meets the keyboard without the reported large gap.
- Landscape with the real IME open shows the unsent draft and send/hide actions.
- Rotation preserves the draft; tapping the editor reopens the keyboard if the
  input method closes during rotation.
- Long press expands a word, immediately shows both handles and the toolbar;
  dragging a handle expands the range without re-locking it.
- The existing scanned PDF renders; tapping its image turns page 36 to 37;
  tapping the previous-page zone restores page 36.

The real summary was generated twice across baseline/candidate testing. Test
drafts were not submitted. Generated chat history is retained on the device.

## Automated verification

```sh
flutter test --no-pub \
  test/widgets/reader_transition_performance_test.dart \
  test/widgets/ai_chat_scroll_test.dart \
  test/widgets/ai_chat_completion_scroll_test.dart \
  test/service/reader_keyboard_test.dart --reporter expanded
```

26 tests passed, including native-reader mount stability, immediate loading,
E Ink/no-motion behavior, single keyboard inset, draft/focus preservation,
stream completion, manual scrolling, and trailing CJK text.

```sh
MODU_JSDOM_ROOT=<external-jsdom-installation> node --test \
  test/android_reader_selection.test.mjs \
  test/reader_smart_selection.test.mjs \
  test/pdf_reading_renderer.test.mjs \
  test/pdf_reading_viewport.test.mjs
```

83 tests passed. The external jsdom installation was only a test dependency;
no application dependency was added.

The first Release attempts used `--no-pub` after profile/widget testing and
retained the generated `integration_test` Android registrant even though Gradle
excluded that dev-only plugin. Rebuild without `--no-pub` when changing build
mode so Flutter regenerates mode-specific platform tooling; no business-code
or dependency change is needed for this generated-file issue.

The signed ARM64 Release package built successfully and was installed with
`adb install -r` (version `1.2.3-preview.2+10089`, no `DEBUGGABLE` flag). Its
SHA-256 is
`8c36b168a0006988c8e936ec6bd309dceabcfb75d8fa5f06dbea8ee14f3f218d`.
This is an in-place local test build, not a new published Preview release.

Static analysis was not a fully clean gate: direct Dart analysis reported only
existing style/import information in the reader files, but its custom_lint
plugin failed to start (`pub is not an AOT snapshot`). A Flutter-analyze retry
also failed inside the SDK's LSP JSON decoder. Compilation and the regression
tests above passed; these analyzer-tool failures are recorded rather than
reported as a clean analysis pass.

## Remaining coverage

- Additional Android vendors, older supported versions, accessibility services,
  and other IMEs still need coverage for platform-view compatibility.
- The original approximately-15-FPS report was not reproduced as a sustained
  condition on this device. Sporadic slow frames remain.
- This change does not alter PDF processing, normal-book pagination, networking,
  or synchronization logic. PDF compatibility was checked, not re-benchmarked
  as a full OCR/cropping performance evaluation.

## Platform references

- [Flutter Android platform views](https://docs.flutter.dev/platform-integration/android/platform-views)
- [initSurfaceAndroidView API and fallback](https://api.flutter.dev/flutter/services/PlatformViewsService/initSurfaceAndroidView.html)

## Follow-up: expand, then turn the cover

The user clarified that Android opening should visibly grow from the shelf
thumbnail and then turn open along the left spine, rather than just enlarge a
cover. The Android route now lasts 720 ms on push / 620 ms on pop:

- The first 55% expands the cover to reader bounds. The rest rotates it open
  with perspective and a painted spine shadow, revealing the stationary reader.
  Following direction feedback, the free/right edge rotates outward toward the
  viewer around the left spine, not inward into the page; a regression assertion
  checks the transform's depth sign.
- Pop uses the reverse sequence: close at reader size, then return to the shelf.
- Cache the cover at thumbnail size to preserve its initial crop, and never
  move or remount the WebView. Reader initialization is still immediate.
- Remove the second Android loading cover, which would otherwise reappear
  behind the turning cover when a chapter is slow to load. Existing failure and
  retry handling remains in place.
- iOS/macOS retain their previous route behavior. Disabled animations and E Ink
  still bypass both the route animation and Hero flight.

The related Flutter suite passes 29 tests after this follow-up, adding checks
for staged bounds, spine rotation, reverse geometry and unchanged iOS behavior.
The earlier profile measurements and APK checksum above describe the preceding
candidate, not this longer animation; they must not be reused as measurements
of this follow-up.

The direction-corrected Release build was installed in place on the same Honor
test device. A short local screen recording confirmed thumbnail expansion,
outward spine rotation, readable chapter content, and reverse return to the
same thumbnail. Device-side temporary recordings were removed after copying
them locally; private library images remain outside the repository. This was a
visual smoke test, not a fresh frame-time benchmark.
