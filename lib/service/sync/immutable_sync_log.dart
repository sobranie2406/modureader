import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';

/// Content-addressed batches are never replaced with different bytes. Two
/// concurrent publishers either write different names or identical content.
/// No shared head/manifest/lock file is necessary. Never garbage-collect here:
/// offline devices may still need old operations and tombstones.
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

  Future<List<RowSyncRecord>> read() async {
    final root = await client.readProps(SyncPaths.recordLog);
    if (root == null) return [];
    if (root.isDir != true) throw const FormatException('同步记录目录无效');
    var records = <RowSyncRecord>[];
    var bytes = 0;
    var count = 0;
    await verifiedCache.create(recursive: true);
    for (final first in await client.readSyncDirectory(SyncPaths.recordLog)) {
      if (first.isDir != true || !_shard.hasMatch(first.name ?? '')) {
        throw const FormatException('未知同步记录目录，请更新所有客户端');
      }
      final firstPath = '${SyncPaths.recordLog}/${first.name}';
      for (final item in await client.readSyncDirectory(firstPath)) {
        final match = _batch.firstMatch(item.name ?? '');
        if (item.isDir != false ||
            match == null ||
            !match[1]!.startsWith('${first.name}') ||
            (item.size ?? 0) > maxBatchBytes ||
            ++count > 10000) {
          throw const FormatException('同步记录文件无效或超过安全限制');
        }
        final local = File('${verifiedCache.path}/${item.name}');
        final cached = await local.exists() &&
            await local.length() <= maxBatchBytes &&
            (await sha256.bind(local.openRead()).first).toString() == match[1];
        if (!cached) {
          final download = File('${staging.path}/batch.db');
          await client.downloadFile('$firstPath/${item.name}', download.path);
          if (await download.length() > maxBatchBytes ||
              (await sha256.bind(download.openRead()).first).toString() !=
                  match[1]) {
            throw const FormatException('同步记录尚未完整上传或校验失败，请稍后重试');
          }
          await download.rename(local.path);
        }
        final size = await local.length();
        bytes += size;
        if (size > maxBatchBytes || bytes > maxScanBytes) {
          throw const FormatException('同步记录过大，已保留本机数据并停止同步');
        }
        if ((await sha256.bind(local.openRead()).first).toString() !=
            match[1]) {
          // Includes partially uploaded objects. Abort without acknowledging
          // success; retry next sync, never interpret partial bytes as empty.
          throw const FormatException('同步记录尚未完整上传或校验失败，请稍后重试');
        }
        records =
            mergeSyncRecords(records, await RowSyncArchive.read(local.path));
      }
    }
    return records;
  }

  Future<void> publish(List<RowSyncRecord> records) async {
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
    // Delete only after read-back succeeds. A crash/timeout replays the exact
    // same bytes on restart and repairs a partially visible remote upload.
    if (await source.exists()) await source.delete();
  }
}
