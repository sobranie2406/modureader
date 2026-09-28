import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';

/// Content-addressed batches are never replaced with different bytes. Two
/// concurrent publishers either write different names or identical content.
/// No shared head/manifest/lock file is necessary. Compaction retains the merged
/// state INCLUDING tombstones, so offline devices can still converge.
class ImmutableSyncLog {
  ImmutableSyncLog(this.client, this.staging, Directory cache,
      {required Directory durableDirectory})
      : verifiedCache = Directory('${cache.path}/modu-sync-record-cache-v1'),
        pending = Directory(
            '${durableDirectory.path}/modu-sync-pending-v1/${sha256.convert(utf8.encode(jsonEncode([
              client.protocolName,
              client.config['url'],
              client.config['username']
            ])))}');
  final SyncClientBase client;
  final Directory staging;
  final Directory pending;
  final Directory verifiedCache;
  static final _shard = RegExp(r'^[0-9a-f]$');
  static final _batch = RegExp(r'^([0-9a-f]{64})\.db$');
  static const maxBatchBytes = 64 * 1024 * 1024;
  static const maxScanBytes = 256 * 1024 * 1024;
  static const compactAfterBatches = 64;
  Map<String, RemoteFile>? _readFiles;
  List<RowSyncRecord>? _readRecords;
  bool get hasReadBatches => _readFiles?.isNotEmpty == true;

  // Finder/Explorer may create these files when the WebDAV directory is browsed.
  // Ignore exact, known non-record filenames only, never arbitrary hidden files,
  // directories, database batches, or entries with an unknown resource type.
  static bool _isSystemSidecar(RemoteFile file) =>
      file.isDir == false &&
      const {'.DS_Store', 'Thumbs.db', 'desktop.ini'}.contains(file.name);

  Future<bool> resumePending() async {
    if (!await pending.exists()) return false;
    var published = false;
    await for (final entity in pending.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final match = _batch.firstMatch(name);
      if (match == null) continue; // Uncommitted local temporary copy.
      if (await entity.length() > maxBatchBytes ||
          (await sha256.bind(entity.openRead()).first).toString() != match[1]) {
        throw const FormatException('本机待同步记录校验失败，已停止同步');
      }
      await _upload(entity, match[1]!);
      published = true;
    }
    return published;
  }

  Future<List<RowSyncRecord>> read({
    Future<void> Function(List<RowSyncRecord>)? onVerifiedBatch,
  }) async {
    _readFiles = null;
    _readRecords = null;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final files = await _listBatches();
        var records = <RowSyncRecord>[];
        final batches = <List<RowSyncRecord>>[];
        var bytes = 0;
        await verifiedCache.create(recursive: true);
        for (final entry in files.entries) {
          final name = entry.value.name!;
          final digest = _batch.firstMatch(name)![1]!;
          final local = File('${verifiedCache.path}/$name');
          final cached = await local.exists() &&
              await local.length() <= maxBatchBytes &&
              (await sha256.bind(local.openRead()).first).toString() == digest;
          if (!cached) {
            final download = File('${staging.path}/batch.db');
            await client.downloadFile(entry.key, download.path);
            if (await download.length() > maxBatchBytes ||
                (await sha256.bind(download.openRead()).first).toString() !=
                    digest) {
              throw const FormatException('同步记录尚未完整上传或校验失败，请稍后重试');
            }
            await download.rename(local.path);
          }
          bytes += await local.length();
          if (bytes > maxScanBytes) {
            throw const FormatException('同步记录过大，已保留本机数据并停止同步');
          }
          final batch = await RowSyncArchive.read(local.path);
          if (onVerifiedBatch != null) batches.add(batch);
          records =
              mergeSyncRecords(records, batch, reconcileBookIdentities: false);
        }
        // A compactor may add its checkpoint to an already listed shard and
        // remove inputs from a not-yet-listed shard. Check the complete name
        // set again; a successful scan must not silently miss BOTH generations.
        final after = await _listBatches();
        if (files.length != after.length ||
            !files.keys.every(after.containsKey)) continue;
        for (final batch in batches) {
          await onVerifiedBatch!(batch);
        }
        _readFiles = files;
        _readRecords = records;
        return records;
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
        // A verified replacement may have removed a listed input. Re-list,
        // never interpret a missing batch as empty records or report success.
      }
    }
    throw StateError('云端同步记录正在变化，已保留本机数据；请稍后重试');
  }

  Future<Map<String, RemoteFile>> _listBatches() async {
    final root = await client.readProps(SyncPaths.recordLog);
    if (root == null) return {};
    if (root.isDir != true) throw const FormatException('同步记录目录无效');
    final files = <String, RemoteFile>{};
    final shards = <String>[];
    for (final first in await client.readSyncDirectory(SyncPaths.recordLog)) {
      if (_isSystemSidecar(first)) continue;
      if (first.isDir != true || !_shard.hasMatch(first.name ?? '')) {
        throw const FormatException('未知同步记录目录，请更新所有客户端');
      }
      final firstPath = '${SyncPaths.recordLog}/${first.name}';
      if (shards.contains(firstPath)) {
        throw const FormatException('同步记录目录包含重复分片');
      }
      shards.add(firstPath);
    }
    // Two consistent listings protect against concurrent compaction. Bound the
    // shard requests to four in parallel so this safety check doesn't double
    // the latency of sixteen sequential network round trips.
    for (var start = 0; start < shards.length; start += 4) {
      final group = shards.skip(start).take(4).toList();
      final listings = await Future.wait(group.map(client.readSyncDirectory));
      for (var i = 0; i < group.length; i++) {
        final firstPath = group[i];
        final prefix = firstPath.substring(firstPath.length - 1);
        for (final item in listings[i]) {
          if (_isSystemSidecar(item)) continue;
          final match = _batch.firstMatch(item.name ?? '');
          if (item.isDir != false ||
              match == null ||
              !match[1]!.startsWith(prefix) ||
              (item.size ?? 0) > maxBatchBytes ||
              files.length >= 10000) {
            throw const FormatException('同步记录文件无效或超过安全限制');
          }
          final path = '$firstPath/${item.name}';
          if (files.containsKey(path)) {
            throw const FormatException('同步记录目录包含重复文件');
          }
          files[path] = item;
        }
      }
    }
    return files;
  }

  /// Only the exact inputs of a completed, validated read may be reclaimed.
  /// Publishing first creates a durable successor, including every tombstone.
  /// Competing compactors can remove each other's output only if it was one of
  /// their inputs (and is therefore preserved by their own verified successor).
  Future<int> compactIfNeeded() async {
    final inputs = _readFiles;
    final records = _readRecords;
    if (inputs == null ||
        records == null ||
        inputs.length < compactAfterBatches) return 0;
    final digest = await publish(records);
    final keep = '${SyncPaths.recordLog}/${digest[0]}/$digest.db';
    return reclaimReadBatches(keep: keep);
  }

  /// Caller must first durably publish AND read-back verify a successor which
  /// covers all records returned by read(). Reliable CAS uses database8.db;
  /// compatibility mode uses a content-addressed batch in this same directory.
  Future<int> reclaimReadBatches({String? keep}) async {
    final inputs = _readFiles;
    if (inputs == null) return 0;
    final obsolete = inputs.keys.where((path) => path != keep).toList();
    var removed = 0;
    // Limit concurrent DELETE requests. Stop on failure; a verified checkpoint
    // and any remaining inputs are sufficient to retry safely on the next sync.
    for (var i = 0; i < obsolete.length; i += 4) {
      await Future.wait(obsolete.skip(i).take(4).map((path) async {
        try {
          await client.remove(path);
          removed++;
        } on DioException catch (e) {
          if (e.response?.statusCode != 404) rethrow;
        }
      }));
    }
    _readFiles = null;
    _readRecords = null;
    return removed;
  }

  Future<String> publish(List<RowSyncRecord> records) async {
    final source = File('${staging.path}/publish-log.db');
    if (await source.exists()) await source.delete();
    // Sorting gives identical batches the same bytes/name on every client.
    await RowSyncArchive.write(source.path, mergeSyncRecords([], records));
    if (await source.length() > maxBatchBytes) {
      throw const FormatException('同步记录批次超过安全限制');
    }
    final digest = (await sha256.bind(source.openRead()).first).toString();
    await pending.create(recursive: true);
    final copy =
        await source.copy('${pending.path}/$digest.tmp-${const Uuid().v4()}');
    final durable = await copy.rename('${pending.path}/$digest.db');
    await _upload(durable, digest);
    return digest;
  }

  Future<void> _upload(File source, String digest) async {
    final folder = '${SyncPaths.recordLog}/${digest.substring(0, 1)}';
    final target = '$folder/$digest.db';
    await client.mkdirAll(folder);
    // Plain PUT is allowed ONLY for this content-addressed, immutable object,
    // never database8.db. Retrying the same name can only resend the same bytes.
    await client.uploadFile(source.path, target);
    final verify = File('${staging.path}/verify-log.db');
    await client.downloadFile(target, verify.path);
    if (await verify.length() != await source.length() ||
        (await sha256.bind(verify.openRead()).first).toString() != digest) {
      throw const FormatException('同步记录上传校验失败，未确认同步成功');
    }
    // Reuse the already verified read-back, including large checkpoints,
    // instead of downloading it again on the very next synchronization.
    await verifiedCache.create(recursive: true);
    await verify.rename('${verifiedCache.path}/$digest.db');
    // Delete only after read-back succeeds. A crash/timeout replays the exact
    // same bytes on restart and repairs a partially visible remote upload.
    if (await source.exists()) await source.delete();
  }
}
