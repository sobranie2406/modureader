# Dictionaries: local and optional online lookup

Source-reviewed for Modu 1.2.5+10102 on 2026-10-10 ([v1.2.5](https://github.com/sobranie2406/modureader/tree/v1.2.5)). Detailed workflows and current boundaries: [English](FEATURES.md) · [简体中文](FEATURES_zh.md). See the [documentation index](README.md) and [settings guide](SETTINGS.md).

Includes the inline original dictionary and optional online lookup changes.

## Usage

1. Open **Settings → Custom dictionaries → Import dictionary**. Modu bundles no dictionary data; import files you are entitled to use.
2. Import one dictionary at a time and give it a custom name. Keep multiple dictionaries and rename, enable/disable or remove them in settings.
3. Select text while reading and choose **Dictionary**. By default, the dialog queries all enabled local dictionaries, ignoring leading/trailing spaces and letter case. **Query dictionaries (one or more)** lets you select one or several dictionaries and remembers your choice by dictionary ID, even when names match. You can edit the query. A missing match does not automatically trigger online translation.
4. Lookup keeps your reading position; closing the dialog restores reader focus.

Each dictionary returns at most 20 entries with the same lookup key per query. Redirect lookup visits at most eight targets to bound malicious or cyclic links.

Each result includes its dictionary name beneath the definition. Local results are labeled **Imported locally**; this identifies the imported dictionary, not independently verified publisher attribution.

## Optional free online sources

Enable sources in the lookup dialog or **Settings → Custom dictionaries → Query sources / online dictionaries**. No API key is required. Online lookup is off by default and sends only the query, not additional book context or book files. Sources run independently; an unavailable online source does not hide local results.

| Source | Content and attribution |
| --- | --- |
| Chinese / English Wiktionary | Text definitions extracted using the [MediaWiki API](https://www.mediawiki.org/wiki/API:Parsing_wikitext), with original revision/contributor and CC BY-SA 4.0 links. |

Only definition excerpts are displayed; remote HTML is never executed and examples, images and audio are not loaded. Follow the original-entry link for the full page. Services may be inaccessible or rate-limited on some networks. Requests have a 15-second overall timeout and a 2 MiB response limit, with no automatic retries. Up to 32 successful query results are cached in memory while the lookup window remains open. Query selections and online opt-in are device-local and excluded from settings backups/transfer.

## Formats

| Format | Import method and limits |
| --- | --- |
| MDX | 1.x / 2.x, uncompressed or zlib; UTF-8 and UTF-16 supported. Other encodings depend on the parser library and have not each been verified. Supports `@@@LINK=` redirects with loop protection. Maximum file size: 256 MiB. |
| StarDict | 2.4.2 / 3.0.0. Select matching `.ifo`, `.idx` / `.idx.gz`, `.dict` / `.dict.dz` and optional `.syn` files together. Supports 32/64-bit offsets, synonyms and multi-field text definitions. |
| ZIP | One dictionary in either format above, optionally in subdirectories. Supports Store/Deflate; rejects encrypted ZIPs, out-of-root paths, symbolic links and duplicate companion filenames. Extracts in chunks and checks actual sizes and CRCs. |

Text lookup converts HTML/XML to text with paragraph separation. Newly imported
MDX dictionaries also retain their original HTML, displayed directly inside
the result card in a sandboxed view with local CSS, JavaScript-generated
content, images and audio. Height adapts to content; entries exceeding 8,000
logical pixels scroll inside the card to bound native surface size. Failed
loads fall back to text. It has no app bridge or file access, blocks external
network content/popups, and requires a user gesture for audio playback.

Import a matching `name.mdd` (or numbered `name.1.mdd` parts) with the MDX, or
select loose companion resources. Use a ZIP when resources use subdirectories;
the relative paths are preserved. Supported resources: PNG/JPEG/GIF/WebP/SVG,
MP3/WAV/OGG/M4A/AAC, CSS/JS and WOFF/WOFF2/TTF. Actual media codecs depend on
the platform WebView. Missing companion resources cannot be reconstructed.
Old text-only imports remain readable and must be reimported to recover HTML
and media; no original user files are modified. Importing again creates a new
dictionary; remove the older imported copy only after verifying the new one.

Local definitions are not summarized or shortened by character count: textual
senses and examples are retained, within the import size limits below. Text-only
results collapse redundant blank lines; original results use compact outer
spacing without repeating the whole text definition. The excerpt/omitted-examples notice
on online results applies to Wiktionary, not local dictionaries.

DSL, MDX/MDD 3, LZO compression and encrypted record blocks are unsupported;
not every commercial dictionary is guaranteed to import. StarDict remains
text-only. Scripts requiring network requests, evaluation via `eval`, storage,
frames, application-specific APIs or cross-entry navigation are not supported.

The MDX parser dependency does not currently validate internal checksums. A successful import is not publisher-certified integrity verification.

## Storage and reliability

- Dictionary parsing, decompression and SQLite indexing run in a separate Dart isolate, not the Flutter UI thread.
- Entries, normalized lookup keys, text/MDX HTML and companion resources are stored in separate local SQLite files. Queries do not reload the original dictionary or depend on its original path.
- Imported data lives in `dictionaries/` under app storage. It is excluded from the book database, settings backups and WebDAV sync.
- Dictionary names are database fields, not file paths. Removing a dictionary deletes only Modu's imported copy, not the original file.
- Import builds in a temporary `.import-*` directory and publishes atomically after validation. Errors roll back and clean the temporary directory while preserving existing dictionaries. Forced process termination can leave a temporary directory but cannot publish an incomplete dictionary as usable.
- StarDict validates companion files, entry counts, index length, record offsets, synonym targets and field boundaries.
- Limits: 2 MiB per definition; 64 MiB for the StarDict index; 2 GiB for imported text/HTML/resources combined; two million entries; 256 MiB per MDD; 32 MiB per resource; 100,000 retained resources; 512 MiB for a ZIP; 2 GiB of extracted dictionary files. Extra temporary disk space is required.
- Failure messages show an error category, not raw dictionary text, paths or parser exception details.

## Verification scope

Existing automated tests use small self-generated dictionaries, without bundling or redistributing commercial dictionaries. Coverage includes MDX 1/2, UTF-8/UTF-16, zlib and redirect loops; StarDict text/compression/64-bit offsets/synonyms; ZIP; failed-import rollback; path validation; enable/disable/rename/delete; and mobile/desktop lookup dialogs.

The 2026-10-10 development checks reran dictionary service and widget tests, including single/multiple selection, duplicate names, source attribution, license validation, request cancellation and online failures with local results preserved. Earlier smoke tests covered the online sources available at that time. Free Dictionary API has since been removed; only Chinese and English Wiktionary remain. These checks do not establish compatibility with every dictionary variant or device; no physical-device or large user-dictionary testing was performed for this change.

## Implementation sources

- MDX: [dict_reader](https://github.com/mumu-lhl/dict_reader), pinned to 1.6.1 (MIT). Transitive cryptographic utilities only decode the format; they do not provide a blockchain/network service. Flutter includes dependency licenses in its license registry.
- StarDict: implemented against the [official file-format specification](https://github.com/huzheng001/stardict-3/blob/master/dict/doc/StarDictFileFormat).
- Archives use the existing `archive` dependency; local databases use the existing native SQLite runtime.
- Modu's [local dictionary service](../lib/service/dictionary/local_dictionary.dart).
