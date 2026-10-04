# Android app data directory migration

> Historical record of the source changes and local checks described below. No release version was specified; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

The default Android data root used `getExternalStorageDirectory()`, typically
`内部存储/Android/data/com.modu.reader/files` (“Internal storage/Android/data/com.modu.reader/files”). No shared user directory was added and
`内部存储/Fonts` (“Internal storage/Fonts”) was not scanned. Existing font import/download methods were unchanged, with fonts still under `font/` in the data root.

On first launch, migration ran before database opening, WebDAV synchronization, the reader and TTS:

- All data from the old `app_flutter`: books, covers, fonts, backgrounds, AI history, indexes, models, dictionaries and more.
- The old private `databases` directory, including database WAL/SHM files, moved to `databases/` under the new root.
- Each file was verified with streaming SHA-256; temporary files were renamed into place only after completion.
- Same-name files with different contents stopped migration without overwriting either side. Insufficient space or interruption could be retried, reusing verified files.
- App startup continued only after migration receipts were written at both ends. The old database was no longer read afterward. If the new directory was lost, startup stopped and prompted a retry rather than silently reverting to old progress or creating an empty library.
- Original private data was retained temporarily as a one-time recovery copy, with no further writes or automatic cleanup.

System SharedPreferences, keys, security settings, crash diagnostics and caches remained in Android-managed private storage. Migration did not provide root-free access to all settings. Settings → Storage displayed the app data root.
Android/data could still be restricted by the system/file manager; this change neither bypassed system permissions nor added storage permissions. Uninstalling the app deletes its app-specific directories; backups should continue to use the app's export feature.

Automated tests covered migration, restart, interrupted recovery, conflicts, missing destinations, symbolic links and unavailable platform directories. Real SQLite WAL tests verified preservation of notes and reading positions. Android device upgrade verification was still required before release, including existing libraries/models, custom-font reading, export/restore, WebDAV sync and retries after insufficient space.

## Local verification in this round

- Migration, startup error page, database initialization, backup, fonts and AI history storage: 48 passed, 1 private-font sample test skipped.
- Sync and model storage/deletion regressions: 268 passed, 1 skipped.
- Android ARM64 `flutter build bundle --debug --no-pub` succeeded. This was Dart/asset compilation, not a complete APK build or device upgrade verification. No app was installed or published and no real user data was migrated in this round.
- Dart analysis reported no compilation errors in the changed code. The environment's custom_lint plugin still failed to run with `pub is not an AOT snapshot`; this was not a complete passing lint check.
