# Modu 1.3.1 settings and features

English · [简体中文](SETTINGS_zh.md) · [Home](../README_EN.md) · [Documentation](README.md)

For stable **1.3.1+10152**, updated 2026-10-22. Phones usually open settings one page at a time; wide desktop windows use a two-column layout. Some capabilities depend on the operating system, reader engine and selected service.

The current entry points below include [1.3.1](https://github.com/sobranie2406/modureader/tree/v1.3.1). See the [detailed feature guide](FEATURES.md) for workflows, defaults and boundaries. Source and automated checks are distinct from device acceptance on every platform.

### 1.3.4 additions

- Language and Classical Chinese translation share Baidu/Microsoft credentials. Encrypted settings sync carries service configuration, credentials and related AI service selection, but not languages, direction or translation appearance.
- Baidu and Microsoft configuration pages show separate usage estimates and editable reference allowances. Only successful Modu request characters count, grouped by UTC calendar month across updated devices with encrypted settings sync enabled; repeated sync does not count twice. These are not official bills or remaining balances, and server-billed cancelled/timed-out requests may be missing. The allowance is not a spending cap. Microsoft's two keys are counted separately; other engines are excluded.
- Selecting Popup AI display reveals an optional Move and resize popups switch, off by default. Enabled selection-tool popups can move by their top and resize from their sides, bottom and corners; reopening resets position and size.
- Last-read ordering uses synchronized reading timestamps. Folder layout respects cover width and available space.

## Settings entry points

### Reader toolbar and Classical Chinese translation

- **Settings → Translation** has separate **Language translation** and **Classical Chinese translation** entries, using the same grouped cards and navigation rows as other settings. Both have independent **Translation appearance** controls for the output font (follow original, system/generic or imported TTF/OTF), size (follow original or a 0.5–3.0 scale in 0.1 steps), bold and italic, with an immediate preview. **Font colour** below the font row uses the theme-style picker, hex input and presets including teal and blue. The two sets of preferences save separately and never change each other. Existing and future output updates in ordinary and PDF/OCR reflow reading, without modifying original text styles or making another translation request. Appearance is included in translation-settings backups; imported font files must also be available on the destination device.

- **Settings → Reading → Reader top toolbar** controls visibility and drag ordering. Enabled actions available in the current reading mode appear in order within 40% of the reading area's usable width, including the three-dot More button; remaining actions go in More. Button touch targets retain their normal size, and the count adapts to rotation and window resizing. Back remains separate. Hidden actions do not appear in More. Ordinary books and PDF/OCR reflow share this configuration.
- **Settings → Translation → Classical Chinese translation** offers AI, Baidu and Microsoft Translator, with Classical → Modern Chinese and Modern → Classical Chinese directions. Ordinary translation preferences remain separate. AI uses a model configured in AI settings.
- **Baidu:** enable [General Text Translation](https://fanyi-api.baidu.com/doc_bd/21), enter its APP ID and secret, then choose **Save configuration**. This is not a Baidu AI Cloud API key. The official HTTPS POST uses `MD5(appid + raw UTF-8 q + salt + secret)` signing and `wyw ↔ zh` codes. Requests are serialized at the standard-tier rate; long paragraphs are split without dropping characters.
- **Microsoft:** create an Azure Translator resource, copy Key 1 or Key 2 and its region from **Keys and Endpoint**, then save. Regional/multi-service resources require the matching region (for example `eastasia`); global single-service resources may leave it blank or use `global`. The official global `/translate?api-version=3.0` endpoint uses `Ocp-Apim-Subscription-Key`, the region header when applicable, and `lzh ↔ zh-Hans`. See [authentication documentation](https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/authentication). Private-network endpoints are outside this configuration's scope.
- Both official APIs require your own credentials; quotas and excess charges depend on your account tier. Keys are obscured and excluded from non-sensitive exports by default. Saving settings never sends text.
- Open the Classical Chinese icon in the reader and explicitly start translation. Choose translation only or original + translation. Only visible paragraphs are requested, with further paragraphs loaded as you scroll; untranslated portions retain the original. Stop cancels pending requests. Changing engines/directions invalidates cached translations on restart. Closing a book never resumes translation automatically. Turning a source page stops reflow translation; OCR caches, edits and notes are unchanged. Google Cloud Translation does not list a dedicated Classical Chinese language, so it is not offered for this feature.

Unreleased scrollbars: the bookshelf, Reading History, settings, remote library, notes, Lookup and scrollable dialogs use translucent draggable thumbs. They appear while scrolling and hide after about 1.2 seconds idle, on the right for vertical scrolling. Horizontal scrolling remains available without a scrollbar. Fitting content has no visible thumb. E-Ink with animations disabled shows/hides without fading. Embedded web pages and continuous reading also have scrollbars; paginated reading and single-line fields do not.

Unreleased autosave changes: ordinary switches, selections and ordering persist immediately; PDF/OCR style sliders save on release. Valid CSS edits save automatically, while invalid edits preserve the last valid configuration. Connection credentials, new templates and text requiring complete validation retain Save; deletion, replacement imports and resets retain confirmation. Speech buffering preferences are remembered immediately but apply after stopping and restarting narration. See the [settings persistence audit](development/settings-autosave-audit.md).

Open **Settings** from the home navigation. The app language can follow the system or be selected manually. Built-in prompts have localized defaults; prompts you have edited are not automatically translated or overwritten.

| Category | Purpose |
| --- | --- |
| Appearance | Theme, colors, OLED / E-Ink, language, covers, navigation and optional WeRead connection |
| Reading | Fonts, layout, page turning and long-press word/paragraph selection |
| Reading → CSS settings | Named profiles, visual controls, custom CSS and regex highlights |
| Selection toolbar | Action switches, sorting, colors, AI selection templates, selection search and custom dictionaries |
| AI Settings | Providers, model parameters, display, tool permissions and AI Reading Skills |
| Offline local model settings | Vector/embedding and OCR models, sources, download/import, selection and deletion |
| Narrate | Engine, voice, speed and editable narration-style templates |
| Sync and backup | WebDAV / S3, automatic and encrypted credential sync, database backup and global settings files/links |
| Remote library settings | Separate WebDAV browsing and book downloads |
| Translation | Engine, target language, AI and DeepL / DeepLX |
| Experimental features | Plugins are off by default; warning and confirmation required; only project-reviewed packages accepted |
| Advanced | Storage, cache, TXT chapter splitting, logs and network |
| About Modu | Bug reports and feature requests, project links, community, licenses and app updates |

WeRead: enable the connection under Appearance and enter your own official API Key. In book details, search and confirm the edition before linking. Its metadata/ratings/reviews stay separate from personal data; public cached data syncs with downloaded books, while keys require explicit sensitive-settings opt-in. See [WeRead](WEREAD.md).

Menus use page-coloured rounded groups with content-driven heights and matching light/dark themes; E-Ink retains its flat monochrome style. New installations go directly to the bookshelf. The reader moon button changes both reading mode and app theme.

Appearance → Display → Interface layout offers Auto / Wide / Narrow and remembers your choice. Auto preserves each screen's existing available-width threshold of more than 600 logical pixels. Manual choices apply to navigation, settings, history, notes and book details, without changing reader column settings.

The default light theme uses paper white and jade green; format and indexing badges retain their distinct colours. Appearance → Theme colour → Restore default resets only the app accent after confirmation. The outlined Background / Text colour controls in reader styles each offer a confirmed reset of that colour without overwriting the other.

Text/OCR reflow provides page-local narration and current-page translation (corrected text first), translation-only/bilingual views and the shared selection toolbar. Original PDF/scanned pages do not narrate. Text → Export saved book text offers TXT or Markdown in original page order.

### First-use defaults

These come from [preferences](../lib/config/shared_preference_provider.dart) when the setting has never been saved. Upgrades, imports and independent provider configurations can change them.

| Setting | Default |
| --- | --- |
| E-Ink, tap-only turns, long-press paragraph selection | Off |
| Bookshelf layout | Thumbnails; switch to a cover-free list from the shelf toolbar |
| E-Ink → Disable all animations | On; only adjustable and effective in E-Ink mode |
| Scroll page amount | 80%; range 80%–100% |
| Selection-search / web-translation zoom | 100%; range 50%–200% |
| Automatic selection translation | Off |
| Reading skill entries | Visible |
| Edit templates before sending | Off; tapping sends |
| Vector model | Enabled/local, BGE Small ZH v1.5; download still required |
| Automatic vectorization on import | Off |
| Cloud connection | Off; configuration required |
| Automatic sync preference | On, only works after enabling cloud sync |
| Timed reading sync | Off; default interval 5 minutes |
| Service/key sync and credentials in backup | Off |

The bookshelf toolbar switches between thumbnails and a text-only list and remembers the selection. List rows keep titles, authors, reading progress, format/index badges and sync status; folder rows show their names and book counts. Long-press still enters selection mode for folder organization and batch deletion, with each book's overflow menu on the right.

Long-press a book and drag it onto another book to name and create a folder, or onto an existing folder to move it there. Dragging a checked book carries all checked books, with a count badge; dragging an unchecked book moves only that book. Inside a folder, drop books outside its frame or on the **Move to shelf** drop area to move them out. Batch moves are atomic, failed moves keep the selection, and cancelling folder creation does not move books.

## Checking and installing updates

Open **Settings → About Modu → App updates**. Checking and downloading share one source selector, initially GitHub. If a check falls back to Gitee because GitHub is temporarily unavailable, the download source changes with it. Check again after manually changing sources; downloads do not mix sources midway. Finding an update does not automatically download or install it, and a failed check does not interrupt reading.

- **Android:** in-app downloads verify size and SHA-256, then package name, signature and version before opening the system installer. Installation permission is requested only when needed; installation is not silent.
- **Windows / Linux:** verified in-app downloads open the EXE / DEB for normal installation. Windows needs WebView2; Linux packages target Debian 13.
- **macOS:** the default browser downloads the DMG. Quit Modu and drag Modu.app onto Applications to replace it. Modu cannot monitor browser completion or claim to have verified that file; compare it with the release's SHA-256 yourself. The disk image contains only the app and Applications shortcut. It is not Apple-notarized.
- **iOS:** the IPA needs your own valid signing and cannot install itself from the app. Store builds should update through their original store.

Back up and upgrade in place; do not uninstall or clear data first. Opening an installer does not mean installation has finished. See [installation and release instructions](RELEASING.md) for platform requirements.

## Reading ordinary books

Unreleased iOS addition: Bookshelf → **+ → Add files/folder in place (no copy)** reads authorized EPUB/PDF/MOBI/AZW3/FB2 originals without importing full copies. First select a file or folder in the system Files picker. Keep files downloaded and available; deleting a shelf entry preserves the external original. Access authorization is device-local and originals are excluded from automatic upload and backup ZIPs, so another device needs reselection or ordinary import. Covers/indexes still use storage. TXT/Markdown/UMD require normal conversion-based import. Existing copied books are not automatically migrated. Physical iOS verification is pending.

Supported formats include EPUB, PDF, MOBI, AZW3, FB2, TXT, Markdown and text UMD. TXT / Markdown / UMD are converted to EPUB on import for reading and synchronization. UMD retains chapters, metadata and supported covers; image/comic UMD is unsupported. The library supports folders, tags, pinning and moving selected books into folders. Download remote books before reading offline or indexing them.

Import multiple files or choose a folder and select its supported books, including subfolders. Desktop drag-and-drop accepts folders on the library or reading screen. Source files are preserved. Dropped books import without repeated confirmation/result dialogs; duplicates are skipped and one failed file does not cancel the rest. Supported system file associations can hand a book to Modu; availability depends on the platform and file provider. Cover badges show the original TXT / MD / UMD format when recognized, otherwise the stored format, and a scanned-book label where applicable; manual classification takes priority over automatic detection.

Cover-opening and return transitions are shared across platforms and follow the disabled-motion preferences; iOS retains edge-swipe return. Dragging iOS text-selection handles updates the selection menu. MOBI note popups require a reliably matching legacy layout; AZW3 note types and explicit image-note text are recognized. Matched notes are hidden from the body and remain available in popups; ambiguous MOBI content stays visible.

The floating home navigation bar is translucent, with space at the end of scrollable content so the last item remains accessible. **Appearance → E-Ink** uses monochrome labels and disables app transitions, animated page turning and decorative motion by default. Its **Disable all animations** switch is greyed out outside E-Ink mode; turn it off to restore saved animation settings while keeping the monochrome palette and hardware refresh settings. The choice is remembered across restarts and mode changes, without overwriting open-book or page-turn preferences. Appearance provides separate **Show book format labels** and **Show indexed labels** switches, both enabled by default and remembered independently. Indexed labels match format-label font size and padding in thumbnail and list layouts. Hiding indexed labels does not delete indexes or hide indexing progress/failure notices; scanned labels remain independent. Long-press a cover (or right-click on desktop) to enter selection mode and reveal its lower-right overflow menu, on the shelf and inside folders.

Tap the text to open the bottom panel. Drag the progress slider to preview a chapter title, or use previous chapter, previous page, next page and next chapter. **Chapter progress** means chapter number / chapter count; **progress within the chapter** means current page / pages in that chapter.

**Style** includes font size, **font thickness 0.5–2.0 in 0.1 steps**, simulated bold, line spacing, paragraph spacing, fonts and backgrounds. Actual weight changes depend on the font; try simulated bold with fixed-weight fonts. More reading settings contain side margins and header/footer options. App themes and book backgrounds are separate.

- **Settings → Reading → Font management** groups **Download Fonts**, **Import fonts** and **Manage installed fonts**, in that order. Import multiple TTF / OTF files or a whole folder, including subfolders. Only single-file imports apply immediately; batch and folder imports preserve the selected font. Installed names and reader font selectors preview the corresponding face, with system fallback for missing glyphs. Online downloads need a connection.
- **Settings → Reading → Font management → Manage installed fonts** removes downloaded/imported app copies after confirmation, keeping the original imported files. System and bundled fonts are protected. Matching reader, English override, translation, PDF/OCR reflow and excerpt-sharing font selections fall back to defaults; other appearance settings remain unchanged. Finish or cancel active/paused font downloads before removing fonts.
- Scroll-page movement can be set to 80%–100% of the viewport. Free scrolling is independent of this setting.
- **Auto-align scrolling** is enabled by default. It keeps the existing top-edge alignment when scrolling up and bottom-edge alignment when scrolling down. Turn it off to stop freely without forced line snapping. The switch is available beside the scroll-page percentage, applies immediately and is included in settings backup; it does not change the page-turn mode or original-page PDF behavior.
- Unreleased: **Scroll continuously across chapters** is on by default. Turn it off in the reading style panel or Reading settings to scroll one chapter at a time; use page turning at the chapter end or the contents to move to another chapter. Changes apply and save immediately. Original-page PDF scrolling is unchanged.
- Long press can match a word or expand to a paragraph. Selection handles remain available to adjust the range after the initial match.
- Android and iOS use one pair of touch handles. In paginated/swipe reading, drag an endpoint to the top/bottom page edge (left/right for vertical text) and hold for about 0.75 seconds. It flips once and freezes at the new page boundary; release and grab the visible handle again to continue selecting, without moving the other endpoint. In scrolling mode, hold near the edge for gradual auto-scroll and release to stop. Selection stays within one chapter; original-page PDF and desktop mouse selection retain their own interaction.
- Unreleased: Horizontal paginated reading also accepts left/right edge dwell, with targets inside the screen safe area rather than the system gesture region. Single-column pages do not require hitting the exact final glyph; multi-column spreads still require reaching the selection boundary of the entire visible spread.
- Mobile tap-only paging does not disable selection or continuous scrolling. Desktop arrow keys and eligible drags turn pages; selecting or typing is not treated as paging.
- Reading brightness follows the system by default. Manual 0–100 dimming applies only to book content in dark mode, including PDF and reflow. Menus, popups, floating controls and screens outside reading retain their brightness; light mode disables dimming. The level is saved locally and restored when dark mode returns.

## PDF and scanned-image books

PDF uses dedicated original-page controls. EPUB, MOBI, AZW3 and FB2 are classified during import by sampling up to five body sections, for both local and remote imports. Opening a book reads its saved classification rather than waiting for sampling. The bookshelf menu can manually mark a book as scanned or restore ordinary reading.

**Ordinary text books keep their existing menus and styling; PDF-specific settings do not affect them.** Scanned books disable ordinary illustration tap-to-enlarge / long-press actions.

The dedicated panel offers fit-page / fit-width, zoom, rotation, panning, continuous scrolling, crop and panels, and reading order. Original and cropped images adapt to the window and settings; layout is saved per book.

The brightness panel's moon button inverts PDF page colours and turns the surrounding background black; page illustrations are inverted too. OCR text selections and annotation colours are preserved. Turn it off to restore the original colours. Original-page PDF text/OCR selections support highlights, underlines and annotations, aligned with crop, zoom and rotation. Continuous-scroll momentum follows disabled-animation and E-Ink settings.

- Automatic cropping detects content bounds per page while retaining useful text, page numbers and footnotes. Use manual crop/panels for difficult layouts.
- Image enhancement offers ink color, contrast, darkening, whitening, sharpening and scanned watermark fading. Adjust intensity, compare the original or reset. Conservative watermark fading cannot remove every watermark.
- PDF reading prepares nearby cropped/enhanced pages automatically. It starts one reading panel ahead, increasing to two after fast processing samples when device hints allow. Continuous mode also retains nearby content for reverse scrolling; full-panel backing images are capped at about 8MP and the window at seven frames, additionally bounded by a decoded-pixel budget based on device hints. Visible and selected content is retained. Zoomed details are refined separately. This is an in-memory optimization, not an offline conversion of the whole book; rapid jumps or expensive pages can still require waiting.
- Processing does not rewrite the source book. Controls follow the app theme; manual / every-N-pages refresh appears only in E-Ink mode and requires a supported device interface.
- Text reflow uses the page's text layer; OCR reflow recognizes image text. Both process the current page, or the whole cropped page when cropping is enabled, and display the result directly in the reader.
- Reflow and extraction results reuse ebook menus and quick styles, including fonts, spacing, colors and backgrounds. Styles save for this book; menus fit their content up to 80% of screen height without resizing the text viewport. The header returns to the source page or changes reflow mode; PDF page arrows automatically reflow adjacent pages using the existing lookahead/cache. Region, whole-page and batch recognition and AI drafts remain available. Text/OCR reflow narrates only the current page, stops on page change or exit, and shares speech providers without changing ordinary ebook narration.
- Paragraphs and first-line indents follow detected source geometry, not every printed line. New reflow notes retain the original page and image regions: **View original** opens these saved locations. Re-recognition preserves existing notes and text revisions; legacy notes are kept without guessed coordinates.
- E-Ink locks both the app and reader to pure white backgrounds and black text. Dark mode is unavailable while E-Ink is on; turning it off restores saved palettes and backgrounds.
- Reflowed text supports styling, selection, annotations and AI tools. The PDF panel's gear opens the relevant text-style controls.
- Only **Extract** asks for a region. Recognition fills an editable AI draft; review and send it yourself. It does not automatically upload the book.

### OCR models

Unreleased: each OCR card has **Offline import**, on desktop and mobile. Select the complete detection and recognition ONNX files together, plus the matching `rec.yml` (upstream `inference.yml`) dictionary configuration for V6 (upstream names or `det.onnx` / `rec.onnx`). Only the exact catalogue version passes the pinned size/SHA-256 checks. Import does not select a different model; use **Use** afterward if needed. No network is accessed during import. ZIPs and download fragments are not accepted.

Open **Settings → OCR model**. **PP-OCRv6 Small** is the default recommendation; **V6 Medium** is the higher-accuracy option. V5 mobile, V4 and V3 remain available. An explicitly saved model selection is preserved. Weights are downloaded on demand, not bundled. Choose upstream or the Gitee mirror: V6 / v4 / v3 use Hugging Face upstream, while v5 uses ModelScope.

Cards support download-and-use, selection, verification, cancellation and deletion. Files must pass size and SHA-256 checks before use. Deleting a downloaded model does not delete books. Recognition runs locally and needs no OCR API key. Model choice and source settings can be backed up; model files are not transferred in global settings backups. Review small text, complex columns and poor-quality scans manually.

Desktop and Android hardware keyboards can configure paging, menu, play/pause and previous/next paragraph under **Reading → Reader shortcuts**, below page-turn mode and above scrolling. Each action supports multiple bindings; conflicts are rejected and Restore defaults asks for confirmation. Play/pause shares P by default. Input fields, selection and dialogs are guarded; OS-reserved keys may not reach the app. Playback controls operate an active narration session.

Unzoomed single-page PDFs support single-finger swipe paging; enlarged pages use drag-to-pan. Pinch zoom and text selection do not turn pages. Reflow supports the configured tap-to-turn regions.

## CSS and selection tools

In-reader settings use Reading / Style / CSS / Other tabs, with CSS templates in their own tab. Style, detailed settings and PDF reading settings follow the Lookup popup sizing rules and scroll within the panel. Selection-toolbar and keyboard-shortcut configuration remain available from Settings.

**Settings → Reading → CSS settings** provides 32 named slots and 14 editable presets. Enable the master switch and desired profiles; multiple profiles can apply together. Each book can follow the default combination or select its own. Profile contents are shared globally, so editing one can affect other books using it.

CSS changes layout; regex highlights style matching text with colors, backgrounds and underlines without rewriting text or annotation positions. Import trusted CSS / JSON only: remote resource URLs can make network requests. New, copied and imported profiles start disabled; imports fill empty slots without silently overwriting profiles.

**Selection toolbar** lets you toggle and drag-sort built-in tools and AI commands, and edit annotation colors, names, icons and prompts. Common AI presets start disabled, including AI Knowledge and Classical Chinese translation. Manage selection templates here, separately from AI Reading Skills; both use the same reader AI dialog.

Each selection command can use **text with context** (default) or **selected text only**, and can opt into online search. Explicit scope choices are preserved. AI Knowledge uses the current model's knowledge first. To check further, choose **Online search** below the answer, before Regenerate and Copy. Wiktionary, Wikipedia and Baidu Baike results are summarized with sources by the same model in the same conversation. No extra search API key is required.

Text-filter profiles live alongside CSS profiles and can hide matching text or its entire paragraph; narration skips filtered content. Native PDF/OCR reflow supports applicable font size, weight, line/letter spacing, colors and alignment, not arbitrary HTML selectors or web layouts.

## Plugins

Unreleased: **Settings → Experimental features → Plugins** is off by default. Enabling requires reading the warning and confirming; cancelling leaves it off. Consent is local to this device and is never exported or restored from settings backups. Once enabled, **Manage plugins** installs a local `.moduplugin` package (a zip under 5 MB). At this stage a package is declarative data only and contains no executable code. Supported contributions are AI prompt templates and selection-toolbar actions; each package must declare an SPDX license, its capabilities and a semantic version. The details page shows the package id, version, author, license, SHA-256, declared permissions and every active contribution.

Only releases reviewed by the [Modu project](https://github.com/sobranie2406/modureader) and pinned in the app's built-in catalog are accepted. Package ID, version, complete file list and every file's SHA-256 must match; forged author URLs, modified packages and extra files do not qualify. Verification runs during installation, startup reconciliation and re-enabling. There is no custom source, trust override or script execution switch. New catalog entries require source review and an app update. See [plugin trust policy](development/plugin-trust.md). This reduces risk; it does not guarantee that AI responses are safe or accurate.

Turning the experimental switch off disables plugins and removes their unedited contributions, but keeps package files, configuration and edited ordinary entries. Turning it back on requires confirmation again and does not automatically re-enable individual plugins. AI actions only send reading context when you invoke them, through your configured AI service.

Disabling a plugin removes the prompts and toolbar actions it added. Uninstalling also deletes its package files. Entries whose prompt content you edited are kept as ordinary prompts or custom toolbar commands, including during same-ID upgrades. Plugin settings accept text, numbers, toggles, choices and help text; they cannot store passwords or API keys. These are explicitly labelled reserved values: they are saved and backed up but do not alter the current prompts. Partially deleted prompt packs are not automatically filled back in on restart, preserving intentional user deletions.

Global settings backup includes installed-plugin records and plugin settings, but not package files. On another device these records stay disabled while the experimental switch is off. After local confirmation, absent packages show as **Missing** and require an approved package to be installed; saved configuration is retained. Plugin toolbar actions use the same 24 custom-action slots as your own commands.

## AI configuration, skills and conversations

Add an endpoint, model and API key in **Settings → AI Settings → Provider configuration**, then test the connection. Each configuration keeps its own temperature, maximum output tokens, history depth and reasoning settings. Supported parameters and costs depend on the provider; RPM controls request pacing, not provider limits.

**AI tools** controls the app tools a model may call. A reading-skill prompt does not automatically supply the entire book: available material depends on the selection, accessible chapters and retrieved passages.

**AI Reading Skills** shows skill shortcuts by default. Built-in and custom skills can be enabled, sorted and edited together. Restore their default order or restore deleted built-in skills. **Fill the input with the skill template first** is off by default: off sends immediately, while on fills the draft so you can add a chapter range or instructions before sending. The switch is available in settings and the dialog. Each AI screen and selection AI action remembers its own switch on this device, including the separate AI tabs in Lookup. Changing one does not change the others; these switches are excluded from sync and settings import/export. Upgrades retain prior defaults until a screen's switch is changed.

A skill can start a new task conversation. Follow-up questions typed into the current or a restored historical conversation continue with its permitted history. The history entry restores the conversation, not only its question. Completed replies return to their beginning for reading. AI font size is independent; mind maps support full screen, zoom, pan, branch collapse and PNG / SVG / Markdown / FreeMind / JSON export.

AI Knowledge never calls local book/library tools, including follow-ups and retries. Book AI retains the original book or bounded skill source. AI Knowledge, AI translation, Classical Chinese translation and the other AI panels have their own settings, new-conversation, history and display menus. Font size and edit-before-send are remembered locally per screen. Histories are partitioned by built-in skill, custom skill and home task; choose a skill in the history menu to view or clear only that skill. Recognizable older histories are classified without deleting records; unclassified legacy conversations remain in their original general history.

Backups store your changes to built-in prompts and your custom templates, not redundant copies of unchanged defaults. Restoring a default replaces its customization. Remote AI receives the actual request text and supplied context; see [Privacy](../PRIVACY.md).

## Vector indexing and semantic retrieval

Unreleased: local model cards offer **Offline import**. Copy the complete `model_quantized.onnx` and `tokenizer.json` from the same supported model/version on a connected device, and select both files together on the offline device. The importer verifies against the app's own manifest; arbitrary ONNX models or user-supplied manifests are not accepted. Existing model selection and indexes are retained. Gitee fragments must first be assembled into complete files.

Open **Settings → Vector Model / Embedding Models**. Embedding models retrieve passages; chat models answer questions. They are configured separately.

Local models include Chinese BGE (default), English BGE, MiniLM and multilingual E5. Download from Hugging Face or Gitee with size and SHA-256 verification. Missing models are not silently downloaded. A remote embeddings API receives indexed passages and queries and may charge for them.

Index / re-index from a book's menu, or enable automatic indexing after import (off by default). Unavailable models or books without local files cannot be queued. If both model and source book are unchanged, an upgrade or replacement package alone should not invalidate a valid index. Changing the model or content requires re-indexing.

**Stop vectorization**, in the library task bar and model settings, disables automatic indexing and cancels active and queued tasks while retaining completed indexes, books and models. Turning off automatic indexing alone cancels automatic tasks without preventing later manual indexing.

**Vector indexes stay local and do not participate in WebDAV / S3 library sync.** Build an index on each device as needed. Local embeddings do not make a remote chat answer offline: retrieved passages supplied to remote AI still leave the device.

## Dictionaries, search and translation

**Lookup** is enabled by default in the selection toolbar. Choose dictionaries, encyclopedia, translation and AI Knowledge independently for automatic overview queries. Book AI, Classical Chinese translation and Web search use separate tabs; Book AI prefills selected text without automatically sending. AI permits context selection, editing before sending and follow-ups. Classical Chinese translation hides reading-skill controls. Standalone dictionary/translation/AI tools remain available, disabled by default. Online providers receive the query or chosen context and may charge for requests.

In Lookup → Lookup settings, drag the four sections and Save to reorder their tabs and overview results on this device. Reordering turns off query-text ordering; enable it again for smart overview results, or turn it off to return to your saved custom order. Disabled sources retain their positions. These settings are excluded from sync and settings backups.

Choose one or several local dictionaries and optional Chinese/English Wiktionary in dictionary sources. Results identify their source, license/link for online entries, and unmatched selected dictionaries.

Import MDX 1/2 or StarDict companion files / ZIP that you are entitled to use. Lookup is offline and uses actual headwords; edit the query when necessary. Two-way lookup depends on the dictionary containing entries in both languages. There is no reverse search through Chinese definitions. New MDX imports can retain original HTML with MDD/local images, audio, CSS and scripts displayed inline in an isolated view without app-bridge or external network access. Audio requires user interaction. Reimport old text-only dictionaries with resources to enable originals; StarDict remains text-only. Dictionaries are not included in library sync or current backups.

Selection search opens results in the in-app browser. Choose a built-in engine or a custom URL containing {query}; results support zoom. The search site receives the query text.

Inline full-text translation supports Google, AI, Baidu Translation API, Microsoft Translator and DeepL / DeepLX. Original + translation or translation-only paragraphs appear on the book page and follow the reading position. This is not a one-click export of an entire translated book. AI translation uses your configured model; DeepL / DeepLX requires the appropriate endpoint configuration.

The selection-translation window can switch providers and also supports Baidu / Youdao webpages. Webpage translation differs from inline paragraph translation; it offers 50%–200% zoom and vertical scrolling. Scans need usable text or OCR/reflow first. Online services receive the text to translate; review their output.

## Narration and style templates

**Settings → Narrate** offers system voices, Edge TTS, DashScope, Xiaomi MiMo and OpenAI-compatible speech. Configure the required endpoint/key, save, fetch voices, select one and test it. System TTS is connected for Android, iOS, macOS and Windows; Linux / OpenHarmony have no system TTS backend and require explicitly choosing an online service.

Editable style templates include natural narration, gentle bedtime reading, fiction performance, knowledge explanation, classical recitation and news reading. OpenAI-compatible services must support the relevant instructions. MiMo offers preset voices or voice design from a description, not voice cloning. Descriptions instruct the model and are not spoken text; results depend on the service.

A compact reader bar provides play/pause, previous/next paragraph arrows, return to the narration page and start from this page. Paragraph navigation preserves playing or paused state. Pitch and speed share equal-width groups. Labels are centered above their controls on narrow screens and beside them when there is room. Pitch accepts 0.5–2.0× in 0.1 steps with direct input. The compact speed control accepts 0.1–4.0× in 0.1 steps, using minus/plus buttons or direct input. On Android, MiMo pitch adjusts local playback immediately without regenerating buffered speech, including after pause/resume; other platforms use provider-dependent style instructions. System/instruction-based speed does not guarantee an exact multiplier. Clearing speech settings requires confirmation and does not clear the library. Transfer speech configuration through **Global settings backup**, not a separate QR entry.

Online speech buffering provides lookahead (default 3 extra passages), maximum characters per request (240), synthesis concurrency (2), paragraph pause (0 ms), cache retention (10 minutes) and manual cache clearing. Stop and restart speech to apply playback changes; pause/resume retains the current settings. The reusable audio cache is memory-only, capped at 32 MiB; retention 0 clears it on stop. Manual clearing preserves active audio and the prepared queue. System TTS does not use these online settings. Prefetching may incur extra usage and high concurrency may trigger provider limits.

See [speech in the feature guide](FEATURES.md#9-speech-voices-and-buffering) for selectable values, [buffer UI](../lib/widgets/settings/tts_buffer_settings.dart) and [validation](../lib/models/tts_buffer_settings.dart).

## Reading History

Edit History to choose whether tapping a book opens its details or starts reading. Save or discard the choice with the layout changes; the selector is hidden outside editing. Details mode retains the blurred long-press preview.

Tap an available book's cover or title to continue reading through the existing book-opening flow. Deleted books show a notice and retain their reading records. Rearrange the Recently read, This week, Daily reading average and Most annotated cards alongside the existing charts; dates, progress, active days and note counts make the cards easier to browse. The daily average counts only days with recorded reading.

The reader style panel also provides Original / Simplified / Traditional Chinese conversion beside the Chinese font selector; this changes presentation without rewriting the source book.

## Cloud sync and the remote library

**Settings → Sync** provides **WebDAV / Object storage** tabs. Object storage includes presets for Alibaba OSS, Tencent COS, Amazon S3, Cloudflare R2, RainYun ROS, Qiniu Kodo, Baidu BOS and Volcengine TOS, plus custom endpoints such as MinIO. Upgrades directly retain existing WebDAV accounts, passwords and enabled state. Turn sync off and wait for transfers before explicitly changing backend. Both connection configurations are retained separately; cloud files are not migrated. Passwords and keys are hidden by default with a common Show/Hide button. See [object storage setup, permissions and limitations](OBJECT_STORAGE_SYNC.md).

**Preview and confirm before sync** is off by default and sits under Cloud sync; it stays disabled until cloud sync is enabled. With it off, automatic sync and the existing asset-first flow are retained. A manual sync first shows both timestamps, books that will join or leave this shelf, reading-progress and note changes, and lets you keep the local or the cloud copy for differing records. The preview updates when the choice changes. Cancelling does not merge or upload library data, including pending uploads from an earlier failed sync. Confirmed local/cloud choices are published as newer operations and covered by the merge backup. Permanently deleted notes, reading sessions and tags stay deleted; legacy cumulative reading time keeps the larger value. While it is on, automatic sync stays paused because a background merge cannot ask for confirmation. The preview is a snapshot; other devices can still change the cloud during confirmation.

Jianguoyun is recognized automatically. Repeated automatic-sync triggers coalesce, with subsequent starts at least ten minutes apart and a per-device/account rolling budget of 480 requests per half-hour. Manual sync respects the budget and server cooldown; restarting does not reset them. Other devices and apps still share the provider's limits. Other WebDAV servers keep their normal automatic-sync frequency. All providers respect HTTP 429/503 and Retry-After. Local changes are retained for later retry.

With automatic sync enabled, startup, foreground/unlock and network restoration initiate sync without the ordinary two-second debounce, on both the bookshelf and reader (including E-Ink devices). Closing a book first drains saved reading/narration writes, then requests sync. Jianguoyun still observes its ten-minute interval, budget and cooldown; Wi-Fi-only restrictions remain. Pending requests are device-local and survive restart; only successful sync acknowledges them. While foregrounded, failed requests are retried after one minute through the same rate-limit gate. Locking/backgrounding cancels waiting timers, not the pending intent; foreground/network restoration resumes it. Background execution or immediate completion before locking is not guaranteed.

For older TXT / Markdown books whose converted EPUB checksum fails, upgrade and sync the device holding the local book before downloading on another device. Keep that local copy until synchronization and download succeed.

In **Settings → Sync**, enter the WebDAV parent URL, account and password, test, then enable sync. Data lives in its modu directory; do not append /modu again. Before migrating old anx / Anx directories, stop sync on every device and back up both local and server data. Do not overwrite an existing modu directory.

Sync merges books, notes, bookmarks, folders, tags and reading records by stable identity. The most recent actual reading action determines position, not the furthest progress. Reliable ETag servers primarily use conditional database8.db writes and clean up covered logs; unreliable servers use content-addressed logs and compaction. Failure must not become an empty-library upload; the first compaction still needs to read old logs.

Fonts, backgrounds, local dictionaries and vector indexes are not library-synced. Keep clients on matching versions where possible. A book record on the shelf does not mean its content is downloaded.

Ordinary and PDF readers do not show sync-success messages. After a failed reader sync, Modu retries the complete reconciliation up to three times, respecting service cooldowns; if all attempts fail, it shows one notice with the failure reason. Repeated failures remain quiet until a successful sync resets the notice. Reader attempts check connectivity: no connection, or no Wi-Fi with Wi-Fi-only enabled, silently defers synchronization and preserves pending progress. Sync notices outside the reader remain unchanged.

Timed sync during reading is off by default. It requires cloud sync (WebDAV or object storage) and automatic sync, runs during foreground reading and respects Wi-Fi-only settings. The default is 5 minutes, with 1/2/3/5/10/15/30/60-minute choices. Locking or leaving pauses it; returning waits a full interval. Missed intervals are not replayed and requests do not overlap.

**Sync service settings, API keys and passwords** is separate and off by default, and shared by WebDAV and object storage. It requires an independent sync encryption password of at least 12 characters, not your WebDAV password or object-storage key. Sensitive service settings use AES-256-GCM encryption; WebDAV/object-storage connection credentials are excluded. The encryption password is not included in sync data. Books, notes and the whole database do not become encrypted, and lost passwords cannot recover the keys.

**Remote library settings** configures a separate browse/download connection; it does not modify that library server's files. Configuration is stored locally, and credentials follow their independent transfer switch. This is distinct from library synchronization.

In **Remote library**, use the current-folder import button or a folder's menu to include supported books in subfolders, then select the books to download and import. Transfers run sequentially with duplicate checks, progress and cancellation; already imported books remain after cancellation. Directory listings are parsed in a background worker with a 32 MiB response limit. Book downloads retain the 512 MiB limit and their integrity checks.

## Two backup types

| Need | Entry | Contents |
| --- | --- | --- |
| Transfer preferences/prompts | Settings → Global settings backup | JSON / modu link, without books or chats |
| Back up the local library | Settings → Sync → Database backup | ZIP with local books, covers, fonts, backgrounds, AI history, general settings and database records |

Global settings backup includes appearance, reading layout, keyboard shortcuts, CSS, selection tools, prompts, plugins, speech, translation and model choices. It excludes font/background/dictionary/model files, books, notes, chats and reading progress. **Accounts, passwords and API keys are excluded by default; including them produces recoverable plaintext JSON / links, not encrypted backups.** Review the import scope first. With the credentials switch off, existing local credentials are preserved. There is no QR transfer; use a file for a complete backup.

Download the books you want to keep before exporting Modu-Backup-*.zip. Service credentials are excluded by default; optional encryption protects the settings section, not all books, notes or chats. Import the ZIP without unpacking it. Restore replaces the current library and backed-up settings rather than merging them. Back up current data first, wait for sync/indexing to finish, then close and reopen after restore.

Windows exports default to the user's Downloads directory, usually `C:\Users\<username>\Downloads`. Other platforms use the system save destination. Successful export shows the actual location and lets you copy it. If Android returns only a document identifier, find the filename in the selected folder.

## Data, security and feedback

Unreleased: contact links are removed from feedback. Bug reports include crash and safe runtime diagnostics by default, independently optional, with full preview and confirmation before proceeding; nothing uploads automatically. Runtime diagnostics retain only the current process's last 300 fixed operation states, elapsed times, durations and RSS samples, never raw ordinary logs, titles, book text, paths, URLs, accounts or keys. They clear on every restart. Ordinary local logs still default to startup cleanup (configurable under Advanced); separate crash diagnostics remain available after restart.

Storage shows usage and can clear regenerable temporary data. Wait for imports, sync and downloads to finish before clearing. Cache cleanup should retain books, notes, chats, downloaded models and completed indexes.

Advanced contains logs, network and JavaScript options. Enable book scripts and custom CSS only for trusted sources. Distinguish bugs from feature suggestions, include version/platform/reproduction steps, and preview/redact reports before submitting. Do not upload private books, credentials or full databases.

[Privacy](../PRIVACY.md) · [Security](../SECURITY.md) · [Contributing](../CONTRIBUTING.md)

### Translation font colours

- Body colours continue to use the existing text/background palette in **Style**, without a duplicate control or override. Ordinary and PDF/OCR reflow reading retain their existing colour behaviour.
- Language and Classical Chinese translations each offer an independent output colour below their font setting, saved and backed up separately without changing source text. Choose presets (including teal `#287D75` and blue `#287FA3`), a custom colour or hex input.
- Cancel discards edits. **Restore default** requires confirmation and resets only the selected translation colour to inherit the original colour, preserving other typography settings.
- Both reader translation panels offer a **Translation appearance** shortcut for font, colour, size, bold, italic and preview in ordinary and reflow reading. Opening or editing appearance neither stops translation nor sends another request.

- Both translation font sizes use the Style slider range and steps (0.5–3.0, in 0.1 steps; 1.0 uses the same 16 px base as body reading), with live preview and an independent **Follow original** reset. The language preview uses a fixed translation of “学而时习之，不亦乐乎？” in the selected translation target language, independently of the app language and without a service request.

### 1.3.5 additions

Settings → Reading: popup height limit 40–80% (default 80%); reading popup opacity 20–100% (default 100%). Both stay on this device and are excluded from sync. Opacity is disabled in E-Ink mode; narration and zoom floating bars retain their original appearance.
