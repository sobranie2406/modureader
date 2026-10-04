# Import an ANX Reader backup

Current guide for Modu 1.2.0+10082. See the [documentation index](README.md) and [settings guide](SETTINGS.md).

Open **Settings → Advanced → Import ANX Reader backup**. All clients select a ZIP file. Modu does not scan another app's private database directory or request cross-app file-access permissions. This migration entry is separate from the top-level **Settings → Global settings backup**.

## Steps

1. Download the books you want to migrate in ANX Reader, stop reading and wait for synchronization to finish.
2. In ANX Reader, export a complete ZIP through **Settings → Sync → Export and import → Export**. Names may differ by ANX version.
3. Save the ZIP on the device running Modu; do not extract or modify it.
4. Select it in Modu and review the importable book/note counts and warnings about missing book files or deleted books.
5. Choose **Start import**. Modu automatically creates a complete snapshot of its current database before importing. The success page provides a copyable backup path.

## Scope and limits

- Imports downloaded books and covers, notes/highlights, reading positions, reading time, folders and tags.
- Excludes deleted books and books whose content files are missing, along with their notes/reading time. Missing books are listed by title; download them in ANX and export a new complete backup.
- Does not import app settings, account passwords, API keys, sync configuration, AI chats or standalone fonts/themes/backgrounds. Embedded resources stay in the original book files. The ZIP may contain sensitive settings; keep it private.
- Accepts original ANX database schema 7 (not the app version number), in ZIP only. Standalone DB files, encrypted ZIPs, unknown schemas, unknown triggers and Modu databases are rejected.
- Reimporting the same backup does not duplicate matching records. Books merge by actual file MD5, not title. Matching books keep Modu's current progress and folder; existing note edits/deletion states take priority. This is a one-time migration entry, not cross-app two-way synchronization. Reimport does not overwrite existing Modu records.
- Extraction and validation occur in a temporary directory. Each database/WAL file is limited to 256 MiB; each table read is limited to 200,000 rows; ZIP expansion is limited to 20 GiB and 100,000 entries. Allow space for extraction, file copies and the current database snapshot.
- The safety snapshot requires SQLite `VACUUM INTO`. If an old system lacks support or storage is insufficient, import stops rather than overwriting the original database. Validation/merge failure does not replace the current database. Keep the app open during import.
- Recovery snapshots are stored in Modu's data directory at `import-backups/before-anx-<unique-id>.db`. Existing book files are not overwritten; the SQLite merge runs in one transaction. A snapshot does not automatically roll back remote WebDAV data.

## Source references

The original source review was dated **2026-09-28**, against the official `Anxcye/anx-reader` `develop` branch. These moving upstream links describe that review; this documentation update did not repeat the upstream review.

- [Backup export and ZIP layout](https://github.com/Anxcye/anx-reader/blob/develop/lib/page/settings_page/sync.dart): `databases/app_database.db`, `file/`, `cover/`, `font/`, `bgimg/` and settings JSON. That exporter can add the databases directory twice; import checks raw ZIP directory entries and rejects duplicate files with conflicting checksums/sizes.
- [Database structure and migrations](https://github.com/Anxcye/anx-reader/blob/develop/lib/dao/database.dart): schema 7 and tables for books, notes, reading time and groups.
- [Database directory](https://github.com/Anxcye/anx-reader/blob/develop/lib/utils/get_path/databases_path.dart) and [resource directory](https://github.com/Anxcye/anx-reader/blob/develop/lib/utils/get_path/get_base_path.dart): references for backup structure only; Modu does not use these paths to read another app's data.
- Modu's [import service](../lib/service/local_data/anx_database_import.dart) and [import page](../lib/page/settings_page/subpage/anx_backup_import_page.dart).

## Verification scope

`test/service/local_data/anx_database_import_test.dart` uses synthetic SQLite/ZIP fixtures covering new records, matching-book merges, repeated import, protection of current records, WAL, missing files, malicious paths, unknown versions/triggers and transaction-failure rollback.

`test/widgets/anx_backup_import_page_test.dart` covers the English/Chinese instructions, ZIP-only entry and import being unavailable before validation. These tests were not rerun for this documentation update.
