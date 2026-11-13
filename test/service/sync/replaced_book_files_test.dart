import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:modu_reader/service/sync/replaced_book_files.dart';
import 'package:modu_reader/service/sync/local_book_download.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/service/sync/sync_paths.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/remote_file.dart';
import 'package:modu_reader/dao/book.dart';
import 'row_sync_test.dart' show MemorySyncClient, fixture, bookRow, noteRow;

class TestBookDao extends BookDao {
  TestBookDao(this.db);
  final Database db;
  @override
  Future<R> transaction<R>(Future<R> Function(Transaction) action) =>
      db.transaction(action);
}

class CleanupClient extends MemorySyncClient {
  @override
  Future<RemoteFile?> readProps(String path) async {
    final props = await super.readProps(path);
    if (!atomic) props?.eTag = null;
    return props;
  }

  final removed = <String>[];
  final uploaded = <String>[];
  bool corruptBackup = false;
  bool failRemove = false;
  Future<void> Function()? afterBackup;
  @override
  Future<void> remove(String path) async {
    if (failRemove) throw StateError('simulated permission failure');
    removed.add(path);
    files.remove(path);
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    uploaded.add(remotePath);
    await super.uploadFile(localPath, remotePath);
    if (remotePath.startsWith('${ReplacedBookFiles.recycleRoot}/')) {
      if (corruptBackup) files[remotePath] = [0];
      await afterBackup?.call();
    }
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late Directory temp;
  late CleanupClient client;
  late RowSyncStore store;
  final oldBytes = utf8.encode('old EPUB content');
  final newBytes = utf8.encode('replacement EPUB content');
  const oldPath = 'file/old.epub';
  const newPath = 'file/new.epub';
  setUp(() async {
    db = await fixture();
    await db.update('tb_books',
        {'file_path': oldPath, 'file_md5': md5.convert(oldBytes).toString()});
    temp = await Directory.systemTemp.createTemp('modu-cleanup-test-');
    client = CleanupClient();
    client.files[SyncPaths.data(oldPath)] = oldBytes;
    store = RowSyncStore(db);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> replace(String path, List<int> bytes) async {
    await db.transaction((txn) async {
      final old = (await txn.query('tb_books', where: 'id=1')).single;
      await ReplacedBookFiles.record(txn, old, path);
      await txn.update('tb_books',
          {'file_path': path, 'file_md5': md5.convert(bytes).toString()},
          where: 'id=1');
    });
    client.files[SyncPaths.data(path)] = bytes;
  }

  Future<void> publish() async {
    await RowSyncEngine(store: store, client: client, cache: temp)
        .synchronize();
  }

  Future<int> reclaim() => ReplacedBookFiles(
          store: store, client: client, cache: temp, durableDirectory: temp)
      .reclaim();

  Future<File> localFile(String path, List<int> bytes) async {
    final file = File('${temp.path}/$path');
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes);
  }

  Future<int> reclaimLocal({bool Function(String)? isInUse}) =>
      ReplacedBookFiles.reclaimLocal(
          db: db, files: Directory('${temp.path}/file'), isInUse: isInUse);

  test(
      'received replacement is recorded and cleaned only after verified download',
      () async {
    final old = await localFile(oldPath, oldBytes);
    final unknown = await localFile('file/unrelated.epub', oldBytes);
    await db.insert('tb_notes', noteRow(1, 'keep-note'));
    final original =
        (await store.snapshot()).singleWhere((r) => r.kind == 'book');
    final incoming = RowSyncRecord('book', original.id, original.clock + 1000,
        'remote-replacement', false, {
      ...original.data,
      'file_path': newPath,
      'file_md5': md5.convert(newBytes).toString(),
    });
    await store.merge([incoming]);
    final evidence = (await db.query(ReplacedBookFiles.table)).single;
    expect(evidence['old_path'], oldPath);
    expect(evidence['old_md5'], md5.convert(oldBytes).toString());
    expect(await reclaimLocal(), 0);
    final downloader = LocalBookDownload();
    final next = File('${temp.path}/$newPath');
    await expectLater(
        downloader.ensure(next, expectedMd5: md5.convert(newBytes).toString(),
            download: (file) async {
          await file.writeAsBytes([0]);
        }),
        throwsA(isA<BookFileIntegrityException>()));
    expect(await reclaimLocal(), 0);
    expect(await old.exists(), isTrue);
    await downloader.ensure(next, expectedMd5: md5.convert(newBytes).toString(),
        download: (file) async {
      await file.writeAsBytes(newBytes);
    });
    final before = await store.snapshot();
    expect(await reclaimLocal(), 1);
    expect(await old.exists(), isFalse);
    expect(await next.readAsBytes(), newBytes);
    expect(await unknown.exists(), isTrue);
    expect(sameSyncRecords(before, await store.snapshot()), isTrue);
    expect((await db.query('tb_notes')).single['content'], 'keep-note');
    expect((await db.query('tb_books')).single['last_read_position'], 'start');
    expect(await reclaimLocal(), 0);
  });

  test('multiple local old versions are removed without changing cloud files',
      () async {
    await localFile(oldPath, oldBytes);
    await replace('file/middle.epub', [1, 2]);
    await localFile('file/middle.epub', [1, 2]);
    await replace(newPath, newBytes);
    await localFile(newPath, newBytes);
    final remoteBefore = Map.of(client.files);
    expect(await reclaimLocal(), 2);
    expect(client.files, remoteBefore);
    expect(await db.query(ReplacedBookFiles.table), hasLength(2));
    expect(await File('${temp.path}/$newPath').readAsBytes(), newBytes);
  });

  test('local cleanup protects trash, active readers and changed old bytes',
      () async {
    final old = await localFile(oldPath, oldBytes);
    await replace(newPath, newBytes);
    await localFile(newPath, newBytes);
    expect(await reclaimLocal(isInUse: (path) => path == oldPath), 0);
    await db.insert('tb_books', {
      ...bookRow(2, md5: 'duplicate'),
      'file_path': oldPath,
      'is_deleted': 1
    });
    expect(await reclaimLocal(), 0);
    await db.delete('tb_books', where: 'id=2');
    await db.update('tb_books', {'is_deleted': 1}, where: 'id=1');
    expect(await reclaimLocal(), 0);
    await db.update('tb_books', {'is_deleted': 0}, where: 'id=1');
    await old.writeAsBytes([42]);
    expect(await reclaimLocal(), 0);
    expect(await old.readAsBytes(), [42]);
  });

  test(
      'local cleanup retains corrupt replacement, symlinks and unsafe evidence',
      () async {
    final old = await localFile(oldPath, oldBytes);
    await replace(newPath, newBytes);
    final next = await localFile(newPath, [0]);
    expect(await reclaimLocal(), 0);
    await next.delete();
    final external = await localFile('external.epub', newBytes);
    await Link(next.path).create(external.path);
    expect(await reclaimLocal(), 0);
    await Link(next.path).delete();
    await localFile(newPath, newBytes);
    await old.delete();
    final externalOld = await localFile('external-old.epub', oldBytes);
    await Link(old.path).create(externalOld.path);
    expect(await reclaimLocal(), 0);
    final evidence = (await db.query(ReplacedBookFiles.table)).single;
    await db.insert(ReplacedBookFiles.table,
        {...evidence, 'old_path': 'file/../external-old.epub'});
    expect(await reclaimLocal(), 0);
    expect(await externalOld.readAsBytes(), oldBytes);
    expect(await external.readAsBytes(), newBytes);
  });

  test('a reader opening during verification prevents local deletion',
      () async {
    final old = await localFile(oldPath, oldBytes);
    await replace(newPath, newBytes);
    await localFile(newPath, newBytes);
    var checks = 0;
    expect(await reclaimLocal(isInUse: (_) => ++checks > 1), 0);
    expect(await old.exists(), isTrue);
  });

  test('verified cloud history also recovers local legacy leftovers', () async {
    client.atomic = false;
    final old = await localFile(oldPath, oldBytes);
    await publish();
    await db.update('tb_books',
        {'file_path': newPath, 'file_md5': md5.convert(newBytes).toString()},
        where: 'id=1');
    client.files[SyncPaths.data(newPath)] = newBytes;
    await localFile(newPath, newBytes);
    await publish();
    expect(await reclaimLocal(), 0); // No guessed filename relationships.
    await reclaim(); // Installs evidence from the verified historical log.
    expect(await reclaimLocal(), 1);
    expect(await old.exists(), isFalse);
  });

  test('local cleanup is wired after successful download and sync maintenance',
      () {
    final source = File('lib/providers/sync.dart').readAsStringSync();
    final download = source.indexOf('Future<void> _downloadBook(');
    final received = source.indexOf('await downloadFile(', download);
    final cleanup =
        source.indexOf('await _cleanupReplacedLocalBooks();', received);
    expect(cleanup, greaterThan(received));
    expect(cleanup, lessThan(source.indexOf('WereadMetadataSync(', received)));
    final maintenance = source.indexOf('SyncMaintenanceSchedule(');
    expect(source.indexOf('await _cleanupReplacedLocalBooks();', maintenance),
        lessThan(source.indexOf('imageCache.clear();', maintenance)));
  });

  for (final atomic in [true, false]) {
    test('reclaims only explicit superseded files after sync (atomic=$atomic)',
        () async {
      client.atomic = atomic;
      await publish();
      await replace(newPath, newBytes);
      // New bytes alone are insufficient; cloud metadata still points at old.
      expect(await reclaim(), 0);
      await publish();
      final metadata = Map.of(client.files)
        ..removeWhere((k, _) => k.contains('/data/'));
      expect(await reclaim(), 1);
      expect(client.files[SyncPaths.data(oldPath)], isNull);
      expect(client.files[SyncPaths.data(newPath)], newBytes);
      expect(
          client.files.entries
              .where(
                  (e) => e.key.startsWith('${ReplacedBookFiles.recycleRoot}/'))
              .single
              .value,
          oldBytes);
      for (final entry in metadata.entries) {
        expect(client.files[entry.key], entry.value);
      }
      expect(await reclaim(), 0);
    });
  }

  test('multiple offline replacements collapse to the verified latest file',
      () async {
    await replace('file/middle.epub', utf8.encode('middle'));
    await replace(newPath, newBytes);
    client.files['modu/data/file/same-title-unknown.epub'] = [1, 2, 3];
    await publish();
    expect(await reclaim(), 2);
    expect(
        client.files.keys.where((k) => k.startsWith('${SyncPaths.books}/')),
        unorderedEquals([
          SyncPaths.data(newPath),
          'modu/data/file/same-title-unknown.epub'
        ]));
  });

  test('another device recovers old paths from verified cloud history',
      () async {
    client.atomic = false;
    await publish();
    // Emulate a release that updated the book but did not record local evidence.
    await db.update(
        'tb_books',
        {
          'file_path': 'file/middle.epub',
          'file_md5': md5.convert(utf8.encode('middle')).toString(),
        },
        where: 'id=1');
    client.files[SyncPaths.data('file/middle.epub')] = utf8.encode('middle');
    await publish();
    await db.update(
        'tb_books',
        {
          'file_path': newPath,
          'file_md5': md5.convert(newBytes).toString(),
        },
        where: 'id=1');
    client.files[SyncPaths.data(newPath)] = newBytes;
    await publish();
    final other = await fixture(bookId: 77);
    try {
      final receiver = RowSyncStore(other);
      await receiver.merge(await store.snapshot());
      expect(
          await ReplacedBookFiles(
                  store: receiver,
                  client: client,
                  cache: temp,
                  durableDirectory: temp)
              .reclaim(),
          2);
      expect(client.files[SyncPaths.data(newPath)], newBytes);
      expect(
          client.files.keys.where((p) => p.startsWith('${SyncPaths.books}/')),
          [SyncPaths.data(newPath)]);
      expect(
          (await other.query(ReplacedBookFiles.table))
              .map((r) => r['old_path']),
          containsAll([oldPath, 'file/middle.epub']));
    } finally {
      await other.close();
    }
  });

  test(
      'without replacement evidence an unreferenced same-title file is retained',
      () async {
    await db.update(
        'tb_books',
        {
          'file_path': newPath,
          'file_md5': md5.convert(newBytes).toString(),
        },
        where: 'id=1');
    client.files[SyncPaths.data(newPath)] = newBytes;
    // The old version was never published in a log and no local evidence exists.
    await publish();
    expect(await reclaim(), 0);
    expect(client.files[SyncPaths.data(oldPath)], oldBytes);
  });

  test('references from another book, even a deleted book, prevent cleanup',
      () async {
    await replace(newPath, newBytes);
    await db.insert('tb_books', {
      ...bookRow(2, md5: 'duplicate'),
      'file_path': oldPath,
      'is_deleted': 1
    });
    await publish();
    expect(await reclaim(), 0);
    expect(client.removed, isEmpty);
  });

  test('missing or corrupt replacement and changed old bytes are retained',
      () async {
    await replace(newPath, newBytes);
    await publish();
    client.files.remove(SyncPaths.data(newPath));
    expect(await reclaim(), 0);
    client.files[SyncPaths.data(newPath)] = [0];
    expect(await reclaim(), 0);
    client.files[SyncPaths.data(newPath)] = newBytes;
    client.files[SyncPaths.data(oldPath)] = [42];
    expect(await reclaim(), 0);
    expect(client.removed, isEmpty);
  });

  test('backup failure never deletes original; failed deletion is retryable',
      () async {
    await replace(newPath, newBytes);
    await publish();
    client.corruptBackup = true;
    await expectLater(reclaim(), throwsStateError);
    expect(client.files[SyncPaths.data(oldPath)], oldBytes);
    client.corruptBackup = false;
    client.failRemove = true;
    await expectLater(reclaim(), throwsStateError);
    expect(client.files[SyncPaths.data(oldPath)], oldBytes);
    client.failRemove = false;
    final uploadsBeforeRetry = client.uploaded.length;
    expect(await reclaim(), 1);
    expect(client.uploaded.length, uploadsBeforeRetry);
  });

  test('unrelated local notes during transfer do not starve cleanup', () async {
    await replace(newPath, newBytes);
    await publish();
    client.afterBackup = () async {
      await db.insert('tb_notes', noteRow(1, 'new-note'));
      await db.update('tb_books',
          {'last_read_position': 'new-position', 'reading_percentage': .75},
          where: 'id=1');
    };
    expect(await reclaim(), 1);
    expect((await db.query('tb_notes')).single['content'], 'new-note');
    expect((await db.query('tb_books')).single['reading_percentage'], .75);
  });

  test('a new local book reference during transfers still prevents removal',
      () async {
    await replace(newPath, newBytes);
    await publish();
    client.afterBackup = () async {
      await db.insert(
          'tb_books', {...bookRow(2, md5: 'revival'), 'file_path': oldPath});
    };
    expect(await reclaim(), 0);
    expect(client.removed, isEmpty);
  });

  test('deleting the replacement during transfers still prevents removal',
      () async {
    await replace(newPath, newBytes);
    await publish();
    client.afterBackup = () =>
        db.update('tb_books', {'is_deleted': 1}, where: 'id=1').then((_) {});
    expect(await reclaim(), 0);
    expect(client.removed, isEmpty);
  });

  test('unrelated cloud notes do not starve cleanup without ETag', () async {
    client.atomic = false;
    await replace(newPath, newBytes);
    await publish();
    final other = await fixture(bookId: 77);
    try {
      final remoteStore = RowSyncStore(other);
      await remoteStore.merge(await store.snapshot());
      client.afterBackup = () async {
        await other.insert('tb_notes', noteRow(77, 'new-note'));
        await RowSyncEngine(store: remoteStore, client: client, cache: temp)
            .synchronize();
      };
      expect(await reclaim(), 1);
      expect((await other.query('tb_notes')).single['content'], 'new-note');
    } finally {
      await other.close();
    }
  });

  test('cloud restores an old file reference during transfers: retain the file',
      () async {
    client.atomic = false;
    await replace(newPath, newBytes);
    await publish();
    final other = await fixture(bookId: 77);
    try {
      final receiver = RowSyncStore(other);
      await receiver.merge(await store.snapshot());
      client.afterBackup = () async {
        await other.update(
            'tb_books',
            {
              'file_path': oldPath,
              'file_md5': md5.convert(oldBytes).toString(),
            },
            where: 'id=77');
        await RowSyncEngine(store: receiver, client: client, cache: temp)
            .synchronize();
      };
      expect(await reclaim(), 0);
      expect(client.removed, isEmpty);
      expect(client.files[SyncPaths.data(oldPath)], oldBytes);
    } finally {
      await other.close();
    }
  });

  test('replacement evidence rolls back with the book update', () async {
    await expectLater(db.transaction((txn) async {
      final old = (await txn.query('tb_books')).single;
      await ReplacedBookFiles.record(txn, old, newPath);
      throw StateError('interrupted replacement');
    }), throwsStateError);
    expect(await reclaim(), 0);
    expect((await db.query('tb_books')).single['file_path'], oldPath);
  });

  test(
      'production book DAO records replacement without altering notes or position',
      () async {
    await db.insert('tb_notes', noteRow(1, 'kept-note'));
    final row = (await db.query('tb_books')).single;
    await TestBookDao(db).updateBook(Book.fromDb(row)
        .copyWith(filePath: newPath, md5: md5.convert(newBytes).toString()));
    final evidence = (await db.query(ReplacedBookFiles.table)).single;
    expect(evidence['old_path'], oldPath);
    expect(evidence['old_md5'], md5.convert(oldBytes).toString());
    expect((await db.query('tb_books')).single['last_read_position'], 'start');
    expect((await db.query('tb_notes')).single['content'], 'kept-note');
    client.files[SyncPaths.data(newPath)] = newBytes;
    await publish();
    expect(await reclaim(), 1);
  });

  test('cleanup is wired after database publication and ordinary file sync',
      () {
    final source = File('lib/providers/sync.dart').readAsStringSync();
    final publish = source.indexOf('await syncDatabase(direction,');
    final files = source.indexOf('await syncFiles(assetListing:', publish);
    final cleanup = source.indexOf('SyncMaintenanceSchedule(', files);
    final completion = source.indexOf('imageCache.clear();', files);
    expect(publish, greaterThan(0));
    expect(files, greaterThan(publish));
    expect(cleanup, greaterThan(files));
    expect(cleanup, lessThan(completion));
    expect(
        source.substring(source.indexOf('Future<void> syncFiles('),
            source.indexOf('Future<RowSyncOutcome> syncDatabase(')),
        isNot(contains('.reclaim()')));
  });

  test('unsafe or unknown paths never become cleanup candidates', () async {
    final old = (await db.query('tb_books')).single;
    await ReplacedBookFiles.record(
        db, {...old, 'file_path': 'file/../database8.db'}, newPath);
    await ReplacedBookFiles.record(
        db, {...old, 'file_path': 'cover/old.jpg'}, newPath);
    await ReplacedBookFiles.record(db, old, '../file/new.epub');
    await publish();
    expect(await reclaim(), 0);
    expect(client.removed, isEmpty);
  });

  test('late old upload is reclaimed again; reference revival is protected',
      () async {
    await replace(newPath, newBytes);
    await publish();
    expect(await reclaim(), 1);
    client.files[SyncPaths.data(oldPath)] = oldBytes;
    expect(await reclaim(), 1);
    client.files[SyncPaths.data(oldPath)] = oldBytes;
    await db.update('tb_books', {'file_path': oldPath});
    await publish();
    expect(await reclaim(), 0);
    expect(client.files[SyncPaths.data(oldPath)], oldBytes);
  });
}
