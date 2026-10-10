# Unified query Android preview

## Local package delivery

## Stable 1.2.5 preparation (2026-10-10)

- Version: `1.2.5+10102`. Playback and pause share one shortcut, default P;
  legacy separate bindings migrate without overwriting an explicit empty binding.
- Final full Flutter regression: 2,520 passed, 13 skipped. Reader JavaScript:
  448 passed. Python project/release/Harmony checks: 186 run, 15 skipped,
  no failures. Build/device-specific opt-in checks remain separate from these.
- Updated the Harmony-only reorder API anchor for grouped selection-tool
  settings. Updated two old UI tests for hidden skill controls and scroll visibility.
- Homepage adds separate Chinese/English unified-query showcase images,
  using the real Flutter query layout with original sample definitions and
  generated phone/Mac framing matching the existing dictionary showcase.
  Generation brief: preserve query labels and the four overview cards,
  ivory/foliage background, phone left/Mac right, no real library or disclaimer;
  headlines: “一个窗口，读懂所选” / “One window, a clearer meaning”.
  Built-in image generation used; images saved under
  `docs/images/showcase/cross-platform/unified-query-{zh,en}.png`.

### Default destination

From 2026-10-10, deliver locally requested installers and their SHA-256 files
to `/Users/sobranie/Work/下载` by default, unless the user specifies another
destination. Keep build/staging files in the project; do not install or publish
packages merely because a local build was requested.

## Preview 8 — reader shortcuts and translation UI (2026-10-10)

Delivered Android arm64 `1.2.5-preview.8+10101` and macOS Apple Silicon DMG
to `/Users/sobranie/Work/下载`, with SHA-256 files. Apple metadata is `1.2.5`
/ `10101`. Android release identity, native ABI/JNI and 16 KB alignment passed;
the DMG passed image integrity, mounted payload and ad-hoc signature checks.
Both payloads contain the current reader JavaScript bundle (matching SHA-256).
macOS is not notarized; neither package was installed or publicly released.

- Custom reader shortcuts for desktop/Android hardware keyboards: paging,
  menu and active narration playback/pause/paragraph navigation, multiple
  bindings, modifier capture, conflict checks and confirmed restore defaults.
  Reset affects only shortcut bindings; portable reading backups include them.
- Classical Chinese translation hides reading-skill controls and the misleading
  disabled-skills prompt, preserving translation/follow-ups and Book AI controls.
- Shortcut, settings and narration regression tests passed, including Chinese
  narrow-screen layout and reset cancellation; query/AI regression: 17 passed.
  Physical-keyboard behavior and live AI requests were not tested this build.

## Preview 7 — inline originals and compact spacing (2026-10-10)

Packaged as `1.2.5-preview.7+10100` for Android arm64 and macOS Apple Silicon.
Apple bundle metadata uses `1.2.5` / `10100`; the DMG name identifies Preview 7.
Android release signing, JNI/ABI, 16 KB alignment and SHA-256 checks passed.
The macOS DMG passed image integrity, mounted payload, architecture, ad-hoc
signature and SHA-256 checks. It is not Apple-notarized. These are local
working-tree test packages, not public releases; neither was installed this turn.

- Inspected the installed Honor build's actual `新` query in Overview and the
  dictionary tab. Chinese examples and English translations were separated by
  full blank rows; plain-text extraction adds newlines around block elements.
- Original MDX content now renders directly inside the result card, without a
  route button or duplicate full text. The isolated loopback/CSP/no-bridge
  boundary and user-gesture audio requirement are unchanged. Local dictionary
  scripts now run as the result displays; privacy notices describe this.
- Cards and outer padding are tighter. Text-only results collapse redundant
  blank lines at display time, including existing imports. Original view height
  tracks loaded images/dynamic content, handles shrinking, and stops polling in
  hidden tabs. Very long content scrolls internally after an 8,000 px height cap.
- Theme text color and system text scaling apply to the original body. Loading
  failures show the text definition in place. Old text-only dictionaries still
  need reimporting with resources for original HTML/media, not for compact text.
- Dictionary/query regression suite: 67 passed, 1 skipped. Native rendering is
  mocked for inline height/security/scroll/fallback tests; no new native-WebView
  visual verification performed for this follow-up.

## Preview 6 — toolbar labels and original dictionary media (2026-10-10)

`1.2.5-preview.6+10099`, signed Android arm64 working-tree test build.

- Narration shortcuts now read **回朗读页** and **此页开始**; their actions are
  unchanged. Traditional Chinese labels are updated too.
- Includes the pending selection-tool settings order, shorter **综合** action,
  Book AI query prefill, removal of Free Dictionary API, and media changes below.
- Related regression suite: **122 passed, 1 skipped**. Shorter labels fit one
  row at 320 px; the narrower-screen test still verifies two-row layout.
- Release signing, JNI/ABI, 16 KB alignment and SHA-256 checks passed.
  Installed with `adb install -r` on the Honor test device, preserving app data;
  confirmed version `1.2.5-preview.6+10099` and launched the app. No public release.
  Live narration and native dictionary media playback remain for device testing.

- New MDX imports retain HTML and can include matching MDD resources or loose
  image/audio/CSS/JS files. ZIP retains resource subdirectories. The result
  card's **Original / audio** button opens an independent WebView; Overview
  keeps its lightweight text cards and does not automatically execute scripts.
- Per-window loopback serving uses an opaque CSP sandbox, no app bridge,
  disabled file access, denied permissions/popups/external navigation, and no
  script fetch/network content. Media requires user interaction. Closing the
  view closes the server. Same-origin/storage-dependent scripts may not work.
- Old databases without HTML/resources remain readable. Reimport MDX and its
  resources for original content. StarDict is still text-only.
- Dictionary/query/toolbar suite: 82 passed, 1 skipped before the final original
  button test; targeted media/widget rerun includes that additional UI test.
- Browser check with `scripts/audit_dictionary_media.dart`: synthetic PNG
  decoded, local CSS applied, local JavaScript generated its result, and the
  one-second WAV played to completion after clicking. Storage and script fetch
  (including a valid same-origin URL) were blocked. No real book data was used.
- Included in Preview 6, but not yet tested in Android/iOS/native desktop WebViews. No real
  user-provided MDD bundle was available; compatibility with every commercial
  dictionary or codec is not claimed.

## Preview 5 — compact result typography (2026-10-10)

`1.2.5-preview.5+10098`. Unified query uses the approved design's rounded
tabs, lighter card styling and clearer heading/source hierarchy. Dictionary
results (local and online, embedded and standalone) use 14 px text with 1.4
line height, 18 px headwords and 12 px source labels. System text scaling is
preserved. Reading-page text is unaffected.

Selected local dictionaries without a match show `词典名 · 无条目`, including
when another dictionary returns a result. Failed queries are not mislabeled
as missing entries.

- 50 relevant widget tests passed, including 1.5x text scaling, mobile/desktop
  dictionary scrolling, Chinese/English query layout and AI follow-ups.
- Targeted dictionary/AI static analysis passed.
- Release build, signing/JNI/ABI/16 KB checks and SHA-256 verification passed;
  installed successfully on the Honor test device with data retained. Final
  visual approval of this smaller type remains with the user.
- Prior Preview 3 device lookup, following user approval: Wikipedia results,
  DeepSeek contextual knowledge and Google translation were displayed for
  “孝宗”. Live follow-up sending has not been verified.
- All three supplied MDX files were copied to the Honor test device. The
  21st Century dictionary (323,791 entries) and Collins Chinese-English
  dictionary (86,167 entries) were confirmed imported. The Xinhua sample
  fails with unsupported compression; it is MDX 1.2, not MDX 3.
- Isolated local-file checks found `apple` in the 21st Century dictionary and
  `苹果` in Collins. Not every selected dictionary contains every query term.

## Preview 3 — automatic overview (2026-10-10)

`1.2.5-preview.3+10096`, Android arm64, Android 8+. Supersedes the
Preview 2 behavior documented below:

- Opening Overview starts its enabled dictionary, encyclopedia, translation
  and AI knowledge queries without an extra start button. Dictionary source
  choices are retained; optional online dictionaries still require source opt-in.
- AI defaults to automatic sending. Explicit saved manual-send choices remain
  respected, and the setting is still available. Book AI and web search are not
  automatically started by Overview.
- Native result cards grow with their contents in the outer page scroll view,
  including streamed AI replies and follow-ups. Third-party webpage translation
  remains an embedded browser with its own viewport.
- Chinese and English privacy notices explain automatic requests and costs.
- Verification: **156 tests passed, 1 skipped**; targeted dictionary and AI
  widget analysis clean; signature, JNI/ABI, 16 KB alignment and SHA-256 passed.
- Installed successfully over `1.2.4+10093` on the connected Honor LGE-AN10;
  confirmed `1.2.5-preview.3+10096`, existing library retained, local book opened
  and the default Look up selection action shown.
- Subsequent approved live lookup results are documented above. No public
  release was made.

## Preview 2 baseline

Build: `1.2.5-preview.2+10095`, arm64, Android 8 or later. This is a signed
working-tree test build, not a published release. The stable source version is
unchanged; the preview version is supplied through Flutter build overrides.

## Behavior

- The selection toolbar enables **综合查询 / Look up** by default. Standalone
  dictionary, translation, AI knowledge and search actions remain available in
  toolbar settings but default to disabled. Legacy settings migrate once;
  subsequent explicit toolbar choices are retained.
- Overview includes individually selectable dictionary, encyclopedia,
  translation and AI knowledge sources. Classical Chinese translation, book AI
  and web search have dedicated tabs and are not summarized in Overview.
- Source cards provide settings and expansion into dedicated tabs. Local
  dictionary selection supports one or multiple dictionaries, with source
  attribution. Online dictionaries require opt-in.
- Encyclopedia, translation and web search use explicit start actions. AI
  requests default to manual sending; automatic initial sending is opt-in.
  Knowledge, classical translation and book AI keep separate conversations and
  preserve drafts while switching tabs. Book AI reuses existing chat and reading
  skills. AI prompt/context/manual-send setting changes apply to the next query.
- Query preferences remain device-local and are excluded from settings backup.

## Verification

- Related Flutter regression suite: **153 passed, 1 skipped**. Covers toolbar
  migration, Chinese/English small-screen layout, keyboard clearance, separate
  real AI widget drafts, dictionary sources, encyclopedia request filtering and
  existing translation popup behavior. AI/network responses are mocked; this
  does not establish live provider availability.
- Targeted analysis: `lib/models` and `lib/widgets/dictionary`, no issues.
- Release APK build completed; package name/version verified. Packaging checks
  passed for release signing identity, archive integrity, JNI/ABI and 16 KB
  native alignment. SHA-256 sidecar verification passed.
- No installation or hardware testing performed for this preview. Existing
  unrelated working-tree changes are included and were not reverted.

## Manual checks

1. Select a word in a book and open Look up. Confirm legacy lookup buttons can
   still be enabled in toolbar settings.
2. Change Overview sources, close/reopen the query and verify saved choices.
3. Select one/multiple local dictionaries and check source footers. Enable an
   online source only when testing network lookup.
4. Test encyclopedia and translation start actions, errors and retry.
5. Send AI knowledge and a follow-up using a configured provider. Switch to
   classical translation and book AI; verify conversation/draft isolation.
6. Test book AI skills on indexed and unindexed books, keyboard opening,
   portrait/landscape layout and returning to the reader.
