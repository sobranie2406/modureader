import 'dart:io';

import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('font and unrelated local resources cannot enter file sync', () {
    for (final path in [
      'font/local.ttf',
      'fonts/local.otf',
      'bgimg/a.png',
      'file/../font/a.ttf',
      '/file/a.epub',
      'file\\a.epub'
    ]) {
      expect(() => SyncPaths.data(path), throwsArgumentError, reason: path);
    }
  });
  test('database, books, covers and connection tests share the modu root', () {
    expect(SyncPaths.root, 'modu');
    expect(SyncPaths.books, 'modu/data/file');
    expect(SyncPaths.covers, 'modu/data/cover');
    expect(SyncPaths.connectionTest, 'modu/.test');
    expect(SyncPaths.database('database42.db'), 'modu/database42.db');
  });

  test('book and cover paths preserve filenames under the configured endpoint',
      () {
    expect(
        SyncPaths.data('file/中文书籍 (1).epub'), 'modu/data/file/中文书籍 (1).epub');
    expect(SyncPaths.data('cover/book.jpg'), 'modu/data/cover/book.jpg');
  });

  test('sync callers no longer hard-code the legacy remote root', () {
    for (final path in [
      'lib/providers/sync.dart',
      'lib/service/database_sync_manager.dart',
      'lib/service/sync/webdav_client.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('SyncPaths.'), reason: path);
      expect(
          RegExp("['\"]/??anx(?:/|['\"])", caseSensitive: false)
              .hasMatch(source),
          isFalse,
          reason: path);
    }
  });
}
