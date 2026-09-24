import 'dart:io';

import 'package:anx_reader/models/remote_file.dart';
import 'package:anx_reader/service/sync/book_file_sync.dart';
import 'package:anx_reader/service/sync/replaced_book_files.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'replaced_book_files_test.dart' show CleanupClient;
import 'row_sync_test.dart' show fixture;

class DelayedListingClient extends CleanupClient {
  bool failProbe = false;

  @override
  Future<RemoteFile?> readProps(String path) {
    if (failProbe && path.startsWith('${SyncPaths.books}/')) {
      throw StateError('simulated network/permission failure');
    }
    return super.readProps(path);
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late Database db;
  late DelayedListingClient client;
  late RowSyncStore store;
  const oldPath = 'file/old.epub';
  const newPath = 'file/替换书籍 #100% %2F.epub';
  const oldBytes = [1, 2, 3];
  const newBytes = [4, 5, 6, 7];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('modu-book-file-sync-test-');
    await Directory('${temp.path}/file').create();
    await File('${temp.path}/$newPath').writeAsBytes(newBytes);
    db = await fixture();
    await db.update('tb_books', {
      'file_path': oldPath,
      'file_md5': md5.convert(oldBytes).toString(),
    });
    client = DelayedListingClient();
    client.files[SyncPaths.data(oldPath)] = oldBytes;
    store = RowSyncStore(db);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> syncFiles() async {
    final rows = await db.query('tb_books');
    await syncBookFiles(
      client: client,
      currentPaths: rows.map((r) => r['file_path'] as String),
      // Simulate a server still returning the pre-replacement directory.
      listedPaths: {oldPath},
      localFile: (path) => File('${temp.path}/$path'),
      upload: (local, remote) => client.uploadFile(local, remote),
    );
  }

  Future<void> replace() => db.transaction((txn) async {
        final old = (await txn.query('tb_books')).single;
        await ReplacedBookFiles.record(txn, old, newPath);
        await txn.update('tb_books', {
          'file_path': newPath,
          'file_md5': md5.convert(newBytes).toString(),
        });
      });

  for (final atomic in [true, false]) {
    test('replace then sync repeatedly without restart (atomic=$atomic)',
        () async {
      client.atomic = atomic;
      final engine = RowSyncEngine(
          store: store, client: client, cache: temp, beforePublish: syncFiles);
      await engine.synchronize();
      await replace();
      final cleanup = ReplacedBookFiles(
          store: store, client: client, cache: temp, durableDirectory: temp);
      for (var round = 0; round < 4; round++) {
        await engine.synchronize();
        await syncFiles();
        expect(await cleanup.reclaim(), round == 0 ? 1 : 0);
      }
      expect(
          client.uploaded.where((p) => p == SyncPaths.data(newPath)).length, 1);
      expect(
          client.files.keys.where((p) => p.startsWith('${SyncPaths.books}/')),
          [SyncPaths.data(newPath)]);
      expect(client.files[SyncPaths.data(newPath)], newBytes);
      // No process-lifetime upload cache: a genuinely deleted file is restored.
      client.files.remove(SyncPaths.data(newPath));
      await syncFiles();
      expect(
          client.uploaded.where((p) => p == SyncPaths.data(newPath)).length, 2);
    });
  }

  test('failed exact-path probe cannot authorize an overwrite', () async {
    await replace();
    client.failProbe = true;
    await expectLater(syncFiles(), throwsStateError);
    expect(client.uploaded, isEmpty);
  });
}
