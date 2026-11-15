import 'dart:io';

import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/sync/sync_client_base.dart';
import 'package:modu_reader/service/sync/sync_paths.dart';

bool canSyncBookAsset(Iterable<Book> books, String relativePath) {
  final privacy = PrivateLibrary.instance;
  if (!privacy.hasSyncExclusions) return true;
  if (!privacy.canSyncSource(filePath: relativePath)) return false;
  final owners = books
      .where((book) =>
          book.filePath == relativePath || book.coverPath == relativePath)
      .toList();
  return owners.isNotEmpty && owners.every(privacy.canSyncBook);
}

/// The directory listing is a hint, not proof that a recently uploaded book
/// is absent. Some DAV servers return delayed or paginated listings.
Future<void> syncBookFiles({
  required SyncClientBase client,
  required Iterable<String> currentPaths,
  required Set<String> listedPaths,
  required File Function(String relativePath) localFile,
  required Future<void> Function(String localPath, String remotePath) upload,
  void Function(String relativePath)? onRemotePresent,
  bool Function(String relativePath)? canSyncPath,
}) async {
  bool allowed(String path) =>
      canSyncPath?.call(path) ?? !PrivateLibrary.instance.hasSyncExclusions;
  for (final path in currentPaths.toSet()) {
    if (!allowed(path)) continue;
    final remotePath = SyncPaths.data(path);
    if (listedPaths.contains(path)) continue;
    final local = localFile(path);
    if (!await local.exists()) continue;
    if (!allowed(path)) continue;

    // Probe the exact target before PUT, without trusting an in-memory
    // "already uploaded" flag. A later real cloud deletion must be repairable.
    final remote = await client.readProps(remotePath);
    if (!allowed(path)) continue;
    if (remote != null) {
      if (remote.isDir != false) {
        throw const FormatException('云端书籍路径不是文件，已停止覆盖');
      }
      // Book replacements have unique paths. Match the existing sync policy
      // for present files; never assume a weak/missing ETag means absence.
      onRemotePresent?.call(path);
      continue;
    }
    await upload(local.path, remotePath);
  }
}
