# Sync and reader regression checks

Source changes only; no new native package was built, installed or published.

## Changes

- Format local database and last-sync timestamps in the device's local timezone,
  leaving stored instants and synchronization comparisons unchanged.
- Await WebDAV configuration dialog dismissal and rebuild the settings page.
- Open backup management as a Navigator dialog, matching its Cancel operation.
- Android selection toolbar observes stable selection changes instead of requiring
  pointer cancellation or a selection-handle drag. Duplicate events are ignored;
  collapsed selections and quick marking do not open the toolbar.
- Lay out chapter iframes while hidden, wait for fonts, then re-layout and reveal.
  An 8-second bound prevents a failed font resource from leaving the reader blank.
- Default next/previous in scrolled mode moves 80% of the current viewport.
  Explicit distances and free scrolling are not changed.

## Evidence

- Flutter: 460 passed, 4 skipped. New widget tests cover UTC/local timestamps,
  WebDAV address refresh immediately after Save, and backup Cancel retaining the
  underlying settings page.
- Reader JavaScript: 71 passed. New tests include single-character/word Android
  selections without pointercancel, deduplication, collapsed selection/quick-mark
  guards, actual chapter-loader font gating, and actual 80% scrolled navigation.
- Targeted Dart analysis: no issues. Legacy webpack bundle rebuilt successfully
  with its three existing target/top-level-await warnings.
- Independent Chromium fixture uses the production paginator and a local test
  font delayed 1.5 seconds. Observed `visibility=hidden` / `fontStatus=loading`,
  followed by visible / loaded; the next chapter also reached loaded state.
- Desktop viewport: 1388px readable height, next offset 1110.5px (80%, within
  browser subpixel rounding). Previous returns to zero.
- 390x844 small viewport: 804px readable height, next offset 643px (80%, within
  browser rounding), leaving approximately 161px overlap.

Browser fixtures are not Android WebView or native-device validation. Android
long-press behavior, native macOS/Windows UI and the user's particular font still
need verification with newly built packages. No personal book or credentials
were used in these tests; mock configuration and local synthetic chapters were
used. The installed 1.0.2+10008 app was not replaced during this task.
