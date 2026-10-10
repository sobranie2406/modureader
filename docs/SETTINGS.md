# Modu 1.2.4 settings and features

English · [简体中文](SETTINGS_zh.md) · [Home](../README_EN.md) · [Documentation](README.md)

For stable **1.2.4+10093**, updated 2026-10-09. Phones usually open settings one page at a time; wide desktop windows use a two-column layout. Some capabilities depend on the operating system, reader engine and selected service.

The 1.2.3 source review was updated for the changes in [1.2.4](https://github.com/sobranie2406/modureader/tree/v1.2.4). See the [detailed feature guide](FEATURES.md) for workflows, defaults and boundaries. Source and automated checks are distinct from device acceptance on every platform.

## Settings entry points

Open **Settings** from the home navigation. The app language can follow the system or be selected manually. Built-in prompts have localized defaults; prompts you have edited are not automatically translated or overwritten.

| Category | Purpose |
| --- | --- |
| Appearance | Theme, colors, OLED / E-Ink, language, covers and navigation |
| Reading | Fonts, layout, page turning and long-press word/paragraph selection |
| CSS settings | Named profiles, visual controls, custom CSS and regex highlights |
| Custom dictionaries | Import and query MDX / StarDict offline |
| Selection search | In-app browser, search engines and custom URLs |
| Selection toolbar | Action switches, drag sorting, annotation colors and AI selection templates |
| AI Settings | Providers, model parameters, display and tool permissions |
| AI Reading Skills | Visibility, unified sorting, prompts and restoring defaults |
| Vector Model / Embedding Models | Local or remote embeddings, automatic indexing, downloads and stopping tasks |
| OCR model | Lightweight recognition models, download sources, selection and deletion |
| Narrate | Engine, voice, speed and editable narration-style templates |
| Sync | WebDAV / S3-compatible object storage, automatic sync, encrypted credential sync and database backup |
| Global settings backup | Settings files or modu links, with optional credentials |
| Remote library settings | Separate WebDAV browsing and book downloads |
| Translation | Engine, target language, AI and DeepL / DeepLX |
| Storage / Advanced | Data, cache, TXT chapter splitting, ANX backup import, logs and network |
| Bug reports and feature requests / About | Reports, project links, licenses and app updates |

### First-use defaults

These come from [preferences](../lib/config/shared_preference_provider.dart) when the setting has never been saved. Upgrades, imports and independent provider configurations can change them.

| Setting | Default |
| --- | --- |
| E-Ink, tap-only turns, long-press paragraph selection | Off |
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

## Checking and installing updates

Open **Settings → About Modu → App updates**. Checking and downloading share one source selector, initially GitHub. If a check falls back to Gitee because GitHub is temporarily unavailable, the download source changes with it. Check again after manually changing sources; downloads do not mix sources midway. Finding an update does not automatically download or install it, and a failed check does not interrupt reading.

- **Android:** in-app downloads verify size and SHA-256, then package name, signature and version before opening the system installer. Installation permission is requested only when needed; installation is not silent.
- **Windows / Linux:** verified in-app downloads open the EXE / DEB for normal installation. Windows needs WebView2; Linux packages target Debian 13.
- **macOS:** the default browser downloads the DMG. Quit Modu and drag Modu.app onto Applications to replace it. Modu cannot monitor browser completion or claim to have verified that file; compare it with the release's SHA-256 yourself. The disk image contains only the app and Applications shortcut. It is not Apple-notarized.
- **iOS:** the IPA needs your own valid signing and cannot install itself from the app. Store builds should update through their original store.

Back up and upgrade in place; do not uninstall or clear data first. Opening an installer does not mean installation has finished. See [installation and release instructions](RELEASING.md) for platform requirements.

## Reading ordinary books

Supported formats include EPUB, PDF, MOBI, AZW3, FB2, TXT, Markdown and text UMD. TXT / Markdown / UMD are converted to EPUB on import for reading and synchronization. UMD retains chapters, metadata and supported covers; image/comic UMD is unsupported. The library supports folders, tags, pinning and moving selected books into folders. Download remote books before reading offline or indexing them.

Import multiple files or choose a folder and select its supported books, including subfolders. Desktop drag-and-drop accepts folders on the library or reading screen. Source files are preserved. Cover badges show the original TXT / MD / UMD format when recognized, otherwise the stored format, and a scanned-book label where applicable; manual classification takes priority over automatic detection.

Cover-opening and return transitions are shared across platforms and follow the disabled-motion preferences; iOS retains edge-swipe return. Dragging iOS text-selection handles updates the selection menu. MOBI note popups require a reliably matching legacy layout; AZW3 note types and explicit image-note text are recognized. Matched notes are hidden from the body and remain available in popups; ambiguous MOBI content stays visible.

The floating home navigation bar is translucent, with space at the end of scrollable content so the last item remains accessible. **Appearance → E-Ink** disables app transitions, animated page turning and decorative motion, uses monochrome labels, and restores normal motion when switched off.

Tap the text to open the bottom panel. Drag the progress slider to preview a chapter title, or use previous chapter, previous page, next page and next chapter. **Chapter progress** means chapter number / chapter count; **progress within the chapter** means current page / pages in that chapter.

**Style** includes font size, **font thickness 0.5–2.0 in 0.1 steps**, simulated bold, line spacing, paragraph spacing, fonts and backgrounds. Actual weight changes depend on the font; try simulated bold with fixed-weight fonts. More reading settings contain side margins and header/footer options. App themes and book backgrounds are separate.

- Import TTF / OTF fonts locally. Successful imports apply immediately; batch imports apply the last successful font. Online font downloads need a connection.
- Scroll-page movement can be set to 80%–100% of the viewport. Free scrolling is independent of this setting.
- Long press can match a word or expand to a paragraph. Selection handles remain available to adjust the range after the initial match.
- Mobile tap-only paging does not disable selection or continuous scrolling. Desktop arrow keys and eligible drags turn pages; selecting or typing is not treated as paging.
- Reading brightness follows the system by default, with manual 20%–100% adjustment. Android uses window brightness; other platforms dim the app. This preference is local to the device.

## PDF and scanned-image books

PDF uses dedicated original-page controls. EPUB, MOBI, AZW3 and FB2 are classified during import by sampling up to five body sections, for both local and remote imports. Opening a book reads its saved classification rather than waiting for sampling. The bookshelf menu can manually mark a book as scanned or restore ordinary reading.

**Ordinary text books keep their existing menus and styling; PDF-specific settings do not affect them.** Scanned books disable ordinary illustration tap-to-enlarge / long-press actions.

The dedicated panel offers fit-page / fit-width, zoom, rotation, panning, continuous scrolling, crop and panels, and reading order. Original and cropped images adapt to the window and settings; layout is saved per book.

- Automatic cropping detects content bounds per page while retaining useful text, page numbers and footnotes. Use manual crop/panels for difficult layouts.
- Image enhancement offers ink color, contrast, darkening, whitening, sharpening and scanned watermark fading. Adjust intensity, compare the original or reset. Conservative watermark fading cannot remove every watermark.
- Processing does not rewrite the source book. Controls follow the app theme; manual / every-N-pages refresh appears only in E-Ink mode and requires a supported device interface.
- Text reflow uses the page's text layer; OCR reflow recognizes image text. Both process the current page, or the whole cropped page when cropping is enabled, and display the result directly in the reader.
- Reflowed text supports styling, selection, annotations and AI tools. The PDF panel's gear opens the relevant text-style controls.
- Only **Extract** asks for a region. Recognition fills an editable AI draft; review and send it yourself. It does not automatically upload the book.

### OCR models

Open **Settings → OCR model**. **PP-OCRv4 Chinese / English** is recommended; v5 mobile Chinese / English, v3 Chinese / English and v3 English are also available. Weights are downloaded on demand, not bundled. Choose upstream or the Gitee mirror: v4 / v3 use Hugging Face upstream, while v5 uses ModelScope.

Cards support download-and-use, selection, verification, cancellation and deletion. Files must pass size and SHA-256 checks before use. Deleting a downloaded model does not delete books. Recognition runs locally and needs no OCR API key. Model choice and source settings can be backed up; model files are not transferred in global settings backups. Review small text, complex columns and poor-quality scans manually.

## CSS and selection tools

**Settings → CSS settings** provides 32 named slots and 13 editable presets. Enable the master switch and desired profiles; multiple profiles can apply together. Each book can follow the default combination or select its own. Profile contents are shared globally, so editing one can affect other books using it.

CSS changes layout; regex highlights style matching text with colors, backgrounds and underlines without rewriting text or annotation positions. Import trusted CSS / JSON only: remote resource URLs can make network requests. New, copied and imported profiles start disabled; imports fill empty slots without silently overwriting profiles.

**Selection toolbar** lets you toggle and drag-sort built-in tools and AI commands, and edit annotation colors, names, icons and prompts. Common AI presets start disabled, including AI Knowledge and Classical Chinese translation. Manage selection templates here, separately from AI Reading Skills; both use the same reader AI dialog.

Each selection command can use **text with context** (default) or **selected text only**, and can opt into online search. Explicit scope choices are preserved. AI Knowledge uses the current model's knowledge first. To check further, choose **Online search** below the answer, before Regenerate and Copy. Wiktionary, Wikipedia and Baidu Baike results are summarized with sources by the same model in the same conversation. No extra search API key is required.

## AI configuration, skills and conversations

Add an endpoint, model and API key in **Settings → AI Settings → Provider configuration**, then test the connection. Each configuration keeps its own temperature, maximum output tokens, history depth and reasoning settings. Supported parameters and costs depend on the provider; RPM controls request pacing, not provider limits.

**AI tools** controls the app tools a model may call. A reading-skill prompt does not automatically supply the entire book: available material depends on the selection, accessible chapters and retrieved passages.

**AI Reading Skills** shows skill shortcuts by default. Built-in and custom skills can be enabled, sorted and edited together. Restore their default order or restore deleted built-in skills. **Fill the input with the skill template first** is off by default: off sends immediately, while on fills the draft so you can add a chapter range or instructions before sending. The switch is available in settings and the dialog.

A skill can start a new task conversation. Follow-up questions typed into the current or a restored historical conversation continue with its permitted history. The history entry restores the conversation, not only its question. Completed replies return to their beginning for reading. AI font size is independent; mind maps support full screen, zoom, pan, branch collapse and PNG / SVG / Markdown / FreeMind / JSON export.

Backups store your changes to built-in prompts and your custom templates, not redundant copies of unchanged defaults. Restoring a default replaces its customization. Remote AI receives the actual request text and supplied context; see [Privacy](../PRIVACY.md).

## Vector indexing and semantic retrieval

Open **Settings → Vector Model / Embedding Models**. Embedding models retrieve passages; chat models answer questions. They are configured separately.

Local models include Chinese BGE (default), English BGE, MiniLM and multilingual E5. Download from Hugging Face or Gitee with size and SHA-256 verification. Missing models are not silently downloaded. A remote embeddings API receives indexed passages and queries and may charge for them.

Index / re-index from a book's menu, or enable automatic indexing after import (off by default). Unavailable models or books without local files cannot be queued. If both model and source book are unchanged, an upgrade or replacement package alone should not invalidate a valid index. Changing the model or content requires re-indexing.

**Stop vectorization**, in the library task bar and model settings, disables automatic indexing and cancels active and queued tasks while retaining completed indexes, books and models. Turning off automatic indexing alone cancels automatic tasks without preventing later manual indexing.

**Vector indexes stay local and do not participate in WebDAV / S3 library sync.** Build an index on each device as needed. Local embeddings do not make a remote chat answer offline: retrieved passages supplied to remote AI still leave the device.

## Dictionaries, search and translation

Import MDX 1/2 or StarDict companion files / ZIP that you are entitled to use. Lookup is offline and uses actual headwords; edit the query when necessary. Two-way lookup depends on the dictionary containing entries in both languages. There is no reverse search through Chinese definitions. Only text is displayed; dictionary scripts and media are not loaded. Dictionaries are not included in library sync or current backups.

Selection search opens results in the in-app browser. Choose a built-in engine or a custom URL containing {query}; results support zoom. The search site receives the query text.

Inline full-text translation supports Google, AI and DeepL / DeepLX. Original + translation or translation-only paragraphs appear on the book page and follow the reading position. This is not a one-click export of an entire translated book. AI translation uses your configured model; DeepL / DeepLX requires the appropriate endpoint configuration.

The selection-translation window can switch providers and also supports Baidu / Youdao webpages. Webpage translation differs from inline paragraph translation; it offers 50%–200% zoom and vertical scrolling. Scans need usable text or OCR/reflow first. Online services receive the text to translate; review their output.

## Narration and style templates

**Settings → Narrate** offers system voices, Edge TTS, DashScope, Xiaomi MiMo and OpenAI-compatible speech. Configure the required endpoint/key, save, fetch voices, select one and test it. System TTS is connected for Android, iOS, macOS and Windows; Linux / OpenHarmony have no system TTS backend and require explicitly choosing an online service.

Editable style templates include natural narration, gentle bedtime reading, fiction performance, knowledge explanation, classical recitation and news reading. OpenAI-compatible services must support the relevant instructions. MiMo offers preset voices or voice design from a description, not voice cloning. Descriptions instruct the model and are not spoken text; results depend on the service.

A compact reader bar provides play/pause, return to the narration position and read from here. Online playback supports up to 4× with separate 3× and 4× steps after 2×. System/instruction-based speed does not guarantee an exact multiplier. Clearing speech settings requires confirmation and does not clear the library. Transfer speech configuration through **Global settings backup**, not a separate QR entry.

Online speech buffering provides lookahead (default 3 extra passages), maximum characters per request (240), synthesis concurrency (2), paragraph pause (0 ms), cache retention (10 minutes) and manual cache clearing. Stop and restart speech to apply playback changes; pause/resume retains the current settings. The reusable audio cache is memory-only, capped at 32 MiB; retention 0 clears it on stop. Manual clearing preserves active audio and the prepared queue. System TTS does not use these online settings. Prefetching may incur extra usage and high concurrency may trigger provider limits.

See [speech in the feature guide](FEATURES.md#9-speech-voices-and-buffering) for selectable values, [buffer UI](../lib/widgets/settings/tts_buffer_settings.dart) and [validation](../lib/models/tts_buffer_settings.dart).

## Reading History

Tap an available book's cover or title to continue reading through the existing book-opening flow. Deleted books show a notice and retain their reading records. Rearrange the Recently read, This week, Daily reading average and Most annotated cards alongside the existing charts; dates, progress, active days and note counts make the cards easier to browse. The daily average counts only days with recorded reading.

The reader style panel also provides Original / Simplified / Traditional Chinese conversion beside the Chinese font selector; this changes presentation without rewriting the source book.

## Cloud sync and the remote library

**Settings → Sync** provides **WebDAV / Object storage** tabs. Object storage includes presets for Alibaba OSS, Tencent COS, Amazon S3, Cloudflare R2, RainYun ROS, Qiniu Kodo, Baidu BOS and Volcengine TOS, plus custom endpoints such as MinIO. Upgrades directly retain existing WebDAV accounts, passwords and enabled state. Turn sync off and wait for transfers before explicitly changing backend. Both connection configurations are retained separately; cloud files are not migrated. Passwords and keys are hidden by default with a common Show/Hide button. See [object storage setup, permissions and limitations](OBJECT_STORAGE_SYNC.md).

Jianguoyun is recognized automatically. Repeated automatic-sync triggers coalesce, with subsequent starts at least ten minutes apart and a per-device/account rolling budget of 480 requests per half-hour. Manual sync respects the budget and server cooldown; restarting does not reset them. Other devices and apps still share the provider's limits. Other WebDAV servers keep their normal automatic-sync frequency. All providers respect HTTP 429/503 and Retry-After. Local changes are retained for later retry.

For older TXT / Markdown books whose converted EPUB checksum fails, upgrade and sync the device holding the local book before downloading on another device. Keep that local copy until synchronization and download succeed.

In **Settings → Sync**, enter the WebDAV parent URL, account and password, test, then enable sync. Data lives in its modu directory; do not append /modu again. Before migrating old anx / Anx directories, stop sync on every device and back up both local and server data. Do not overwrite an existing modu directory.

Sync merges books, notes, bookmarks, folders, tags and reading records by stable identity. The most recent actual reading action determines position, not the furthest progress. Reliable ETag servers primarily use conditional database8.db writes and clean up covered logs; unreliable servers use content-addressed logs and compaction. Failure must not become an empty-library upload; the first compaction still needs to read old logs.

Fonts, backgrounds, local dictionaries and vector indexes are not library-synced. Keep clients on matching versions where possible. A book record on the shelf does not mean its content is downloaded.

Timed sync during reading is off by default. It requires cloud sync (WebDAV or object storage) and automatic sync, runs during foreground reading and respects Wi-Fi-only settings. The default is 5 minutes, with 1/2/3/5/10/15/30/60-minute choices. Locking or leaving pauses it; returning waits a full interval. Missed intervals are not replayed and requests do not overlap.

**Sync service settings, API keys and passwords** is separate and off by default, and shared by WebDAV and object storage. It requires an independent sync encryption password of at least 12 characters, not your WebDAV password or object-storage key. Sensitive service settings use AES-256-GCM encryption; WebDAV/object-storage connection credentials are excluded. The encryption password is not included in sync data. Books, notes and the whole database do not become encrypted, and lost passwords cannot recover the keys.

**Remote library settings** configures a separate browse/download connection; it does not modify that library server's files. Configuration is stored locally, and credentials follow their independent transfer switch. This is distinct from library synchronization.

In **Remote library**, use the current-folder import button or a folder's menu to include supported books in subfolders, then select the books to download and import. Transfers run sequentially with duplicate checks, progress and cancellation; already imported books remain after cancellation. Directory listings are parsed in a background worker with a 32 MiB response limit. Book downloads retain the 512 MiB limit and their integrity checks.

## Two backups and ANX import

| Need | Entry | Contents |
| --- | --- | --- |
| Transfer preferences/prompts | Settings → Global settings backup | JSON / modu link, without books or chats |
| Back up the local library | Settings → Sync → Database backup | ZIP with local books, covers, fonts, backgrounds, AI history, general settings and database records |
| Migrate from ANX | Settings → Advanced → Import ANX Reader backup | Validate an ANX ZIP and merge supported books/records |

Global settings backup includes appearance, reading layout, CSS, selection tools, prompts, speech, translation and model choices. It excludes font/background/dictionary/model files, books, notes, chats and reading progress. **Accounts, passwords and API keys are excluded by default; including them produces recoverable plaintext JSON / links, not encrypted backups.** Review the import scope first. With the credentials switch off, existing local credentials are preserved. There is no QR transfer; use a file for a complete backup.

Download the books you want to keep before exporting Modu-Backup-*.zip. Service credentials are excluded by default; optional encryption protects the settings section, not all books, notes or chats. Import the ZIP without unpacking it. Restore replaces the current library and backed-up settings rather than merging them. Back up current data first, wait for sync/indexing to finish, then close and reopen after restore.

Windows exports default to the user's Downloads directory, usually `C:\Users\<username>\Downloads`. Other platforms use the system save destination. Successful export shows the actual location and lets you copy it. If Android returns only a document identifier, find the filename in the selected folder.

ANX import accepts original schema-7 backup ZIPs. It imports downloaded books, covers, notes, progress, time, folders and tags, but not accounts, app settings, AI chats or books with missing content. Files determine identity; repeated import does not duplicate matching records. A local database snapshot is created first. Standalone DB files, encrypted ZIPs and unknown schema versions are unsupported. This is migration, not ongoing cross-app sync.

## Data, security and feedback

Storage shows usage and can clear regenerable temporary data. Wait for imports, sync and downloads to finish before clearing. Cache cleanup should retain books, notes, chats, downloaded models and completed indexes.

Advanced contains logs, network and JavaScript options. Enable book scripts and custom CSS only for trusted sources. Distinguish bugs from feature suggestions, include version/platform/reproduction steps, and preview/redact reports before submitting. Do not upload private books, credentials or full databases.

[Privacy](../PRIVACY.md) · [Security](../SECURITY.md) · [Contributing](../CONTRIBUTING.md)
