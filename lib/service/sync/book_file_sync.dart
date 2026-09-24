import 'dart:io';

import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';

/// The directory listing is a hint, not proof that a recently uploaded book
/// is absent. Some DAV servers return delayed or paginated listings.
Future<void> syncBookFiles({
  required SyncClientBase client,
  required Iterable<String> currentPaths,
  required Set<String> listedPaths,
  required File Function(String relativePath) localFile,
  required Future<void> Function(String localPath, String remotePath) upload,
}) async {
  for (final path in currentPaths.toSet()) {
    final remotePath = SyncPaths.data(path);
    if (listedPaths.contains(path)) continue;
    final local = localFile(path);
    if (!await local.exists()) continue;

    // Probe the exact target before PUT, without trusting an in-memory
    // "already uploaded" flag. A later real cloud deletion must be repairable.
    final remote = await client.readProps(remotePath);
    if (remote != null) {
      if (remote.isDir != false) {
        throw const FormatException('云端书籍路径不是文件，已停止覆盖');
      }
      // Book replacements have unique paths. Match the existing sync policy
      // for present files; never assume a weak/missing ETag means absence.
      continue;
    }
    await upload(local.path, remotePath);
  }
}
