import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:anx_reader/service/sync/immutable_sync_log.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:anx_reader/utils/log/common.dart';

/// A clean SQLite transport: only portable records and opaque encrypted AI
/// settings. Never ships local paths, fonts, indexes, or the entire app DB.
class RowSyncArchive {
  static const format = 1;

  /// Transport schema version. v9 adds `time.round`, `round` and `review` kinds.
  ///
  /// The remote file name intentionally stays `database8.db`: old clients must
  /// READ the new archive and stop with "不支持的同步数据库版本" instead of
  /// silently creating a second, diverging archive under a new name.
  static const databaseVersion = 9;
  static const legacyVersion = 8;

  static Future<void> write(String path, List<RowSyncRecord> records,
          {Directory? databaseDirectory}) =>
      _withDatabasePath(path,
          writing: true,
          databaseDirectory: databaseDirectory,
          action: (local) => _write(local, records));

  // OHOS sqflite resolves customDir relative to its database root, not the
  // supplied cache path. Keep portable archives separate from the live library.
  static Future<T> _withDatabasePath<T>(String path,
      {required bool writing,
      required Future<T> Function(String) action,
      Directory? databaseDirectory}) async {
    databaseDirectory ??=
        AnxPlatform.isOhos ? Directory(await getDatabasesPath()) : null;
    if (databaseDirectory == null) return action(path);
    final temporary = await databaseDirectory.createTemp('modu-sync-archive-');
    // The pinned OHOS plugin also keys open handles by basename, not full path.
    final local =
        File(p.join(temporary.path, '${p.basename(temporary.path)}.db'));
    try {
      if (!writing) await File(path).copy(local.path);
      final result = await action(local.path);
      // action closes the database before the standalone transport is copied.
      if (writing) await local.copy(path);
      return result;
    } finally {
      await temporary.delete(recursive: true);
    }
  }

  static Future<void> _write(String path, List<RowSyncRecord> records) async {
    final db = await openDatabase(path, singleInstance: false);
    try {
      await db.transaction((txn) async {
        await txn.execute(
            'CREATE TABLE modu_sync_manifest (format INTEGER NOT NULL)');
        await txn.insert('modu_sync_manifest', {'format': format});
        await txn.execute('''CREATE TABLE $syncRecordsTable (
          kind TEXT NOT NULL, sync_id TEXT NOT NULL, clock INTEGER NOT NULL,
          revision TEXT NOT NULL, deleted INTEGER NOT NULL, payload TEXT NOT NULL,
          narration TEXT,
          PRIMARY KEY(kind,sync_id))''');
        for (final raw in records) {
          final record = normalizeSyncReadingPosition(raw);
          RowSyncStore.validate(record);
          await txn.insert(syncRecordsTable, record.toMap());
        }
        await txn.execute('PRAGMA user_version = $databaseVersion');
      });
    } finally {
      await db.close();
    }
  }

  static Future<List<RowSyncRecord>> read(String path,
      {bool legacy = false, Directory? databaseDirectory}) async {    // A bounded metadata-only database; an oversized/corrupt download cannot
    // be mistaken for an empty cloud library.
    if (await File(path).length() > 64 * 1024 * 1024) {
      throw const FormatException('同步数据库超过 64 MiB 安全限制');
    }
    return _withDatabasePath(path,
        writing: false,
        databaseDirectory: databaseDirectory,
        action: (local) => _read(local, legacy: legacy));
  }

  static Future<int?> versionOf(String path) async {
    int? version;
    try {
      // OHOS resolves database paths relative to its own root; reuse the same
      // copy-to-temp path as read() instead of opening the staging file directly.
      await _withDatabasePath(path, writing: false, action: (local) async {
        final db = await openDatabase(local, readOnly: true,
            singleInstance: false);
        try {
          version = await db.getVersion();
        } finally {
          await db.close();
        }
      });
    } catch (_) {
      // Corrupt/truncated cloud files are handled by read() (integrity check),
      // which produces the user-facing "同步数据库校验失败" path. The probe must
      // never turn them into an untyped database exception.
      return null;
    }
    return version;
  }

  static Future<List<RowSyncRecord>> _read(String path,
      {required bool legacy}) async {
    var db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.single.values.single != 'ok') {
        throw const FormatException('同步数据库校验失败');
      }
      final version = await db.getVersion();
      if (legacy) {
        if (version != 7) throw const FormatException('旧同步数据库版本不是 7，请先升级旧客户端');
        final triggers = await db
            .rawQuery("SELECT name FROM sqlite_master WHERE type='trigger'");
        if (triggers.isNotEmpty) {
          throw const FormatException('旧同步数据库包含未知触发器，已停止迁移');
        }
        // This is a disposable download, never the live library or server DB.
        await db.close();
        db = await openDatabase(path, singleInstance: false);
        await db.transaction((txn) => RowSyncStore.install(txn));
        return await RowSyncStore(db).snapshot();
      }
      if (version != databaseVersion) {
        if (version != legacyVersion) {
          throw const FormatException('不支持的同步数据库版本');
        }
        // v8 has no round records and its time payloads have no `round`.
        // RowSyncRecord.fromMap() defaults time.round to 1, so the read is a
        // pure in-memory upgrade; the caller decides when to publish v9.
      }
      final manifest = await db.query('modu_sync_manifest');
      if (manifest.length != 1 || manifest.single['format'] != format) {
        throw const FormatException('不支持的逐条同步格式');
      }
      final result = (await db.query(syncRecordsTable))
          .map(RowSyncRecord.fromMap)
          .toList();
      for (final r in result) {
        RowSyncStore.validate(r);
      }
      return result;
    } finally {
      await db.close();
    }
  }
}

enum RowSyncOutcome { unchanged, published, publishedWithPendingChanges }

class RowSyncEngine {
  RowSyncEngine(
      {required this.store,
      required this.client,
      required this.cache,
      this.durableDirectory,
      this.beforePublish,
      this.beforeMerge,
      this.afterMerge,
      this.maxAttempts = 3,
      this.validatorRetryDelay = const Duration(seconds: 1)});
  final RowSyncStore store;
  final SyncClientBase client;
  final Directory cache;
  final Directory? durableDirectory;
  final Future<void> Function()? beforePublish;
  final Future<void> Function()? beforeMerge;
  final Future<void> Function()? afterMerge;
  final int maxAttempts;
  final Duration validatorRetryDelay;
  static final remotePath = SyncPaths.database('database8.db');

  /// Read-only version gate executed before assets/logs are touched.
  ///
  /// Corrupt files return `null` and are handled by the integrity check in
  /// [RowSyncArchive.read]. Only a *newer* transport version aborts here.
  Future<void> _preflightRemoteVersion(Directory staging) async {
    final metadata = await client.readProps(remotePath);
    if (metadata == null) return;
    if ((metadata.size ?? 0) > 64 * 1024 * 1024) {
      throw const FormatException('同步数据库过大，已停止下载');
    }
    final download = '${staging.path}/preflight-archive.db';
    await client.downloadFile(remotePath, download);
    final version = await RowSyncArchive.versionOf(download);
    if (version != null && version > RowSyncArchive.databaseVersion) {
      throw FormatException(
          '云端同步数据版本过新（v$version），本机未做任何写入；请升级本机客户端');
    }
  }

  /// Keep the pre-v9 bytes before the first v9 publish. The name is stable
  /// (`database8.db`) so old clients fail closed instead of forking the cloud.
  Future<void> _keepLegacyArchiveBackup(String source, int attempt) async {
    final directory = durableDirectory ?? cache;
    await directory.create(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final target =
        p.join(directory.path, 'sync-v8-backup-$stamp-$attempt.db');
    await File(source).copy(target);
    AnxLog.info('Sync: pre-v9 remote archive backup kept at $target');
  }

  Future<RowSyncOutcome> synchronize() async {
    final staging = await cache.createTemp('modu-row-sync-');
    var backedUp = false;
    var published = false;
    bool? atomicSupport;
    try {
      final log = ImmutableSyncLog(client, staging, cache,
          durableDirectory: durableDirectory ?? cache);
      Future<RowSyncOutcome> finish(RowSyncOutcome outcome,
          {String? checkpoint}) async {
        // Maintenance is best-effort AFTER data synchronization. Upload/read-
        // back failure leaves every old input intact; DELETE failure leaves a
        // valid successor plus redundant inputs, never missing records.
        try {
          var removed = 0;
          if (checkpoint != null && log.hasReadBatches) {
            final verified = File('${staging.path}/verified-checkpoint.db');
            await client.downloadFile(remotePath, verified.path);
            final expected =
                await sha256.bind(File(checkpoint).openRead()).first;
            if (await verified.length() > ImmutableSyncLog.maxBatchBytes ||
                (await sha256.bind(verified.openRead()).first).toString() !=
                    expected.toString()) {
              throw StateError(
                  'Cloud checkpoint changed; journal cleanup deferred');
            }
            removed = await log.reclaimReadBatches();
          } else if (atomicSupport == false) {
            removed = await log.compactIfNeeded();
          }
          if (removed > 0) {
            AnxLog.info(
                'Sync journal compacted: removed $removed covered batches');
          }
        } catch (e) {
          AnxLog.warning('Sync journal maintenance deferred: $e');
        }
        return outcome;
      }

      // Read-only version gate BEFORE any asset/log write. A v9+ client must
      // never touch a cloud archive written by a future/uncoordinated format.
      await _preflightRemoteVersion(staging);
      // Assets first: retrying after an interrupted transfer must not advertise
      // unavailable books as synchronized. Still after the version gate.
      await beforePublish?.call();
      // Repair/replay pending log batches before listing the journal: a partial
      // upload from a previous run is reinstated here (and never before the
      // version gate above).
      published = await log.resumePending();
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        // Both transports always consume the immutable log, including after
        // ETags recover. Otherwise intermittent capabilities split the library.
        final journal = await log.read();
        final remote = await client.readProps(remotePath);
        var path = remotePath;
        var metadata = remote;
        if (remote == null && journal.isEmpty) {
          path = SyncPaths.database('database7.db');
          metadata = await client.readProps(path);
        }
        List<RowSyncRecord> remoteRecords = [];
        var legacyArchive = false;
        if (metadata != null) {
          if ((metadata.size ?? 0) > 64 * 1024 * 1024) {
            throw const FormatException('同步数据库过大，已停止下载');
          }
          final download = '${staging.path}/download-$attempt.db';
          await client.downloadFile(path, download);
          final after = await client.readProps(path);
          if (after == null ||
              metadata.eTag != after.eTag ||
              metadata.size != after.size ||
              metadata.mTime != after.mTime) {
            continue;
          }
          // Strict fail-closed gate: inspect the archive version BEFORE any
          // asset upload, pending-log upload or local merge. A future/unknown
          // format is never overwritten.
          final remoteVersion = await RowSyncArchive.versionOf(download);
          if (remoteVersion != null &&
              remoteVersion > RowSyncArchive.databaseVersion) {
            throw FormatException(
                '云端同步数据版本过新（v$remoteVersion），本机未做任何写入；请升级本机客户端');
          }
          if (remoteVersion == RowSyncArchive.legacyVersion) {
            legacyArchive = true;
            // Keep the exact v8 bytes we are about to migrate. Recovery never
            // depends on the network, and old clients can still be restored.
            await _keepLegacyArchiveBackup(download, attempt);
          }
          remoteRecords =
              await RowSyncArchive.read(download, legacy: remote == null);
        }
        // Keep the actual remote baseline: normalization can retire duplicate
        // identities even when there are no user edits. That repair must be
        // published, not mistaken for an unchanged already-normalized cloud.
        final remoteBaseline = mergeSyncRecords(remoteRecords, journal,
            reconcileBookIdentities: false);
        remoteRecords = mergeSyncRecords(remoteBaseline, []);
        final repairsRemoteIdentity =
            !sameSyncRecords(remoteBaseline, remoteRecords);
        final local = await store.snapshot();
        if (!backedUp &&
            remoteRecords.isNotEmpty &&
            !sameSyncRecords(local, mergeSyncRecords(local, remoteRecords))) {
          await beforeMerge?.call();
          backedUp = true;
        }
        var merged = await store.merge(remoteRecords);
        // Metadata-only local migrations run after learning remote replacements
        // and before the unchanged fast path. Publish the repaired snapshot in
        // this same sync, without resurrecting an obsolete local book file.
        if (afterMerge != null) {
          await afterMerge!();
          merged = await store.snapshot();
        }
        // Counts only: enough to distinguish an empty metadata view from a
        // successful merge without exposing titles, paths, accounts or keys.
        int bookRecords(List<RowSyncRecord> records) =>
            records.where((r) => r.kind == 'book' && !r.deleted).length;
        AnxLog.info('Sync metadata: attempt=${attempt + 1}, '
            'localBooks=${bookRecords(local)}, remoteBooks=${bookRecords(remoteRecords)}, '
            'mergedBooks=${bookRecords(merged)}, checkpoint=${metadata != null}, '
            'journalRecords=${journal.length}');
        if ((remote != null || journal.isNotEmpty) &&
            !legacyArchive &&
            !repairsRemoteIdentity &&
            sameSyncRecords(merged, remoteRecords)) {
          if (log.hasReadBatches) {
            atomicSupport ??= await client.supportsAtomicSyncWrites();
          }
          if (!log.hasReadBatches || atomicSupport != true) {
            return await finish(published
                ? RowSyncOutcome.published
                : RowSyncOutcome.unchanged);
          }
          // Even with no local edits, fold outstanding journal records into
          // database8 using CAS before reclaiming their source batches.
        }
        // An empty new device may read a real empty/tombstone archive, but may
        // not create the first cloud library merely by opening the app.
        if (remote == null &&
            metadata == null &&
            !merged.any((r) => r.kind == 'book')) {
          return RowSyncOutcome.unchanged;
        }
        // Include assets imported while the remote database was downloading.
        // Changes after this merged snapshot are picked up by the next pass.
        await beforePublish?.call();
        atomicSupport ??= await client.supportsAtomicSyncWrites();
        Future<void> publishLog() async {
          atomicSupport = false;
          // On first legacy migration, seed all legacy records as well. Once
          // the log exists, database7 must not be re-imported repeatedly.
          final baseline = remote == null ? journal : remoteBaseline;
          final known = {
            for (final r in baseline) r.key: jsonEncode(r.toMap())
          };
          final delta = merged
              .where((r) => known[r.key] != jsonEncode(r.toMap()))
              .toList();
          if (delta.isNotEmpty) await log.publish(delta);
          published = true;
        }

        Future<RowSyncOutcome?> finishPublished({String? checkpoint}) async {
          if (sameSyncRecords(await store.snapshot(), merged)) {
            return finish(RowSyncOutcome.published, checkpoint: checkpoint);
          }
          // Live reading need not stop for an upload to succeed. Newer local
          // revisions remain in the database and must be queued for a later sync.
          if (attempt + 1 >= maxAttempts) {
            return finish(RowSyncOutcome.publishedWithPendingChanges,
                checkpoint: checkpoint);
          }
          return null;
        }

        if (atomicSupport != true) {
          await publishLog();
          final outcome = await finishPublished();
          if (outcome != null) return outcome;
          continue;
        }
        final upload = '${staging.path}/upload-$attempt.db';
        await RowSyncArchive.write(upload, merged);
        try {
          await client.uploadFileConditionally(upload, remotePath,
              expectedETag: remote?.eTag, createOnly: remote == null);
          published = true;
          final outcome = await finishPublished(checkpoint: upload);
          if (outcome != null) return outcome;
          // Reading/import can continue during upload. If it produced another
          // operation, include it in the next bounded pass instead of marking
          // an older snapshot as fully synchronized.
        } on MissingSyncValidatorException {
          if (attempt + 1 >= maxAttempts) {
            await publishLog();
            return (await finishPublished())!;
          }
          // No PUT was sent. Reload and re-merge the whole remote snapshot;
          // never attach a newly fetched ETag to an older merged upload.
          await Future<void>.delayed(validatorRetryDelay);
        } on DioException catch (e) {
          if ([405, 501].contains(e.response?.statusCode)) {
            // A capability can disappear after a successful earlier probe.
            // Only the immutable log may use plain PUT, never the shared file.
            atomicSupport = false;
            await publishLog();
            final outcome = await finishPublished();
            if (outcome != null) return outcome;
            continue;
          }
          if (e.response?.statusCode != 412) rethrow;
          // Another device published first: reload and re-merge, preserving
          // new local changes too. Never retry with an unconditional PUT.
        }
      }
      throw StateError('其他设备正在更新云端，已保留本机改动；请稍后重试同步');
    } finally {
      await staging.delete(recursive: true);
    }
  }
}
