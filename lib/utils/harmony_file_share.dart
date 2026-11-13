import 'dart:io';

import 'package:modu_reader/utils/harmony_file_export.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> shareHarmonyFile({
  required String sourceFilePath,
  String? title,
}) async {
  final source = File(sourceFilePath);
  if (!await source.exists()) {
    throw FileSystemException('File is not available locally', sourceFilePath);
  }
  final name = (title ?? p.basename(sourceFilePath))
      .replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
  if (name.isEmpty || name == '.' || name == '..') {
    throw ArgumentError.value(title, 'title', 'Expected a file name');
  }
  final cache = await getTemporaryDirectory();
  // The receiving app may read after the share sheet closes. Retain snapshots
  // for a day and clean only our own old directories on a subsequent share.
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  await for (final entry in cache.list(followLinks: false)) {
    if (entry is Directory &&
        p.basename(entry.path).startsWith('modu-share-')) {
      try {
        if ((await entry.stat()).modified.isBefore(cutoff)) {
          await entry.delete(recursive: true);
        }
      } on FileSystemException {
        // Cache cleanup must not prevent sharing a new file.
      }
    }
  }
  final staging = await cache.createTemp('modu-share-');
  try {
    final snapshot = await source.copy(p.join(staging.path, name));
    await harmonyFileExportChannel.invokeMethod<void>('shareFile', {
      'sourcePath': snapshot.path,
      'fileName': name,
    });
  } catch (_) {
    await staging.delete(recursive: true);
    rethrow;
  }
}
