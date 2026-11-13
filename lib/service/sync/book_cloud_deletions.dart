import 'dart:convert';
import 'dart:io';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/sync/sync_client_base.dart';
import 'package:modu_reader/service/sync/sync_paths.dart';

/// Explicit deletion intents, scoped to one backend. Never infer from absence.
class BookCloudDeletions {
  BookCloudDeletions(this.file);
  final File file;
  static Future<void> _pending = Future.value();
  Future<void> _change(
      Future<void> Function(List<Map<String, dynamic>>) action) {
    final next = _pending.then((_) async {
      final rows = await file.exists()
          ? (jsonDecode(await file.readAsString()) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];
      await action(rows);
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(rows), flush: true);
      await temp.rename(file.path);
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> enqueue(SyncClientBase client, Iterable<Book> books) =>
      _change((rows) async {
        final endpoint = jsonEncode(client.syncIdentity);
        for (final book in books) {
          rows.removeWhere(
              (r) => r['endpoint'] == endpoint && r['path'] == book.filePath);
          rows.add({
            'endpoint': endpoint,
            'path': book.filePath,
            'cover': book.coverPath,
            'md5': book.md5
          });
        }
      });

  /// Call only after a successful merged database publication. Retain intents
  /// after success too: a late offline upload must be cleaned on a later sync.
  Future<void> apply(SyncClientBase client, List<Book> books) =>
      _change((rows) async {
        final endpoint = jsonEncode(client.syncIdentity);
        final cancelled = <Map<String, dynamic>>{};
        for (final row in rows.where((r) => r['endpoint'] == endpoint)) {
          final path = row['path'] as String;
          final hash = row['md5'];
          final same = books.where(
              (b) => b.filePath == path || (hash != null && b.md5 == hash));
          if (same.isEmpty) continue;
          final generation = same.first.updateTime.millisecondsSinceEpoch;
          if (same.any((b) => !b.isDeleted) ||
              (row['generation'] != null && row['generation'] != generation)) {
            cancelled.add(row);
            continue;
          }
          row['generation'] = generation;
          for (final asset in [path, row['cover'] as String]) {
            if (asset.isEmpty ||
                books.any((b) =>
                    !b.isDeleted &&
                    (b.filePath == asset || b.coverPath == asset))) {
              continue;
            }
            final parts = asset.split('/');
            if (parts.length != 2 ||
                !['file', 'cover'].contains(parts.first) ||
                parts.last.isEmpty ||
                ['.', '..'].contains(parts.last) ||
                asset.contains('\\')) {
              throw const FormatException('Invalid deletion path');
            }
            final remote = SyncPaths.data(asset);
            final props = await client.readProps(remote);
            if (props == null) continue;
            if (props.isDir != false) {
              throw const FormatException(
                  'Refusing to delete a remote directory');
            }
            await client.remove(remote);
          }
        }
        rows.removeWhere(cancelled.contains);
      });
}
