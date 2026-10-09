# Modu detailed feature guide (checked against source)

English · [简体中文](FEATURES_zh.md) · [Settings](SETTINGS.md) · [Documentation](README.md)

Reviewed **2026-10-08**, updated for changed features **2026-10-09**, app **1.2.4+10093**, source baseline [v1.2.4](https://github.com/sobranie2406/modureader/tree/v1.2.4). This guide follows visible entry points, connected services, preference defaults and validation. Source support is not certification on every device or provider. Recheck implementation when it changes rather than only changing this version label.

## 1. Getting started

1. Use **Import books** on the bookshelf to select files or a folder; desktop also accepts drag-and-drop.
2. Open a cover and adjust **Style** and additional reading settings from the reader menu.
3. Import your dictionaries in **Settings → Custom dictionaries** for offline lookup.
4. Configure a provider and model in **Settings → AI settings** before using AI.
5. Choose a speech service in **Settings → Read aloud**, save edits, load voices and preview.
6. Configure WebDAV or object storage in **Settings → Sync** for multiple devices. Back up before connecting an existing cloud library.

Ordinary book reading does not require AI, cloud sync or online speech. Downloaded resources and selected services determine what can work offline.

## 2. Import, bookshelf and remote library

| Feature | Behavior | Boundary |
| --- | --- | --- |
| File import | EPUB, PDF, MOBI, AZW3, FB2, TXT, `.md` / `.markdown`, text UMD; multiple selection | An accepted extension does not guarantee every damaged, encrypted or unusual book can be parsed |
| Folder import | Includes subfolders and lets you select compatible files | Original files remain; files must be accessible |
| TXT / Markdown | Converted to EPUB, then use normal reading, notes and sync | The source is unchanged; Markdown does not execute Mermaid, LaTeX or scripts |
| Organization | Folders, bulk moves, tags, pins and book-menu actions | A cloud book record is separate from its downloaded body |
| Cover badges | Original TXT / MD / UMD format when recognized, otherwise stored format; scanned-book classification | Display metadata does not change stored files or synchronization checksums |
| Remote library | Independent WebDAV browsing, downloads and selectable folder imports including subfolders | Separate from library sync; does not edit server books; cancellation preserves completed imports |

Text UMD imports preserve chapters, metadata and supported covers, converting to EPUB in a background worker. The file limit is 64 MiB and decoded text is limited to 32 MiB; image/comic UMD is unsupported. Remote listings are parsed in a background worker with a 32 MiB response limit, while book downloads retain the 512 MiB limit.

Use UTF-8 Markdown. The first level-one heading supplies the title; headings form a table of contents. Common formatting, tables, code and static content are supported. Base64 images can be embedded; adjacent image folders are not read automatically and network images are not downloaded. Use EPUB for complete packaged resources. Markdown files are limited to 64 MiB. See [Markdown books](MARKDOWN_BOOKS.md).

Source: [formats](../lib/service/book_formats.dart), [import picker](../lib/widgets/bookshelf/book_import_picker.dart), [bookshelf](../lib/page/home_page/bookshelf_page.dart), [remote library](../lib/service/remote_library/webdav_library.dart), [Markdown converter](../lib/service/convert_to_epub/markdown/convert_from_markdown.dart).

## 3. Text-book reading

The reader offers a table of contents, book search, bookmarks, reading progress and chapter navigation. The progress panel supports previous/next chapter and page. Chapter number and progress within the current chapter are different indicators.

Style controls font, size, thickness, simulated bold, line/paragraph spacing and backgrounds. Additional settings control margins, layout and navigation. Import TTF/OTF fonts; available weights depend on the font. Horizontal/vertical presentation depends on the book and reader. **Original / Simplified / Traditional Chinese** beside the Chinese font selector changes display without rewriting the book.

| Setting | Default / range | Effect |
| --- | --- | --- |
| Font thickness | 0.5–2.0, step 0.1 | Font-dependent; simulated bold is available |
| Scroll page amount | 80%; adjustable 80%–100% | Affects a page-turn action, not continuous manual scrolling |
| Tap-only page turns | Off | Mobile swipes no longer turn pages; selection and scrolling remain |
| Long-press paragraph selection | Off | Word matching by default; handles remain adjustable |
| Reading brightness | Follow system; manual 20%–100% | Android window brightness; app dimming elsewhere, saved locally |
| E-Ink mode | Off | Removes app motion and uses solid display styles |

Desktop navigation keys respect reader focus, text fields and overlays. All platforms share cover-opening and return transitions, skipped when motion is disabled or E-Ink is enabled; iOS retains edge-swipe return and refreshes selection menus after handle drags. App theme and page background are separate.

MOBI note popups are recovered for matching legacy note-list/superscript-icon structures. AZW3 retains note semantics and can use explicit embedded note text where conversion links point to the wrong note. Matched inline notes are hidden in the body; ambiguous MOBI content stays visible. Original book bytes and annotation text-node positions are preserved.

Source: [reading settings](../lib/page/settings_page/reading.dart), [style controls](../lib/widgets/reading_page/style_widget.dart), [defaults](../lib/config/shared_preference_provider.dart), [keyboard](../lib/service/reader_keyboard.dart), [brightness](../lib/service/app_brightness.dart).

## 4. PDFs, image books and OCR

PDFs use original-page controls. Import samples EPUB/MOBI/AZW3/FB2 content to classify image books; opening reads the saved result. A book-menu action can correct classification. Ordinary text books keep their normal menus.

- Fit page/width, 100%–1500% zoom, rotation, viewport movement and single-page/continuous scrolling.
- Automatic/manual crop, panel divisions and reading order, stored per book without overwriting originals.
- Ink tone, contrast, darkening, whitening, sharpening and watermark fading, with original comparison.
- More controls include page borders, scroll separators, grayscale, pan-before-turn and horizontal/reversed/vertical/tap-only navigation.
- Automatic turns are off by default; enabling uses 30 seconds, adjustable 5–600 seconds. Background, menus, input and selection suspend them.
- Named watermark layers can be hidden when supported. This differs from fading a watermark inside an image; neither guarantees removal of every watermark. App grayscale does not expand hardware capabilities.
- E-Ink refresh controls require a supported device interface for actual hardware refresh.

| Action | Input | Output / boundary |
| --- | --- | --- |
| Text Reflow | Existing current-page text layer | Selectable text in the reader; not whole-book conversion |
| OCR Reflow | Current-page image, local OCR | Uses the entire cropped page when crop is enabled, not just a panel or zoomed viewport |
| Extract | User-selected region | Editable AI draft; does not send automatically |

**Settings → OCR model** recommends PP-OCRv4 Chinese/English; v5 mobile, v3 Chinese/English and v3 English are also available. Download and verify size/SHA-256 first; choose upstream or Gitee. V5 uses ModelScope upstream, v3/v4 Hugging Face. Recognition runs locally without an OCR API key. Complex columns, small text and poor scans need checking.

Reflow can use selection tools. An image without text/OCR is not directly selectable text. Whole-book OCR/export and identical search/annotation/speech behavior across all scans are not promised.

Source: [page controls](../lib/widgets/reading_page/pdf_reading_controls.dart), [layout](../lib/widgets/reading_page/document_layout_editor.dart), [reflow](../lib/widgets/reading_page/document_reflow_reader.dart), [extraction](../lib/widgets/reading_page/document_extraction_panel.dart), [models](../lib/service/ocr/ocr_models.dart).

## 5. CSS, selection, highlights and notes

**Settings → CSS settings** provides 32 named profile slots, visual controls, custom CSS and regex highlights. Enable the main switch and selected profiles; a book can use the default combination or its own. Editing a shared profile affects other books using it. New, copied and imported profiles start disabled; imports use empty slots.

Regex highlights are display rules, not saved annotations. CSS does not rewrite books; remote CSS resources may use the network and results depend on the engine/book.

Selection actions include annotations, notes, dictionaries, translation, search and AI according to enabled buttons and reading mode. **Selection toolbar** controls order, colors and custom AI labels/icons/prompts separately from reading skills. AI selection commands can use context or only selected text. AI Knowledge's **Online search** can retrieve dictionary/encyclopedia evidence in the same conversation without a separate search API key.

Quick highlights can show the selection menu after saving; that preference starts off. Existing merge rules handle successive cross-page marks. Notes can be viewed, searched, edited and exported by clipboard, Markdown, TXT or CSV. Reading-position links can reopen available books; a notes export is not a complete library backup.

Source: [CSS profiles](../lib/models/custom_css_profile.dart), [selection settings](../lib/page/settings_page/selection_toolbar.dart), [quick marks](../lib/service/book_player/quick_mark_service.dart), [notes export](../lib/service/notes/export_notes.dart), [reading links](../lib/service/notes/reading_link.dart).

## 6. Dictionaries, search and translation

Import, rename, enable/disable and remove dictionaries in **Custom dictionaries**. Supported inputs are MDX 1/2, StarDict companion files and a ZIP containing one dictionary. Lookup queries actual entries in enabled dictionaries and permits editing the term. Reverse lookup depends on supplied headwords; Chinese definitions are not indexed as reverse-search terms.

Definitions are text only: no scripts, MDD, images or audio. MDX 3, LZO and encrypted records are unsupported; commercial variants are not universally compatible. Lookup does not silently switch to online translation. Dictionary files are excluded from sync/current backups. See [formats and limits](LOCAL_DICTIONARIES.md).

**Selection search** accepts preset engines or custom URLs containing `{query}`. Its browser zoom defaults to 100%, adjustable 50%–200%. Queries go to the selected website.

Visible translation choices are Google Translate (Free), AI, DeepL/DeepLX and Google/Bing/Baidu/Youdao web pages. Full-text translation uses Google Free, AI or DeepL; web-page results are a separate selection mode. Baidu/Youdao choose language inside their page. Configure a target language, AI translation model and DeepL key/address as needed. Automatic translation after selection starts off.

Inline translation displays original plus translation or translation alone; it does not export a translated book. Text goes to the provider. Scans require a text layer or OCR/reflow first.

Source: [dictionary service](../lib/service/dictionary/local_dictionary.dart), [search](../lib/page/settings_page/selection_search.dart), [translation UI](../lib/page/settings_page/translate.dart), [visible providers](../lib/service/translate/index.dart), [free transport](../lib/service/translate/microsoft_free.dart).

## 7. AI providers, conversations and skills

The app uses the user's configured provider/model, not a fixed QQ-bot Qwen model. Add the endpoint, model and key in **AI settings → Provider configuration**, then test. Per-model controls include temperature, output/context limits and reasoning parameters. Provider support, limits and cost apply; RPM only paces requests. The `isOhosStore` build flag hides AI settings and reading-skill entries; availability follows the installed build.

Continue chats, recover history and adjust text size. Tool-capable models can use enabled bookshelf, note, history, chapter/content, calculator, time and mind-map tools. Bookshelf organization produces a plan requiring Apply inside the app. A prompt is not proof the model received the whole book or changed data.

Reading skill controls are visible by default. Built-in/custom skills can be toggled, reordered, edited and restored. Template-draft mode starts off (tap sends); enabling fills the input before manual sending. Built-in prompts follow app language; edited prompts are preserved.

| Skill / use | Actual context |
| --- | --- |
| Chapter summary, concepts, arguments, quotes, reading guide, vocabulary, mind map | Selection or obtainable current chapter; no automatic cross-chapter retrieved snippets |
| Smart translation | Selected text |
| Whole-book summary | Chapters through the TOC, valid indexed text plus extraction; compressed to a context budget |
| Character tracking | Already-read chapters and current text through the reading position; no whole-chapter substitution when that boundary is unavailable |
| Free chat inside a book | Relevant keyword/vector snippets from that book's valid index |
| Home book questions | Tools identify the book and retrieve; requires enabled tools and model tool support |

Mind maps support fullscreen, zoom/pan, node folding and PNG/SVG/Markdown/FreeMind/JSON export. Check facts, quotes and citations. See [AI/index context](AI_INDEX_USAGE.md).

Source: [skills](../lib/service/ai/readany_skills.dart), [execution](../lib/service/ai/reading_skill_execution.dart), [tools](../lib/service/ai/tools/ai_tool_registry.dart), [provider settings](../lib/page/settings_page/ai_provider_detail_page.dart), [mind-map export](../lib/service/ai/mindmap_export.dart).

## 8. Embedding models and semantic retrieval

Embedding, chat and OCR models have different jobs and settings. Vector models default to enabled/local mode with BGE Small ZH v1.5. Other local choices are BGE Small EN, all-MiniLM-L6-v2 and Multilingual E5 Small, or configure a remote embeddings API. Downloads are explicit and verified. Remote embedding sends indexed snippets/queries and may cost money.

Download the model and book body, then use **Vectorize / Re-vectorize** in the book menu. Manual and automatic work share a queue; indexing after import starts off. **Stop Vectorization** disables automatic indexing and cancels active/queued work while retaining completed indexes, books and models.

Changed content/models require rebuilding; an app upgrade alone should not invalidate an unchanged index. Missing/incompatible models fall back to keywords rather than comparing incompatible vectors; optional index corruption does not block normal search.

Indexes stay local and are not transferred through WebDAV/S3 sync. Other devices build their own. Upgrades do not automatically delete historical cloud indexes. Local embeddings do not make remote chat offline: relevant context still goes to the selected chat provider.

Source: [models](../lib/service/knowledge/local_embedding_models.dart), [queue](../lib/service/knowledge/book_knowledge_index_queue.dart), [retrieval](../lib/service/knowledge/book_knowledge_retriever.dart), [search tool](../lib/service/ai/tools/book_content_search_tool.dart).

## 9. Speech, voices and buffering

Choose system speech, Edge TTS, DashScope, Xiaomi MiMo or OpenAI-compatible speech in **Read aloud**. Save endpoint edits before loading voices or previewing. System speech is connected for Android/iOS/macOS/Windows; Linux/OpenHarmony require explicitly selecting an online service.

Reader controls include play/pause, return to narration and read from here. Online audio playback reaches 4×, with discrete 3×/4× above 2×; system/instruction rates are provider-dependent. Background speech and notification controls depend on OS permissions/power management. OpenAI-compatible/MiMo style prompts require provider support; MiMo text-designed voices are not voice cloning.

**Online speech buffering and cache** exposes these choices:

| Setting | Default | UI values | Meaning |
| --- | --- | --- | --- |
| Lookahead passages | 3 | 0, 1, 3, 5, 8, 12 | Excludes active passage; 0 disables prefetch |
| Characters per request | 240 | 100, 240, 400, 600, 1000, 1500, 2000 | Sentence/paragraph-aware upper limit |
| Concurrency | 2 | 1, 2, 3, 4 | First passage prioritized |
| Paragraph pause (ms) | 0 | 0, 100, 200, 300, 500, 1000, 2000, 3000 | Only at paragraph ends |
| Cache retention (minutes) | 10 | 0, 5, 10, 30, 60, 120 | Immediate; 0 clears on stop |

The first four apply after stop/restart, not pause/resume. Cache is memory-only, bounded to 32 MiB and lost on exit. Clearing preserves current playback/prepared queue. System TTS does not use online settings. Prefetch/concurrency may add usage or hit limits.

Transfer speech preferences through global settings; system voices may need reselection. Clearing speech settings stops speech and removes TTS configuration, leaving library/AI/sync intact.

Source: [settings](../lib/page/settings_page/narrate.dart), [services](../lib/service/tts/tts_service.dart), [platforms](../lib/service/tts/system_tts_support.dart), [buffer UI](../lib/widgets/settings/tts_buffer_settings.dart), [defaults/validation](../lib/models/tts_buffer_settings.dart).

## 10. Reading history

The home Reading History page records time, active dates, progress and notes with heatmaps/trends/streaks and configurable cards. Recent reading, weekly review, daily average and most annotated books are available; daily average counts only recorded reading days. Tap available book titles/covers to reopen. Deleted books show a notice without removing history. Activity in other apps is not measured.

Source: [cards/defaults](../lib/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart), [book links](../lib/widgets/statistic/reading_history_book_link.dart), [recording](../lib/service/statistic.dart).

## 11. WebDAV and object-storage sync

WebDAV uses the parent URL/account/password and its `modu` subdirectory; do not repeat `/modu` in the address. Object-storage presets include OSS, COS, S3, R2, RainYun ROS, Kodo, BOS and TOS plus custom S3-compatible endpoints such as MinIO. Configure endpoint, region, bucket, prefix and keys; advanced settings cover temporary token, addressing, signing and listing version. Test before enabling.

Upgrades retain WebDAV settings. Disable sync and wait for tasks before switching. Connections stay separate; switching does not migrate cloud-only books automatically. Download/back up first. See [object storage](OBJECT_STORAGE_SYNC.md).

| Scope | Behavior |
| --- | --- |
| Books, notes, bookmarks, folders, tags, reading records | Stable-ID merging; reading position follows recent actual actions, not highest percentage |
| Fonts, backgrounds, dictionaries, vector indexes | Excluded |
| Automatic sync | Preference starts on, but cloud connection starts off and must be configured/enabled |
| Timed reading sync | Off; default 5 minutes, choices 1/2/3/5/10/15/30/60; cloud and automatic sync required |
| Foreground restrictions | Pauses on exit/lock, waits a full interval on return; no catch-up/overlap; obeys Wi-Fi-only preference |
| Service configuration sync | Separate, off by default; password of at least 12 characters |

Nutstore coalesces automatic triggers with a minimum 10-minute interval and conservative 480-request/half-hour budget per local account. Manual requests still obey budgets/cooldowns; restarting does not reset them. Other clients consume the same account quota. All WebDAV providers obey 429/503 and Retry-After.

Optional service configuration uses AES-256-GCM, excludes WebDAV/S3 connection credentials and never transfers its encryption password. It does not encrypt book bodies/the entire database. Forgotten passwords cannot recover service keys. A visible book record does not mean its body is downloaded; keep devices on compatible versions.

Source: [sync UI](../lib/page/settings_page/sync.dart), [records](../lib/service/sync/row_sync_engine.dart), [S3 config](../lib/service/sync/s3_config.dart), [scheduler](../lib/service/sync/reading_sync_scheduler.dart), [encrypted settings](../lib/service/sync/ai_settings_sync.dart).

## 12. Backups, restore and ANX migration

| Feature | Entry | Scope / restore |
| --- | --- | --- |
| Global settings | Settings → Global settings backup | JSON/modu link with selectable modules; included preferences only, not library/notes/chat/progress |
| Library backup | Settings → Sync → Database backup | ZIP with local bodies, covers, fonts, backgrounds, database, AI history and general settings; replaces rather than merges |
| ANX import | Settings → Advanced → Import ANX Reader backup | Schema-7 ZIP; merges supported downloaded books, covers, notes, positions, time, folders and tags |

Settings exports exclude resource files and credentials by default. Including credentials makes JSON/links recoverable plaintext. Imports with credentials disabled preserve local keys; imported cloud sync and automatic sync must be re-enabled manually.

Download wanted bodies before library backup. Optional encryption protects the settings portion, not the entire ZIP. Back up current data and finish sync/index tasks before restore; fully restart afterwards. ANX import excludes accounts, settings, AI history and missing bodies; standalone DB/encrypted ZIP/unknown schemas are unsupported. It creates a database snapshot and deduplicates repeated imports; it is not continuous sync between apps.

Source: [settings transfer](../lib/service/config_transfer/global_settings_transfer.dart), [backup UI](../lib/widgets/settings/database_backup_section.dart), [ANX import](../lib/service/local_data/anx_database_import.dart).

## 13. Updates, logs and feedback

**Settings → About Modu → App updates** shares a GitHub/Gitee source selector for checking/downloading, defaulting to GitHub. Recheck after switching sources. Finding an update is not installing it. Back up and upgrade in place. Platform signing/install/runtime limits are in [Releasing](RELEASING.md); source support is not device acceptance.

Storage settings show usage and clean regenerable temporary data; models, books and completed indexes are not ordinary cache. Advanced settings include TXT chapter rules, file-checksum management, logs, network proxy and JavaScript controls. Enable scripts only for trusted books.

**Bug reports and feature requests** has two categories, existing issues and personal report links. Enter reproduction/expected/actual behavior and environment, preview, then open GitHub. Long reports/diagnostics are copied for manual paste; add screenshots/public examples there. Crash diagnostics are opt-in, sanitized available errors/checkpoints rather than all logs/configuration/book text. Ordinary logs are in Advanced settings. Issues are public; inspect before sharing.

Source: [updates](../lib/service/update/app_update.dart), [feedback](../lib/page/settings_page/bug_report.dart), [diagnostics](../lib/service/feedback/crash_diagnostics.dart), [build switches](../lib/utils/env_var.dart).

## 14. Offline/network reference

| Use | Processing / destination |
| --- | --- |
| Downloaded books, notes, dictionaries | Local; book remote resources/enabled scripts or CSS can still network |
| Local OCR/embedding | Model download requires network; inference is local |
| Remote AI/embeddings/speech/translation | Required text/context/query sent to selected provider |
| Search/AI online lookup | Query sent to sites; synthesis may call selected AI |
| Sync | In-scope data sent to configured WebDAV/object storage |
| Feedback | User-reviewed public GitHub issue; optional diagnostics |

App AI and the QQ helper are separate services; this guide does not establish the bot's live model, permissions or deployment. See [Privacy](../PRIVACY.md). This review did not execute every import/OCR/speech/sync/update flow on every platform. Dated historical test reports retain their original dates and are not fresh acceptance claims.
