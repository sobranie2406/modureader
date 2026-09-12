import 'dart:io';
import 'dart:convert';
import 'package:anx_reader/service/sync/immutable_sync_log.dart';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';

/// A clean SQLite transport: only portable records and opaque encrypted AI
/// settings. Never ships local paths, fonts, indexes, or the entire app DB.
class RowSyncArchive {
  static const format = 1;
  static const databaseVersion = 8;

  static Future<void> write(String path, List<RowSyncRecord> records) async {
    final db = await openDatabase(path, singleInstance: false);
    try {
      await db.transaction((txn) async {
        await txn.execute(
            'CREATE TABLE modu_sync_manifest (format INTEGER NOT NULL)');
        await txn.insert('modu_sync_manifest', {'format': format});
        await txn.execute('''CREATE TABLE $syncRecordsTable (
          kind TEXT NOT NULL, sync_id TEXT NOT NULL, clock INTEGER NOT NULL,
          revision TEXT NOT NULL, deleted INTEGER NOT NULL, payload TEXT NOT NULL,
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
      {bool legacy = false}) async {
    // A bounded metadata-only database; an oversized/corrupt download cannot
    // be mistaken for an empty cloud library.
    if (await File(path).length() > 64 * 1024 * 1024) {
      throw const FormatException('同步数据库超过 64 MiB 安全限制');
    }
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
        throw const FormatException('不支持的同步数据库版本');
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

enum RowSyncOutcome { unchanged, published }

class RowSyncEngine {
  RowSyncEngine(
      {required this.store,
      required this.client,
      required this.cache,
      this.durableDirectory,
      this.beforePublish,
      this.beforeMerge,
      this.maxAttempts = 3,
      this.validatorRetryDelay = const Duration(seconds: 1)});
  final RowSyncStore store;
  final SyncClientBase client;
  final Directory cache;
  final Directory? durableDirectory;
  final Future<void> Function()? beforePublish;
  final Future<void> Function()? beforeMerge;
  final int maxAttempts;
  final Duration validatorRetryDelay;
  static final remotePath = SyncPaths.database('database8.db');

  Future<RowSyncOutcome> synchronize() async {
    // Complete asset uploads first. Retrying after an interrupted transfer
    // must not advertise unavailable new books as successfully synchronized.
    await beforePublish?.call();
    final staging = await cache.createTemp('modu-row-sync-');
    var backedUp = false;
    var published = false;
    bool? atomicSupport;
    try {
      final log = ImmutableSyncLog(client, staging, cache,
          durableDirectory: durableDirectory ?? cache);
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
          remoteRecords =
              await RowSyncArchive.read(download, legacy: remote == null);
        }
        remoteRecords = mergeSyncRecords(remoteRecords, journal);
        final local = await store.snapshot();
        if (!backedUp &&
            remoteRecords.isNotEmpty &&
            !sameSyncRecords(local, mergeSyncRecords(local, remoteRecords))) {
          await beforeMerge?.call();
          backedUp = true;
        }
        final merged = await store.merge(remoteRecords);
        if ((remote != null || journal.isNotEmpty) &&
            sameSyncRecords(merged, remoteRecords)) {
          return published
              ? RowSyncOutcome.published
              : RowSyncOutcome.unchanged;
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
          // On first legacy migration, seed all legacy records as well. Once
          // the log exists, database7 must not be re-imported repeatedly.
          final baseline = remote == null ? journal : remoteRecords;
          final known = {
            for (final r in baseline) r.key: jsonEncode(r.toMap())
          };
          final delta = merged
              .where((r) => known[r.key] != jsonEncode(r.toMap()))
              .toList();
          if (delta.isNotEmpty) await log.publish(delta);
          published = true;
        }

        if (!atomicSupport) {
          await publishLog();
          if (sameSyncRecords(await store.snapshot(), merged)) {
            return RowSyncOutcome.published;
          }
          continue;
        }
        final upload = '${staging.path}/upload-$attempt.db';
        await RowSyncArchive.write(upload, merged);
        try {
          await client.uploadFileConditionally(upload, remotePath,
              expectedETag: remote?.eTag, createOnly: remote == null);
          published = true;
          if (sameSyncRecords(await store.snapshot(), merged)) {
            return RowSyncOutcome.published;
          }
          // Reading/import can continue during upload. If it produced another
          // operation, include it in the next bounded pass instead of marking
          // an older snapshot as fully synchronized.
        } on MissingSyncValidatorException {
          if (attempt + 1 >= maxAttempts) {
            await publishLog();
            if (sameSyncRecords(await store.snapshot(), merged)) {
              return RowSyncOutcome.published;
            }
            break;
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
            if (sameSyncRecords(await store.snapshot(), merged)) {
              return RowSyncOutcome.published;
            }
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
