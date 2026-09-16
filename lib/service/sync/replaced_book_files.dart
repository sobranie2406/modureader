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
    await txn.execute('''CREATE TABLE IF NOT EXISTS $table (
      book_id TEXT NOT NULL, old_path TEXT NOT NULL, old_md5 TEXT,
      PRIMARY KEY(book_id, old_path))''');
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
    final exists = await store.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [table]);
    if (exists.isEmpty) return 0;
    final pending = await store.db.query(table);
    if (pending.isEmpty) return 0;
    final staging = await cache.createTemp('modu-replaced-files-');
    var reclaimed = 0;
    var attempted = 0;
    try {
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
        if (!sameSyncRecords(cloud, freshCloud) ||
            !sameSyncRecords(local, await store.snapshot()) ||
            _eligible(item, local, freshCloud) == null) {
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
        throw StateError('Cloud changed during replacement cleanup');
      }
    }
    final afterJournal = await log.read();
    if (!sameSyncRecords(journal, afterJournal)) {
      throw StateError('Cloud log changed during replacement cleanup');
    }
    // No legacy guessing; newly synchronized replacements use v8 or the log.
    return mergeSyncRecords(records, journal);
  }
}
