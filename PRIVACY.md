# Privacy and network behavior

English · [简体中文](PRIVACY_zh.md) · [Home](README_EN.md) · [Settings guide](docs/SETTINGS.md)

Updated 2026-11-08. This document explains storage and network behavior. Third-party services have their own privacy policies.

## Local data and scanned books

Books, progress, notes, bookmarks, reading time and AI history are stored locally by default. Back up important data yourself. This repository and its release packages contain no developer private library, service keys, WebDAV configuration or AI history.

Import-time scanned-book detection, PDF/image-book cropping, panels, image enhancement, scanned watermark fading, text extraction and OCR run locally. These actions do not automatically upload or rewrite source books. Reflow appears in the reader; **Extract** fills an editable AI draft. Sending that draft then uses your selected AI service.

Custom dictionaries are imported, parsed and queried locally. Text results remain available. In 1.2.5, newly imported MDX entries display imported HTML, CSS, JavaScript, images and audio (including matching MDD resources) directly in the result card, in an isolated sandboxed WebView served only on loopback while the view is open. Local scripts run when the original content is displayed, without an app bridge, file access or external network resources; audio requires a user gesture. Older text-only imports require reimporting the MDX and companion resources. StarDict remains text-only. Dictionaries are excluded from library sync and current settings/database backups.

In 1.2.5, optional online dictionary lookup is off by default. Enabling Chinese/English Wiktionary sends the query (which may be selected book text), IP address and normal request metadata to the selected service, not surrounding passages or the book file. Responses are rendered as text with source and license links; no remote scripts, images or audio are loaded. Results are cached only in memory for the lookup window. Local dictionary selections and online opt-in stay on this device and are excluded from settings transfer. Service availability and privacy policies are controlled by their providers.

Custom CSS can contain remote resource URLs and make network requests when enabled. Use book JavaScript, external links and webpage content only from trusted sources.

## Optional WeRead metadata

Appearance → Link WeRead is off by default and uses your own official API Key. Searches send the title/author query; detail, review and highlight requests send the confirmed WeRead book ID to the official gateway. Cover requests use WeRead's CDN. These services receive normal network metadata, not your local book contents, notes or personal reviews. Replacing a local cover or description requires confirmation.

Links and loaded public metadata are cached locally and can sync as separate book sidecars only for downloaded originals. The enable switch stays device-local. The API Key is stored in private application preferences and excluded from book sidecars and logs. It transfers only when credentials are explicitly included in global settings exports (recoverable plaintext) or through the existing encrypted sensitive-settings sync with its independent password. See [WeRead details](docs/WEREAD.md). Disabling queries does not erase existing caches or previously synced credentials.

Current-page reflow translation sends the current page's corrected text, or recognized text when no correction exists, to the selected translation service. It does not request translation of the entire book.

## AI, translation, search and narration

In unified lookup, opening Overview automatically queries its enabled dictionary, encyclopedia, translation and AI knowledge sections. Dictionary network sources remain individually opt-in. Wikipedia receives only the query; translation and AI receive selected text and, when enabled, its context using your configured services. AI auto-send is enabled by default and can incur provider charges; enable **Edit AI questions before sending** for manual sending or disable individual Overview sources. Existing explicit manual-send choices are retained. Book AI and web search are not automatically requested by Overview.

Remote AI receives the actual prompt, conversation history and selected text, chapters or retrieved passages needed for the task. Selection templates default to text with context; you may choose selected text only. Explicit scope choices are preserved. Reading skills and app tools supply different source scopes for their tasks. Editing a prompt does not automatically send the whole book.

AI Knowledge uses the current model's existing knowledge first. Enabling a template's online option or choosing **Online search** beneath an answer queries Wiktionary, Wikipedia and Baidu Baike. Those sites receive the search term; retrieved results are sent to the same AI model for a sourced summary. No separate search API key is required. Context chosen for the template can still enter the AI request.

Selection search, custom search engines and Baidu / Youdao webpage translation send query or translation text to their respective sites. Embedded WebViews and external browsers use the system network environment; sites may use cookies and other browser data under their own policies.

Google, DeepL / DeepLX and AI translation receive text to translate. Inline full-text translation likewise sends the paragraphs being translated. Edge TTS and online speech services receive narration text and relevant voice/style instructions. Whether system speech uses a network depends on the chosen system engine. Ensure you are entitled to send the content and understand the provider's retention, pricing and privacy rules.

## Model and font downloads

Embedding and OCR weights are not bundled. Users download pinned files on demand from upstream or Gitee. Embedding models and OCR v4 / v3 use Hugging Face upstream; OCR v5 uses ModelScope. Downloads consume data and expose requests/IP addresses to the service and its download infrastructure, but do not include books, prompts, API keys or Gitee login credentials.

Files must pass size and SHA-256 checks. Starting the app or indexing does not silently download missing models or change your selected source. Prepared local OCR and embeddings do not need to upload book text. Remote embeddings APIs receive indexing passages and retrieval queries. Even with local embeddings, passages subsequently supplied to remote chat AI leave the device.

Font downloads contact the font service, currently including fonts.anxcye.com. Importing a local font does not send its file to that service.

## Update checks and downloads

Startup and manual checks share a source selector, initially GitHub. When GitHub is temporarily unavailable, a check can fall back to Gitee and change the subsequent download source with it. Check again after manually changing sources. Services receive IP addresses, normal request metadata and a fixed Modu-Updater identifier, not books, notes, account secrets or unique device identifiers. Failed checks do not interrupt reading.

Packages download only after your request. Except for macOS browser downloads, in-app downloads require matching size and SHA-256 checks. Android also checks package name, signature and version and requests system installation confirmation; it does not install silently. Modu cannot confirm completion or verification of a macOS browser download; compare the release checksum yourself.

## WebDAV and remote libraries

Object-storage sync is configured under **Settings → Sync**, separately from WebDAV. Selecting S3 / OSS / COS sends the same library-sync data to your chosen bucket, plus signed requests and temporary probe objects when testing. Endpoint, bucket, prefix and access credentials are stored in local preferences without additional encryption; default backups exclude the credentials. They are not included in AI-settings sync. No bucket is made public, no existing WebDAV configuration is replaced automatically, and switching does not transfer data between providers. Use private buckets, scoped keys and HTTPS. See [object storage synchronization](docs/OBJECT_STORAGE_SYNC.md).

To reduce requests, the app stores request-budget timestamps, server cooldowns and maintenance schedules locally under hashed account filenames. These policy files contain no passwords, book text or full server URLs and are not library-synced. Jianguoyun request limits are per device/account; other devices and applications can still consume the same server quota.

WebDAV sync runs only after configuration and enablement. Your server receives synchronized books, covers, notes, bookmarks, folders, tags, positions and reading time. Records merge by stable identity and retain deletion markers. Fonts, backgrounds, device preferences and dictionaries are not library-synced. **Vector-index sync has been removed**; indexes and model files stay local.

**Sync API keys** is separate from the WebDAV master switch and off by default. It requires an independent password and encrypts sensitive service settings with AES-256-GCM. The password is not stored in sync data. This does not encrypt all books, notes or the whole database. Disabling the switch does not automatically destroy old cloud data, backups or copies on other devices. Lost passwords cannot recover protected keys.

**Remote library** offers a separate WebDAV connection for browsing/downloading and does not modify that server's library files. Its URL, username and password are kept in local preferences without additional encryption; protect access to your device. With key sync enabled, library configuration can be encrypted using the same independent sync password. Clearing a connection can propagate configuration removal, not book deletion; an unconfigured new device does not proactively clear cloud configuration.

Baidu Netdisk is connected only at the user's request through Baidu's official authorization page; Modu does not receive the Baidu password. The client requests selected directories, file information and book downloads directly from Baidu, without uploading, deleting or modifying Netdisk files. Authorization requests pass through Cloudflare to an AWS Singapore service for code exchange and token refresh; book files do not pass through this service. The service encrypts tokens with AES-GCM and stores hashed device-session identifiers. The client keeps its device session in secure storage and access tokens in memory, outside library sync and settings backups. Authorization tickets expire after five minutes; device sessions expire after 30 days and renew on successful token refresh. Expired records are cleaned during subsequent requests. Disconnecting deletes that device's server session and tokens but keeps downloaded books. The service does not log authorization codes, tokens, request bodies or query strings; Cloudflare and AWS process connection metadata under their own service policies.

Use HTTPS. Basic authentication is not transport encryption; explicitly choosing HTTP risks interception of credentials and content.

## Settings transfer and database backups

**Global settings backup** excludes accounts, passwords and API keys by default. Opting in produces JSON files or modu links containing **recoverable plaintext credentials**, not encrypted backups. The sync encryption password is never exported. Review the import scope; with credentials excluded, existing local credentials are preserved. Import does not automatically connect to a remote library.

Global settings include custom CSS, URLs and prompts, which can contain information you entered; do not embed secrets in them. Only edits to built-in prompts and custom templates are stored, not duplicate defaults. Settings transfer excludes books, notes, AI history, dictionaries and font/background/model files. There is no QR transfer.

Database ZIP backups include locally available books, covers, notes, reading records, fonts, backgrounds, AI history and general settings. Service configuration is excluded by default. If included, AES-256-GCM protects the settings section, **not the whole ZIP, books, notes or chats**. Restore replaces the library rather than merging it. Keep files/passwords private; do not publish settings links, backups or logs.

ANX Reader backup import validates and merges supported books/records locally. It does not inspect another app's private database or import ANX accounts, keys or app configuration. Protect the local pre-import database snapshot too.

## Diagnostics and issue reports

Platforms retain limited local diagnostics: the latest 16 entries, approximately 30 KB maximum. These contain exception type, app code location, version, time and indexing phase/counts, not exception messages, titles, book text, user file paths, keys or accounts. They are not WebDAV-synced.

Bug reports exclude crash diagnostics by default. Opting in allows you to preview local records and available platform-native summaries, not raw memory dumps:

- **Android:** system exit reasons, memory samples and fault-thread summaries.
- **iOS / macOS:** Apple MetricKit diagnostics, with at most three additional sanitized summaries and a 32 KB size limit.
- **Windows:** one small stack summary for an unhandled native exception, recovered on the next launch; no minidump is generated.
- **Linux:** only after opt-in, coredumpctl info reads the latest record for this app from the last seven days, with a 256 KiB read cap and five-second timeout. Only signals and stack offsets are extracted. No debugger, core extraction, scanning of other apps, enabling system dumps or administrator request occurs. Raw system output is neither saved nor included in reports.

Native summaries contain numeric error codes, available times/versions and up to 32 frames of public module names, module-relative offsets and binary version identifiers. They exclude device UUIDs, arbitrary function names, exception payload text, registers and memory. Apple reports may arrive late; Linux depends on system configuration, retention and permissions. Force-stops, resource exhaustion or damaged stacks may leave no record. An unconfirmed previous session does not prove a crash; a missing record does not prove the absence of one. Modu does not change operating-system diagnostic retention settings.

Optional environment details contain available OS version, model, architecture, memory and app version, not device/host names, serial numbers, IMEI, Android ID, hardware UUID or system product ID.

**Preview and submit** shows the complete report, copies it after confirmation and lets you paste it into GitHub yourself. You can also choose Copy report. Diagnostics are not automatically uploaded or embedded in URLs. **GitHub issues are public, and other apps may read the clipboard.** Review the report again before submission.

[Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)
