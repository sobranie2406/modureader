# Windows reader keyboard regression

## Report and code findings

Reported against Windows 1.0.6: arrows and the enabled Ctrl+[ / Ctrl+]
setting do not turn pages. The released Flutter handler requires the reader
wrapper to have primary focus, but the Windows texture WebView uses a child
Focus. Its bubbled keys were consequently ignored. Independently, the DOM
handler rejects all Ctrl keys and never receives the Ctrl-brackets preference.

## Changes

- Accept page keys from the Windows reader WebView focus scope without stealing
  primary focus. Exclude Flutter text editors and controls outside that scope.
- Route the desktop Flutter fallback through the DOM selection/editor guards.
- Supply the Ctrl-brackets preference on initial load and live style updates.
- Enable the matching DOM shortcuts only when the preference is enabled.
- Keep modified editing keys and selections out of page navigation; do not
  reinterpret plain Escape as Ctrl+[.

## Local verification (2026-09-15)

- Flutter suite: 669 passed, 5 skipped. Includes child-focus key delivery,
  focus restoration after an editor, modifier mapping and preference toggling.
- Reader JavaScript suite: 135 passed. Includes DOM/fallback guards and wiring.
- Python checks: 43 passed.
- Webpack reader bundle rebuilt successfully, with 3 existing warnings.
- Real Chromium, synthetic `continuous-reader.html?long&keys` fixture:
  - Right: scroll 3770 → 4282; Left: 4282 → 3770 (one 80% step of 512 px).
  - Ctrl+] disabled: unchanged at 3770.
  - After enabling: Ctrl+] → 4282; Ctrl+[ → 3770.
  - Editor focused: arrows and Ctrl+] leave reader at 3770.
  - Book text selected: Ctrl+] leaves reader at 3770.

The fixture uses the production renderer and desktop DOM input module, not a
Windows WebView2 host. Windows native key routing remains to be confirmed on a
Windows machine. No Windows installer was produced or released in this change.
Flutter's LSP analyzer failed while reading its initialization message locally;
this is not recorded as a passing static analysis check.
