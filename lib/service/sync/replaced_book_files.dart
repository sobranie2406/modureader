import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:anx_reader/service/sync/immutable_sync_log.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';

/// Local evidence of explicit replacements, not a list of remotely absent books.
/// Kept across syncs/endpoints so a late offline upload can be reclaimed again.
class ReplacedBookFiles {
  static const table = 'modu_replaced_book_files';
  static const recycleRoot = 'modu/replaced-files-v1';
  static const maxFileBytes = 512 * 1024 * 1024;
  static const maxFilesPerSync = 3;
  static final _md5 = RegExp(r'^[0-9a-fA-F]{32}$');

  static Future<void> _ensureTable(DatabaseExecutor db) => db.execute('''
    CREATE TABLE IF NOT EXISTS $table (
      book_id TEXT NOT NULL, old_path TEXT NOT NULL, old_md5 TEXT,
      PRIMARY KEY(book_id, old_path))''');

  static bool _bookPath(Object? path) =>
      path is String &&
      path.startsWith('file/') &&
      path.split('/').length == 2 &&
      path.length > 5 &&
      !path.contains(RegExp(r'[\\\x00-\x1f]')) &&
      !const ['.', '..'].contains(path.substring(5));

  /// Call in the same transaction as the book update. No network in the DAO.
  static Future<void> record(
      DatabaseExecutor txn, Map<String, Object?> old, String nextPath) async {
    final oldPath = old['file_path'];
    if (oldPath == nextPath) return;
    if (!_bookPath(oldPath) || !_bookPath(nextPath)) return;
    final identity = await txn.query(syncRecordsTable,
        columns: ['sync_id'],
        where: "kind='book' AND local_id=?",
        whereArgs: [old['id']]);
    if (identity.length != 1) {
      throw StateError('Replacement has no sync identity');
    }
    await _ensureTable(txn);
    await txn.insert(
        table,
        {
          'book_id': identity.single['sync_id'],
          'old_path': oldPath,
          'old_md5': old['file_md5'],
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  ReplacedBookFiles(
      {required this.store,
      required this.client,
      required this.cache,
      required this.durableDirectory});
  final RowSyncStore store;
  final SyncClientBase client;
  final Directory cache, durableDirectory;

  String get _endpoint => jsonEncode(
      [client.protocolName, client.config['url'], client.config['username']]);

  Future<int> reclaim() async {
    final endpoint = _endpoint;
    final staging = await cache.createTemp('modu-replaced-files-');
    var reclaimed = 0;
    var attempted = 0;
    try {
      // Another device (or an older release) may have performed the replacement.
      // Recover explicit old paths from verified records for the SAME stable book
      // identity, never infer relationships from a title, timestamp or file size.
      await _rememberHistory(staging);
      final pending = await store.db.query(table);
      for (final item in pending) {
        if (_endpoint != endpoint) throw StateError('Sync endpoint changed');
        final oldPath = item['old_path'];
        final oldMd5 = item['old_md5'];
        if (!_bookPath(oldPath) ||
            oldMd5 is! String ||
            !_md5.hasMatch(oldMd5)) {
          continue;
        }
        final path = SyncPaths.data(oldPath as String);
        final props = await client.readProps(path);
        if (props == null) continue;
        if (props.isDir != false ||
            props.size == null ||
            props.size! <= 0 ||
            props.size! > maxFileBytes) {
          continue;
        }

        final cloud = await _cloudSnapshot(staging);
        final local = await store.snapshot();
        final replacement = _eligible(item, local, cloud);
        if (replacement == null) continue;
        if (attempted++ >= maxFilesPerSync) break;
        final nextPath = replacement.data['file_path'] as String;
        final nextMd5 = replacement.data['file_md5'];
        if (nextMd5 is! String || !_md5.hasMatch(nextMd5)) continue;
        // A database pointer or successful PUT alone is not proof of a complete
        // replacement. Read back the bytes before touching the old object.
        final next = File('${staging.path}/replacement');
        if (!await _downloadBook(SyncPaths.data(nextPath), next) ||
            (await md5.bind(next.openRead()).first).toString() !=
                nextMd5.toLowerCase()) {
          continue;
        }
        final old = File('${staging.path}/old');
        if (!await _downloadBook(path, old) ||
            (await md5.bind(old.openRead()).first).toString() !=
                oldMd5.toLowerCase()) {
          continue;
        }
        // Recoverable reclamation: preserve verified bytes outside data/file.
        // Old clients do not participate in an acknowledged permanent-GC protocol.
        final digest = (await sha256.bind(old.openRead()).first).toString();
        final pathId = sha256.convert(utf8.encode(oldPath)).toString();
        final folder = '$recycleRoot/$pathId/$digest';
        final backup = '$folder/${oldPath.substring(5)}';
        await client.mkdirAll(folder);
        await client.uploadFile(old.path, backup);
        final verify = File('${staging.path}/verify');
        await client.downloadFile(backup, verify.path);
        if ((await sha256.bind(verify.openRead()).first).toString() != digest) {
          throw StateError('Replaced book backup verification failed');
        }

        // Recheck both endpoints after all slow transfers. Any concurrent change
        // postpones cleanup; nothing is inferred from titles or timestamps.
        if (!await _downloadBook(path, verify) ||
            (await sha256.bind(verify.openRead()).first).toString() != digest) {
          continue;
        }
        final freshCloud = await _cloudSnapshot(staging);
        final freshLocal = await store.snapshot();
        if (!_sameBookReferences(cloud, freshCloud) ||
            !_sameBookReferences(local, freshLocal) ||
            _eligible(item, freshLocal, freshCloud) == null) {
          continue;
        }
        if (_endpoint != endpoint) throw StateError('Sync endpoint changed');
        await client.remove(path);
        reclaimed++;
      }
      return reclaimed;
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<void> _rememberHistory(Directory staging) async {
    final local = {
      for (final record in await store.snapshot())
        if (record.kind == 'book' && !record.deleted) record.id: record,
    };
    await _ensureTable(store.db);
    final evidence = <String, Map<String, Object?>>{};
    final log = ImmutableSyncLog(client, staging, cache,
        durableDirectory: durableDirectory);
    await log.read(onVerifiedBatch: (batch) async {
      for (final old in batch) {
        final current = local[old.id];
        final path = old.data['file_path'];
        final digest = old.data['file_md5'];
        if (old.kind != 'book' ||
            old.deleted ||
            current == null ||
            !_bookPath(path) ||
            !_bookPath(current.data['file_path']) ||
            path == current.data['file_path'] ||
            digest is! String ||
            !_md5.hasMatch(digest)) {
          continue;
        }
        // Require a strictly older clock; equal-clock conflicts and newer
        // remote records are not assumed to be obsolete.
        if (old.clock >= current.clock) continue;
        evidence[jsonEncode([old.id, path])] = {
          'book_id': old.id,
          'old_path': path,
          'old_md5': digest,
        };
      }
    });
    // Incomplete/invalid scans throw above without installing partial evidence.
    await store.db.transaction((txn) async {
      for (final item in evidence.values) {
        await txn.insert(table, item,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  /// Notes, reading time and positions cannot introduce a file reference.
  /// Still compare ALL books (including trash) and deletion/restore operations.
  bool _sameBookReferences(List<RowSyncRecord> a, List<RowSyncRecord> b) =>
      sameSyncRecords(
        a.where((r) => r.kind == 'book' || r.kind == 'life'),
        b.where((r) => r.kind == 'book' || r.kind == 'life'),
      );

  Future<bool> _downloadBook(String path, File target) async {
    final props = await client.readProps(path);
    if (props?.isDir != false ||
        props?.size == null ||
        props!.size! <= 0 ||
        props.size! > maxFileBytes) {
      return false;
    }
    await client.downloadFile(path, target.path);
    return await target.length() == props.size;
  }

  RowSyncRecord? _eligible(Map<String, Object?> item, List<RowSyncRecord> local,
      List<RowSyncRecord> remote) {
    if ([...local, ...remote].any((r) =>
        r.kind == 'life' &&
        r.id == item['book_id'] &&
        (r.deleted || r.data['is_deleted'] == 1))) {
      return null;
    }
    // Protect every reference, including trash/restorable books and duplicates.
    if ([
      ...local,
      ...remote
    ].any((r) => r.kind == 'book' && r.data['file_path'] == item['old_path'])) {
      return null;
    }
    final a = local
        .where((r) => r.kind == 'book' && r.id == item['book_id'])
        .toList();
    final b = remote
        .where((r) => r.kind == 'book' && r.id == item['book_id'])
        .toList();
    if (a.length != 1 ||
        b.length != 1 ||
        a.single.deleted ||
        !sameSyncRecords(a, b) ||
        !_bookPath(a.single.data['file_path'])) {
      return null;
    }
    return a.single;
  }

  Future<List<RowSyncRecord>> _cloudSnapshot(Directory staging) async {
    final log = ImmutableSyncLog(client, staging, cache,
        durableDirectory: durableDirectory);
    final journal = await log.read();
    final path = RowSyncEngine.remotePath;
    final before = await client.readProps(path);
    List<RowSyncRecord> records = [];
    if (before != null) {
      if (before.isDir != false ||
          before.size == null ||
          before.size! > 64 * 1024 * 1024) {
        throw StateError('Invalid cloud archive');
      }
      final first = File('${staging.path}/gc-snapshot.db');
      final second = File('${staging.path}/gc-snapshot-check.db');
      await client.downloadFile(path, first.path);
      records = await RowSyncArchive.read(first.path);
      await client.downloadFile(path, second.path);
      if ((await sha256.bind(first.openRead()).first).toString() !=
          (await sha256.bind(second.openRead()).first).toString()) {
        final latest = await RowSyncArchive.read(second.path);
        if (!_sameBookReferences(records, latest)) {
          throw StateError('Cloud changed during replacement cleanup');
        }
        records = latest;
      }
    }
    final afterJournal = await log.read();
    if (!_sameBookReferences(journal, afterJournal)) {
      throw StateError('Cloud log changed during replacement cleanup');
    }
    // No legacy guessing; newly synchronized replacements use v8 or the log.
    return mergeSyncRecords(records, afterJournal);
  }
}
