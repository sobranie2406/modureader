# Local custom dictionaries

Source-reviewed for Modu 1.2.3+10090 on 2026-10-08 ([b6bf820a](https://github.com/sobranie2406/modureader/tree/b6bf820a4a3fd5ee1f657c80c061f64349a1aedb)). Detailed workflows and current boundaries: [English](FEATURES.md) · [简体中文](FEATURES_zh.md). See the [documentation index](README.md) and [settings guide](SETTINGS.md).

## Usage

1. Open **Settings → Custom dictionaries → Import dictionary**. Modu bundles no dictionary data; import files you are entitled to use.
2. Import one dictionary at a time and give it a custom name. Keep multiple dictionaries and rename, enable/disable or remove them in settings.
3. Select text while reading and choose **Dictionary**. The dialog shows exact-word definitions from all enabled dictionaries, ignoring leading/trailing spaces and letter case. You can edit the query. A missing match does not automatically trigger online translation.
4. Lookup keeps your reading position; closing the dialog restores reader focus.

Each dictionary returns at most 20 entries with the same lookup key per query. Redirect lookup visits at most eight targets to bound malicious or cyclic links.

## Formats

| Format | Import method and limits |
| --- | --- |
| MDX | 1.x / 2.x, uncompressed or zlib; UTF-8 and UTF-16 supported. Other encodings depend on the parser library and have not each been verified. Supports `@@@LINK=` redirects with loop protection. Maximum file size: 256 MiB. |
| StarDict | 2.4.2 / 3.0.0. Select matching `.ifo`, `.idx` / `.idx.gz`, `.dict` / `.dict.dz` and optional `.syn` files together. Supports 32/64-bit offsets, synonyms and multi-field text definitions. |
| ZIP | One dictionary in either format above, optionally in subdirectories. Supports Store/Deflate; rejects encrypted ZIPs, out-of-root paths, symbolic links and duplicate companion filenames. Extracts in chunks and checks actual sizes and CRCs. |

Only text definitions are displayed. HTML/XML definitions are converted to text with paragraph separation. Lookup does not execute JavaScript or load web pages, external CSS, images or audio.

MDD multimedia, DSL, MDX 3, LZO compression and encrypted record blocks are unsupported; not every commercial MDX is guaranteed to import. StarDict audio/image fields and resource references are not shown. Media-only entries report that no text definition is available.

The MDX parser dependency does not currently validate internal checksums. A successful import is not publisher-certified integrity verification.

## Storage and reliability

- Dictionary parsing, decompression and SQLite indexing run in a separate Dart isolate, not the Flutter UI thread.
- Entries, normalized lookup keys and text definitions are stored in separate local SQLite files. Queries do not reload the original dictionary or depend on its original path.
- Imported data lives in `dictionaries/` under app storage. It is excluded from the book database, settings backups and WebDAV sync.
- Dictionary names are database fields, not file paths. Removing a dictionary deletes only Modu's imported copy, not the original file.
- Import builds in a temporary `.import-*` directory and publishes atomically after validation. Errors roll back and clean the temporary directory while preserving existing dictionaries. Forced process termination can leave a temporary directory but cannot publish an incomplete dictionary as usable.
- StarDict validates companion files, entry counts, index length, record offsets, synonym targets and field boundaries.
- Limits: 2 MiB per definition; 64 MiB for the StarDict index; 2 GiB for dictionary content/imported definitions; two million entries; 512 MiB for a ZIP; 2 GiB of extracted dictionary files. Extra temporary disk space is required.
- Failure messages show an error category, not raw dictionary text, paths or parser exception details.

## Verification scope

Existing automated tests use small self-generated dictionaries, without bundling or redistributing commercial dictionaries. Coverage includes MDX 1/2, UTF-8/UTF-16, zlib and redirect loops; StarDict text/compression/64-bit offsets/synonyms; ZIP; failed-import rollback; path validation; enable/disable/rename/delete; and mobile/desktop lookup dialogs.

The original verification did not test actual large user-provided dictionaries or imports on mobile devices. Passing tests do not establish compatibility with every format variant or device. This documentation update did not rerun tests or perform those device checks.

## Implementation sources

- MDX: [dict_reader](https://github.com/mumu-lhl/dict_reader), pinned to 1.6.1 (MIT). Transitive cryptographic utilities only decode the format; they do not provide a blockchain/network service. Flutter includes dependency licenses in its license registry.
- StarDict: implemented against the [official file-format specification](https://github.com/huzheng001/stardict-3/blob/master/dict/doc/StarDictFileFormat).
- Archives use the existing `archive` dependency; local databases use the existing native SQLite runtime.
- Modu's [local dictionary service](../lib/service/dictionary/local_dictionary.dart).
