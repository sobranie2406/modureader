# WebDAV record-level merge synchronization

## Current: Modu 1.2.0+10082

This guide describes the stable Modu publishing repository's `v1.2.0` commit `77dc238fb2ae2ce02455bd80c500ee9fd140f219`, using sync-container format/database version 8. Uncommitted application changes are outside this baseline. Versioned milestones and test results below are historical, not new release acceptance; this documentation update ran no application, device or live WebDAV tests.

Books, notes, bookmarks, reading positions and reading-time records merge individually. Book metadata and covers sync first; missing book content downloads when opened, so a visible bookshelf entry is not proof of offline availability. Vector-index synchronization and its switch have been removed; local indexing, retrieval and Stop Vectorization remain available. Fonts, local rendering preferences, downloaded model weights and page reflow caches are not transported as record-database contents. OCR model/source choices may travel through global settings backup, without weights.

PDF/scanned-book controls are separate from ordinary text-book reading. Image-book classification for EPUB, MOBI, AZW3 and FB2 samples at most five body sections during import and saves a local result; remote-library import shares that path, and downloading a missing bookshelf file can populate classification locally. Opening an available book does not resample it. See [scanned-document status](SCANNED_DOCUMENT_DEVELOPMENT.md) and [local indexing](INDEX_SYNC_AND_READING_CONTROLS.md).

The original record-merge release was `1.0.2+10004`. Local `1.0.1+10002`/`10003` test builds already included it; the original GitHub `1.0.1+10001` installer did not. Those package distinctions are preserved as history.

## Merge behavior

The inherited whole-database timestamp/replace workflow was replaced with record-level merging. SQLite remains the cloud container, but only allowed synchronization records are transported; the complete application database is neither uploaded nor replaced.

| Content | Merge rule |
| --- | --- |
| Books | Stable identities link records; metadata follows operation time, preserving local integer IDs |
| Notes, bookmarks, highlights | Independent identities; operation time resolves the same record, and deletion retains tombstones |
| Reading position | Independent operation time; the latest reading action wins even when moving backward; title/rating edits do not change position |
| Book deletion/restoration | Independent lifecycle record; offline reading or metadata edits do not undo deletion, while explicit reimport can restore |
| New reading duration | Each reading session adds an independent event, deduplicated by identity and aggregated by existing statistics queries |
| Folders and tags | Sync identities link records; foreign keys map to each device's local IDs; font styles are not exported |
| AI settings and API keys | Existing separate opt-in AES-256-GCM encryption; disabled devices neither export local settings nor decrypt cloud ciphertext, but preserve ciphertext from other devices |
| Fonts, theme images, local preferences, vector indexes | Excluded from the record container; local font files/selections stay on each device; indexes are not separately transferred over WebDAV |

Equal timestamps are resolved deterministically using persistent random operation revisions. The local operation clock increases monotonically and absorbs observed remote clocks; devices should still use automatic system time.

## Migration and limits

1. Back up every device and the server's `modu` directory; pause old clients' sync.
2. Upgrade participating devices to versions supporting database 8. Keep the same WebDAV parent-directory setting without adding another `/modu`.
3. If `modu/database8.db` is absent, the new client reads `modu/database7.db`, migrates a temporary copy and merges it with local records before creating the new cloud container. The old file is neither overwritten nor deleted. On services without reliable conditional writes, migration uses the compatibility log described below.
4. Once the new container/log migration exists, the old file is not repeatedly imported. Old clients should no longer write the old database. Version checks stop older clients processing a higher database version, but cannot remotely cancel an upload already started by an old client.
5. Old databases lack original per-session reading events and complete deletion history. Legacy duration uses the larger same-book/same-day cumulative total from either side, then adds new post-upgrade events. It cannot precisely recover separate pre-upgrade increments embedded in those totals. Lost notes or deletion history cannot be invented.
6. Legacy books use existing file MD5 when available, otherwise the original relative book path. Shared legacy notes migrate using book identity, old ID, location and creation time; new notes use random stable IDs. Independently created notes without common history are not deleted or merged merely because their text matches.
7. A sync container is not a full backup that can overwrite local `app_database.db`. Database Backup Management keeps up to three full pre-merge local snapshots. Restoring an old backup does not undo updates on all devices; newer cloud records still participate in the next merge.

## Concurrency and failure protection

- Database-file reads keep file paths without a directory trailing slash.
- Only 404 means absent. Authentication, network, server and parsing failures stop sync rather than uploading an empty database.
- Remote metadata is checked around downloads. Reliable writes use strong-ETag `If-Match`; initial creation uses `If-None-Match: *`. A 412 triggers another download/merge, with at most three attempts, never an unconditional overwrite.
- Reliable servers use conditional requests; servers without reliable ETags use the record-log channel. Neither channel unconditionally overwrites an existing cloud database. Last-modified comparisons alone cannot provide atomic concurrency protection. See [RFC 9110 §13](https://www.rfc-editor.org/rfc/rfc9110.html#section-13).
- Sync does not close or replace the active local database. Merge runs in a SQLite transaction and rolls back on failure; local edits and their sync records commit together.
- New local operations during upload enter bounded retries. Persistent changes/contention preserve data and report retry later rather than success.
- Failed book/cover transfers prevent publication of a new database. Sync no longer deletes files simply because the current database does not reference them. Tombstones propagate deletion; automatic unreferenced-file collection is not implemented, to protect offline clients and concurrent uploads. Explicit book deletion still removes that device's local file.
- Identical records do not repeatedly upload a database or create needless backups.
- Metadata and covers sync; missing book content downloads on first opening.
- Empty libraries, databases and cover transfers do not force lookup of nonexistent books. Failed transfers clear in-progress state without marking success. Automatic sync refreshes the bookshelf without requiring a caller-provided UI reference.
- Containers allow only known fields and validate integrity, format version, relative paths and record types. The database limit is 64 MiB. Encrypting keys does not encrypt books, notes or the entire database.

## Historical: 1.0.4 startup recovery and ETag compatibility

- Automatic sync starts approximately two seconds after launch/foreground return, not when entering the background. Read-only connection preflight retries transient network errors within limits; persistent authentication rejection prompts for account/directory checks. Manual failures retain clear messages.
- When database PROPFIND lacks a strong ETag, HEAD checks the same file. The PROPFIND response's own ETag, weak ETags and dates are not substituted for a strong resource validator.
- Without a valid validator, the client rereads and merges within limits rather than overwriting unconditionally. Early packages stopped upload if absence persisted; later versions use the independent log channel below.
- Logs distinguish unchanged records/no upload from published database. Successful sync does not necessarily mean a database upload occurred.
- Read-only online checks verify authentication and metadata responses, not phone cold-start network recovery or actual conditional-write enforcement.

## Historical: 1.0.5 compatibility channel without reliable ETags

- Before a required upload, synthetic objects under `modu/.sync-probes/<random-id>/` test that ETags change with content, stale `If-Match` and repeated `If-None-Match: *` return 412, and rejected writes leave content unchanged. Probes do not use real databases and clean up their own files. Only unreliable results are cached for 30 seconds; conditional writes revalidate each required round instead of trusting a 15-minute-old success. Authentication/network/server failures are not evidence of unsupported conditions.
- Verified servers conditionally update `database8.db`. Missing, weak, unchanged ETags or ignored conditions select `modu/record-log-v1/<first-hash-digit>/<SHA-256>.db`. Changed allowlisted records form content-addressed files: concurrent writers use different names or identical bytes, avoiding a shared manifest/database race. There is no unconditional PUT fallback for `database8.db`.
- Every sync reads the shared database and compatibility logs using the same clocks, identities, tombstones and duration deduplication. Logs remain readable after ETag support recovers. Migration from `database7.db` writes the old data into the new channel once; the old file remains.
- Pending batches are persisted in the database directory, outside disposable caches and isolated by server/account, before upload. Uploaded bytes are downloaded and SHA-256-checked. Interrupted/restarted sync replays pending batches. Incomplete/corrupt remote files are not empty data and do not yield success. Corrupt files without another sender able to retransmit require recovery rather than blind deletion.
- Verified immutable batches are cached locally. Sixteen buckets and full pagination avoid repeated historical downloads. Pagination remains restricted to the original server/directory to prevent credential forwarding. A Jianguoyun listing of 750 items without next-page information stops rather than assuming completeness.
- Early versions retained all logs; the 2026-09-28 compaction milestone below replaced that policy while retaining tombstones. Limits remain 64 MiB per batch and 256 MiB/10,000 batches per scan. Do not manually empty the log directory.
- All participating devices must support this implementation; pause old automatic sync and back up first. Old clients do not understand logs and cannot guarantee complete mixed-version synchronization. Font sync is unnecessary; API keys and remote-library credentials still use their separate encrypted opt-in settings.
- This stage recorded only synthetic local database/HTTP regressions, without actual Jianguoyun writes or long-term multi-device acceptance. The previously stopped all-platform build did not contain this addition.

## Historical: two-mode log compaction (2026-09-28)

Mode is selected automatically by isolated strong-ETag/conditional-write checks, not merely by ETag presence.

1. Reliable ETag mode uses `database8.db` as the primary container. Compatibility logs are merged even without new local edits. After CAS publication and byte-for-byte download verification, only read logs covered by that database are deleted. If the database changes again before verification, cleanup is deferred. Compaction does not create another compatibility log.
2. Unreliable ETag mode does not overwrite `database8.db` unconditionally. At 64 or more read batches, records merge under the existing conflict rules into a content-addressed batch. Persist the pending output, upload, read back and verify SHA-256, then delete only the old read batches. Concurrent unread batches are excluded. Output above 64 MiB defers cleanup and keeps the originals.

Both modes retain identities, revisions, tombstones and deduplicated duration. They do not delete by age or remove books, covers, auxiliary system files, bucket directories or old databases. Offline clients can still read current state and deletions; compaction merges history rather than clearing records.

The complete batch-name set is checked before and after reading. A 404 or changed set during compaction causes up to three reread rounds; persistent changes stop sync rather than treating missing files as empty. Deletion targets only the verified read set, with at most four parallel requests. Cleanup failure does not undo successful data sync; logs record the deferral and later eligible sync retries.

Reliable mode still checks logs left by other or temporarily downgraded clients. Compaction reduces repeated opening of historical databases but does not eliminate directory requests. The first compaction must read old records, upload the merge and delete files individually; later sync receives the main performance benefit. Missing DELETE permission leaves redundant files.

Participants should upgrade together for reread protection. The recorded tests used isolated mock servers, not a live WebDAV account. Entry point: `test/service/sync/log_compaction_test.dart`, covering 700-batch merges, reliable-mode consolidation, offline deletion, concurrent additions/two-device compaction, read races, corrupt uploads, denied deletion and CAS conflicts.

## Historical implementation and verification entry points

### Second-resolution ETags and book identities (2026-09-28)

- Isolated probes perform four different equal-length writes within two seconds, reading back bytes and checking ETags each time. At least two writes fall in the same second, exposing size-plus-whole-second validators. Repeated ETags, mismatched bytes or inability to complete the window conservatively select logs; probes do not delay writes to make unreliable validators appear valid.
- Checked `database8.db` conditional writes remain preferred, with content-addressed logs/compaction as compatibility transport. No server-source changes or data clearing are required.
- Besides stable IDs, merge checks current content MD5. A matching path merges only when known MD5 values do not conflict. Identical titles or paths with different checksums do not identify the same book. An independently deleted duplicate does not delete another live book.
- A deterministic canonical identity is selected. Old identities redirect through reserved revision prefix `modu-book-alias-v1:` in `book`, `position` and `life` deletion records, without new database8 fields/record kinds. New clients redirect offline old identities before clock-based merge; old clients understand accompanying tombstones but do not perform the new duplicate detection. Upgrade together.
- Notes and duration keep independent records; book/tag references point to the retained local book. Progress/folders follow existing conflict rules. Duplicate rows are hidden, preserving files, covers and notes. Tombstones retain old paths to protect restorable content from file maintenance.
- Remote identity duplicates publish a repair even without manual book edits. Database merge, compaction and offline replay retain redirect evidence.
- Regression entry points: `test/service/sync/book_identity_merge_test.dart` and `test/service/sync/webdav_capabilities_test.dart`, using synthetic databases/local mock servers rather than a user's remote library.

### Long-lived reader protection (1.0.5)

- Locking, backgrounding and closing wait for actual reading operations to persist without refreshing operation time from a cached screen position. Real turns, chapter jumps and user scrolling save progress; layout restoration, font reflow and sync relocation are not new reading.
- The same database transaction checks the previously observed position version. If sync wrote a newer version, stale-page writes are rejected and the reader relocates from the database. Unchanged saves create no new version; intentional backward reading remains valid.
- Database sync completion, including successful merge followed by failed upload, refreshes open readers and note lists. Annotation refresh changes visual overlays without invoking bookmark deletion.
- Note editing retains a snapshot and checks for changes/deletion in the transaction. Conflicts preserve the draft and prompt rather than overwriting newer notes; changing highlight color/type does not restore stale excerpt text.
- `test/service/sync/suspended_reader_sync_diagnostic_test.dart` changed from failure reproduction to protective regressions for both transports. Script checks cover reading actions/annotation refresh, and widget checks cover note drafts. This stage used no real cloud books and performed no physical E-Ink acceptance.

Implementation and regression locations:

- `lib/service/sync/row_sync_store.dart`: stable IDs, transaction triggers, foreign-key mapping, allowlist and local merge.
- `lib/service/sync/row_sync_record.dart`: conflict resolution, deletion state and legacy duration.
- `lib/service/sync/row_sync_engine.dart`: legacy migration, containers and concurrency retries.
- `lib/providers/sync.dart`: automatic/manual sync entry points.
- `test/service/sync/row_sync_test.dart`: isolated databases, migration, deletion, deduplication and concurrency integration.
- `test/service/sync/webdav_error_test.dart`: real client against a local HTTP server for paths, errors and conditions.

## Historical local two-device acceptance (2026-09-10)

After explicit authorization and backups of computer/cloud databases, macOS ARM64 and HONOR Magic4 Pro (Android 15/API 35) synced through the existing WebDAV directory. Both used local `1.0.1+10002` startup-fix builds with API-key sync disabled.

- Fixed duplicate database opening caused by asynchronous DAO calls during migration: shared the initialization Future, moved old-cover repair after database opening and waited for base-directory initialization. Five initialization/migration regressions were added.
- Recorded full automated result: 380 passed, two skipped; 54 targeted initialization/sync tests passed. Automation did not establish physical-device validation of every feature.
- The phone received three bookshelf entries and could download/open the demonstration EPUB.
- Reading the demo backward from about 72% to 36% on the phone synchronized the same position to computer/cloud, confirming latest-action rather than furthest-progress resolution.
- The computer saved chapter 2 at about 72%; the phone received 72%, retained it across cold start and actually opened chapter 2.
- Two unchanged syncs left cloud ETag, modification time, content hash and duration unchanged.
- Only demo-book position and naturally accumulated reading time changed. No real content was deleted, real notes were not edited, simultaneous editing/offline contention was not tested, and iOS/other platforms were outside this acceptance.

Page ranges/percentages are recalculated for each layout: chapter 2 occupied one computer page and three phone pages. This check established matching sync records and the correct chapter, not identical in-page percentages across screens. Large-library performance, every server implementation and fine-grained in-page positioning still require independent verification.
