# macOS AI panel keyboard regression

Local ARM64 build: 1.0.2+10008. No public release was created.

## Causes and fixes

- The production `generateUrl()` initial style omitted `desktopPageInput`.
  Setting it only in `EpubPlayer.changeStyle()` left freshly opened books with
  disabled DOM key interception. Initial URL and legacy initialization now carry
  platform input flags, including the existing mobile touch/image settings.
- Clicking book content after editing in the Flutter AI panel did not return
  keyboard focus. The completed, unselected book click callback now requests
  both reader Flutter focus and macOS native first-responder restoration.
  It does not require closing the AI panel or intercept input-field editing.

## Verification

- Added an actual `generateUrl()` regression test: before the fix,
  `desktopPageInput` was null (expected true on macOS); after the fix it passes.
- Flutter: 457 passed, 4 skipped. Reader JS: 66 passed.
- Targeted analysis: no errors/warnings, four pre-existing info-level lints.
- ARM64 main executable/App.framework, packaged reader sources, ad-hoc signature,
  DMG mount validation and SHA-256 checks passed.
- Installed `/Applications/Modu.app` and exercised the native window, not a
  browser mock. AI panel stayed open. Typing `abc`, Left, then `X` produced
  `abXc`, without paging. The test draft was cleared without sending it.
- After clicking back into the reader, focus left the AI editor. Right advanced
  13/24 to 14/24, Left returned to 13/24. Down and Up repeated that sequence.

An existing automatically restored full-text translation mode also displayed
HTTP 429 and a handshake error during this check. Translation service errors
are separate from keyboard routing and were not changed in this task. No AI
chat message was submitted. The real book was paged during this test, so normal
reading progress/time updates may occur.

Only macOS ARM64 was installed and exercised here. Android, Windows and Linux
were not built or tested on devices in this task. No old installed-app backup
was retained, as requested; application data directories were not replaced.
