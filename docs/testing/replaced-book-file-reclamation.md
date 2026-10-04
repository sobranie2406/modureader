# WebDAV file reclamation after book replacement

> Historical record of the 2026-09-16 verification and 2026-09-20 added regressions described below. No release version was specified; this is not certification of the latest 1.2.0 release. See the [documentation index](../README.md).

## Behavior

- `BookDao.updateBook` recorded the old path, old MD5 and stable book identifier in the same SQLite transaction that updated the file path. Reading progress and notes were unchanged.
- Reclamation ran after normal database merge, publication and book-file synchronization. It could not be placed in `syncFiles`, which was also called before database publication. Vector-index synchronization had been removed and no longer affected EPUB reclamation.
- Only book files with explicit replacement records were processed. The latest merged local and remote records, including immutable logs used by servers without reliable ETag, protected all still-referenced files, including books in the recycle bin.
- The remote new EPUB's MD5 and old file's MD5 had to be verified, and the recovery copy of the old file read back and checked. After slow transfers, all book references and delete/restore records were rechecked; relevant changes deferred reclamation. Unrelated note, reading-position or duration changes no longer caused indefinite deferral.
- Missing local evidence could be recovered from remote immutable logs that passed hash and database-format validation. Only historical records with the same stable book identifier, an earlier operation clock, a different path and a valid MD5 were accepted. Evidence was saved only after a successful full scan, followed by validation of the latest references on both sides and file contents. Replacement relationships were not guessed from directory filenames or sizes; old files with no trustworthy historical records were retained.
- Old files moved out of `modu/data/file`; recovery copies were stored at `modu/replaced-files-v1/<旧路径SHA256>/<内容SHA256>/<原文件名>` (placeholders: old-path SHA256, content SHA256, original filename). For recovery, copy that file back to `modu/data/file/<原文件名>` (original filename).
- This was **recoverable reclamation, not permanent deletion, and did not free the remote space occupied by recovery copies**. Older clients had no reclamation acknowledgement protocol, and database checks and file deletion were not atomic across files. Recovery copies were therefore retained; last-moment concurrent references could not be ruled out.
- Historical files of unproven origin were not cleaned up, and ownership was not guessed from matching book titles. Records lacking valid MD5, with unknown file size or with files larger than 512 MiB were skipped. Each sync attempted at most 3 eligible files; later syncs continued the work.
- Local replacement evidence was retained for offline retries, switching sync targets and handling offline devices reuploading old files. These local maintenance tables were not added to the cross-device sync format.
- Reclamation failure did not fail completed book/note synchronization; later syncs could retry.

## Regressions

`test/service/sync/replaced_book_files_test.dart` used real temporary SQLite and in-memory WebDAV, covering reliable ETag / no ETag, successive replacements, unpublished changes, missing/corrupt new files, references from other books, corrupt recovery copies, delete-failure retries, concurrent modification, transaction rollback, actual DAO integration, path restrictions and old-file reuploads.

`test/service/sync/webdav_capabilities_test.dart` used a local HTTP server and additionally covered exact deletion of filenames containing Chinese characters, spaces, `#`, `%` and literal `%2F`, preventing filenames from being interpreted as URL fragments or directories.

Added regressions (2026-09-20): successive replacements unrecorded by older versions and another device recovering evidence from remote logs; completion despite new notes/progress updates during reclamation; blocking reclamation on new local references, remote restoration of an old file or deletion of the current book; and ensuring index-sync calls did not precede reclamation.

No real WebDAV connection was used, existing historical files were not migrated, and no package was built or published in this round.

Verification results (2026-09-16): full Flutter suite 707 passed, 5 skipped; local HTTP WebDAV tests 15 passed. The additional custom_lint static-analysis plugin could not complete because dependencies were unavailable; this was not recorded as complete static-analysis success.
