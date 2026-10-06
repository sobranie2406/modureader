import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/service/convert_to_epub/create_epub.dart';
import 'package:anx_reader/service/convert_to_epub/section.dart';
import 'package:anx_reader/service/convert_to_epub/markdown/convert_from_markdown.dart';
import 'package:anx_reader/service/sync/converted_book_checksum.dart';
import 'package:anx_reader/service/sync/local_book_download.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show fixture, bookRow, noteRow, MemorySyncClient;

class _BookDao extends BookDao {
  _BookDao(this.db);
  final Database db;
  @override
  Future<List<T>> rawQueryList<T>(String sql,
          {List<Object?>? arguments,
          required T Function(Map<String, dynamic>) mapper}) async =>
      (await db.rawQuery(sql, arguments)).map(mapper).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late Directory root;
  const source = '# Synthetic book\n\n## Chapter one\n\n原创测试内容。';
  final sourceHash = md5.convert(utf8.encode(source)).toString();
  File local(String path) => File('${root.path}/$path');
  Future<void> addLegacy(List<int> bytes, {String extension = 'epub'}) async {
    await db.insert('tb_books', {
      ...bookRow(2, md5: sourceHash),
      'file_path': 'file/converted.$extension',
      'last_read_position': 'epubcfi(/6/2!/4/2)',
      'reading_percentage': 0.42,
    });
    final file = local('file/converted.$extension');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    await db.insert('tb_notes', noteRow(2, 'existing-highlight'));
  }

  Future<int> repair() =>
      ConvertedBookChecksum(db).repairLocalBooks(localFile: local);
  setUp(() async {
    db = await fixture();
    root = await Directory.systemTemp.createTemp('modu-converted-checksum-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await db.close();
    await root.delete(recursive: true);
  });

  for (final format in ['txt', 'markdown']) {
    test('$format legacy repair preserves book, notes, position and sync IDs',
        () async {
      final bytes = format == 'txt'
          ? await (await createEpub(
                  'Synthetic', 'Test', [Section('第一章', source, 1)]))
              .readAsBytes()
          : markdownToEpub(source, fallbackTitle: 'Synthetic');
      await addLegacy(bytes);
      final before = (await db.query('tb_books', where: 'id=2')).single;
      final notes = await db.query('tb_notes');
      final records = await RowSyncStore(db).snapshot();
      final originalIds = {for (final r in records) r.key};
      await expectLater(
          LocalBookDownload().ensure(local('other/failed.epub'),
              expectedMd5: sourceHash, download: (file) async {
            await file.writeAsBytes(bytes);
          }),
          throwsA(isA<BookFileIntegrityException>()));

      expect(await repair(), 1);
      final after = (await db.query('tb_books', where: 'id=2')).single;
      expect(after['file_md5'], md5.convert(bytes).toString());
      expect(
          {...after}
            ..remove('file_md5')
            ..remove('update_time'),
          {...before}
            ..remove('file_md5')
            ..remove('update_time'));
      expect(await db.query('tb_notes'), notes);
      expect({for (final r in await RowSyncStore(db).snapshot()) r.key},
          originalIds);
      expect(await local('file/converted.epub').readAsBytes(), bytes);
      expect((await _BookDao(db).getBookByMd5(sourceHash))!.id, 2);
      expect((await _BookDao(db).getBookByMd5(after['file_md5'] as String))!.id,
          2);
      expect(await repair(), 0);

      final other = await fixture(bookId: 11);
      try {
        await RowSyncStore(other)
            .merge(records); // other device already has legacy entry
        await RowSyncStore(other).merge(await RowSyncStore(db).snapshot());
        final received = (await other.query('tb_books',
                where: 'file_path=?', whereArgs: ['file/converted.epub']))
            .single;
        expect(received['last_read_position'], before['last_read_position']);
        expect(received['reading_percentage'], 0.42);
        expect(
            (await other.query('tb_notes')).single['book_id'], received['id']);
        final target = local('other/downloaded.epub');
        await LocalBookDownload()
            .ensure(target, expectedMd5: received['file_md5'] as String,
                download: (file) async {
          await file.writeAsBytes(bytes);
        });
        expect(await target.readAsBytes(), bytes);
        // Replaying a pre-repair snapshot must not undo the correction.
        await RowSyncStore(other).merge(records);
        expect(
            (await other.query('tb_books',
                    where: 'id=?', whereArgs: [received['id']]))
                .single['file_md5'],
            after['file_md5']);
      } finally {
        await other.close();
      }
    });
  }

  test('new converted imports use content checksum and source dedup identity',
      () async {
    final bytes = markdownToEpub(source, fallbackTitle: 'Synthetic');
    final actual = md5.convert(bytes).toString();
    final id = await db.transaction((txn) => ConvertedBookChecksum.insert(
        txn, {...bookRow(2, md5: actual)},
        sourceMd5: sourceHash));
    expect(
        (await db.query('tb_books', where: 'id=?', whereArgs: [id]))
            .single['file_md5'],
        actual);
    final synced = await RowSyncStore(db).snapshot();
    expect(
        synced
            .singleWhere((r) => r.kind == 'book' && r.id == 'md5:$sourceHash')
            .data['file_md5'],
        actual);
    expect((await _BookDao(db).getBookByMd5(sourceHash))!.id, id);
    await expectLater(
        db.transaction((txn) => ConvertedBookChecksum.insert(
            txn, bookRow(3, md5: actual),
            sourceMd5: sourceHash)),
        throwsStateError);
    expect(await db.query('tb_books'), hasLength(2));
    expect(sameSyncRecords(await RowSyncStore(db).snapshot(), synced), isTrue);
  });

  test('remote-only legacy books cannot be repaired without local evidence',
      () async {
    await addLegacy(markdownToEpub(source, fallbackTitle: 'Synthetic'));
    await local('file/converted.epub').delete();
    expect(await repair(), 0);
    expect((await db.query('tb_books', where: 'id=2')).single['file_md5'],
        sourceHash);
  });

  for (final atomic in [true, false]) {
    test('unchanged cloud publishes repair in same sync, atomic=$atomic',
        () async {
      final bytes = markdownToEpub(source, fallbackTitle: 'Synthetic');
      await addLegacy(bytes);
      final cloud = local('cloud.db');
      await RowSyncArchive.write(cloud.path, await RowSyncStore(db).snapshot());
      final client = MemorySyncClient()..atomic = atomic;
      client.files[RowSyncEngine.remotePath] = await cloud.readAsBytes();
      final engine = RowSyncEngine(
          store: RowSyncStore(db),
          client: client,
          cache: root,
          afterMerge: () async {
            await repair();
          });
      expect(await engine.synchronize(), RowSyncOutcome.published);
      expect(await engine.synchronize(), RowSyncOutcome.unchanged);
      final other = await fixture(bookId: 11);
      try {
        await RowSyncEngine(
                store: RowSyncStore(other), client: client, cache: root)
            .synchronize();
        final row = (await other.query('tb_books',
                where: 'file_path=?', whereArgs: ['file/converted.epub']))
            .single;
        expect(row['file_md5'], md5.convert(bytes).toString());
        expect(row['reading_percentage'], 0.42);
        expect((await other.query('tb_notes')).single['book_id'], row['id']);
      } finally {
        await other.close();
      }
    });

    test(
        'remote replacement wins over obsolete local conversion, atomic=$atomic',
        () async {
      await addLegacy(markdownToEpub(source, fallbackTitle: 'Synthetic'));
      final other = await fixture(bookId: 11);
      try {
        await RowSyncStore(other).merge(await RowSyncStore(db).snapshot());
        await other.update(
            'tb_books',
            {
              'file_path': 'file/newer.epub',
              'file_md5': md5.convert([1, 2, 3]).toString(),
              'title': 'Updated on another device'
            },
            where: 'file_path=?',
            whereArgs: ['file/converted.epub']);
        final cloud = local('cloud.db');
        await RowSyncArchive.write(
            cloud.path, await RowSyncStore(other).snapshot());
        final client = MemorySyncClient()..atomic = atomic;
        client.files[RowSyncEngine.remotePath] = await cloud.readAsBytes();
        await RowSyncEngine(
            store: RowSyncStore(db),
            client: client,
            cache: root,
            afterMerge: () async {
              await repair();
            }).synchronize();
        final row = (await db.query('tb_books', where: 'id=2')).single;
        expect(row['file_path'], 'file/newer.epub');
        expect(row['title'], 'Updated on another device');
        expect(row['file_md5'], md5.convert([1, 2, 3]).toString());
      } finally {
        await other.close();
      }
    });
  }

  test('bad ZIP CRC is rejected even if the member text is readable', () async {
    final bytes = markdownToEpub(source, fallbackTitle: 'Synthetic');
    bytes[14] ^= 1; // Local ZIP header CRC of the uncompressed mimetype member.
    await addLegacy(bytes);
    expect(await repair(), 0);
    expect((await db.query('tb_books', where: 'id=2')).single['file_md5'],
        sourceHash);
  });

  test('ordinary EPUB with mismatched hash is not auto-accepted', () async {
    final zip = Archive()
      ..addFile(ArchiveFile.string('mimetype', 'application/epub+zip'));
    await addLegacy(ZipEncoder().encode(zip)!);
    expect(await repair(), 0);
    expect((await db.query('tb_books', where: 'id=2')).single['file_md5'],
        sourceHash);
  });

  test('corrupt or truncated converted archive is not repaired', () async {
    final bytes = markdownToEpub(source, fallbackTitle: 'Synthetic');
    await addLegacy(bytes.sublist(0, bytes.length ~/ 2));
    expect(await repair(), 0);
    // Replacing damaged local bytes invalidates the migration fingerprint.
    await local('file/converted.epub').writeAsBytes(bytes);
    expect(await repair(), 1);
  });

  test('a repaired book is never re-blessed after later corruption', () async {
    final bytes = markdownToEpub(source, fallbackTitle: 'Synthetic');
    await addLegacy(bytes);
    expect(await repair(), 1);
    await local('file/converted.epub')
        .writeAsBytes(markdownToEpub('# Different', fallbackTitle: 'Changed'));
    expect(await repair(), 0);
    expect((await db.query('tb_books', where: 'id=2')).single['file_md5'],
        md5.convert(bytes).toString());
  });

  for (final extension in ['mobi', 'azw3', 'fb2', 'pdf']) {
    test('$extension is not modified by converted-book migration', () async {
      final bytes = utf8.encode('synthetic $extension passthrough fixture');
      await addLegacy(bytes, extension: extension);
      final before = await RowSyncStore(db).snapshot();
      expect(await repair(), 0);
      expect(
          sameSyncRecords(await RowSyncStore(db).snapshot(), before), isTrue);
      final target = local('other/book.$extension');
      await LocalBookDownload().ensure(target,
          expectedMd5: md5.convert(bytes).toString(), download: (file) async {
        await file.writeAsBytes(bytes);
      });
      expect(await target.readAsBytes(), bytes);
    });
  }
}
