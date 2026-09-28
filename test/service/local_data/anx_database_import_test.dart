import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/service/local_data/anx_database_import.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import '../sync/row_sync_test.dart' show fixture, noteRow;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late Database target;
  late Directory targetRoot;
  final bookBytes = utf8.encode('synthetic ANX book contents');
  final digest = md5.convert(bookBytes).toString();
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('modu-anx-test-');
    targetRoot = await Directory('${temp.path}/modu').create();
    target = await fixture(path: '${targetRoot.path}/current.db');
  });
  tearDown(() async {
    await target.close();
    await temp.delete(recursive: true);
  });

  Future<File> backup(
      {bool missing = false,
      int version = 7,
      String filePath = 'file/anx.epub',
      bool trigger = false,
      bool wal = false,
      String? extraPath}) async {
    final folder = await temp.createTemp('source-');
    final file = File('${folder.path}/app_database.db');
    final db = await fixture(path: file.path, install: false);
    if (wal) {
      await db.rawQuery('PRAGMA journal_mode=WAL');
      await db.rawQuery('PRAGMA wal_autocheckpoint=0');
    }
    await db.setVersion(version);
    await db.insert('tb_groups',
        {'id': 4, 'name': 'ANX folder', 'parent_id': 0, 'is_deleted': 0});
    await db.update('tb_books', {
      'file_md5': null,
      'file_path': filePath,
      'title': 'ANX book',
      'group_id': 4,
      'last_read_position': 'anx-chapter-3',
      'reading_percentage': .4
    });
    await db.insert(
        'tb_notes', {...noteRow(1, 'epubcfi(anx)'), 'reader_note': 'ANX note'});
    await db.insert('tb_reading_time',
        {'id': 1, 'book_id': 1, 'date': '2026-09-01', 'reading_time': 20});
    await db.insert('tb_reading_time',
        {'id': 2, 'book_id': 1, 'date': '2026-09-01', 'reading_time': 30});
    await db.insert(
        'tb_styles', {'id': 1, 'font_size': 1, 'font_family': 'ANX tag'});
    await db.insert('tb_styles',
        {'id': 2, 'font_size': 2, 'line_height': 1, 'letter_spacing': 1});
    if (trigger) {
      await db.execute(
          'CREATE TRIGGER unknown_trigger AFTER INSERT ON tb_books BEGIN DELETE FROM tb_notes; END');
    }
    if (!wal) await db.close();
    final archive = Archive();
    final bytes = await file.readAsBytes();
    archive
        .addFile(ArchiveFile('databases/app_database.db', bytes.length, bytes));
    if (wal) {
      final bytes = await File('${file.path}-wal').readAsBytes();
      archive.addFile(
          ArchiveFile('databases/app_database.db-wal', bytes.length, bytes));
      await db.close();
    }
    if (!missing) {
      archive
          .addFile(ArchiveFile('file/anx.epub', bookBytes.length, bookBytes));
    }
    archive.addFile(ArchiveFile('anx_shared_prefs.json', 2, utf8.encode('{}')));
    if (extraPath != null) archive.addFile(ArchiveFile(extraPath, 1, [1]));
    final zip = File('${folder.path}/backup.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive)!);
    return zip;
  }

  Future<AnxDatabaseImport> prepare(File zip) async {
    final result = await AnxDatabaseImport.prepare(
        cache: temp, zip: zip, factory: databaseFactoryFfi);
    addTearDown(result.dispose);
    return result;
  }

  test('imports complete ZIP; retains original and creates recovery snapshot',
      () async {
    final zip = await backup();
    final original = await zip.readAsBytes();
    final plan = await prepare(zip);
    expect(plan.books, 1);
    expect(plan.notes, 1);
    expect((await target.query('tb_books')).length, 1); // Preview is read-only.
    final result = await plan.apply(target, targetRoot);
    expect(result.addedBooks, 1);
    expect(result.addedNotes, 1);
    final book = (await target
            .query('tb_books', where: 'file_md5=?', whereArgs: [digest]))
        .single;
    expect(await File('${targetRoot.path}/${book['file_path']}').readAsBytes(),
        bookBytes);
    expect((book['file_path'] as String).split('/').length, 2);
    expect(book['last_read_position'], 'anx-chapter-3');
    expect(book['group_id'], isNot(0));
    expect((await target.query('tb_notes')).single['book_id'], book['id']);
    expect((await target.query('tb_reading_time')).single['reading_time'], 50);
    expect(
        (await target.query('tb_styles', where: 'font_size=2'))
            .single['line_height'],
        book['id']);
    final saved = await databaseFactoryFfi.openDatabase(result.backupPath,
        options: OpenDatabaseOptions(readOnly: true));
    expect((await saved.query('tb_books')).length, 1);
    expect(await saved.query('tb_notes'), isEmpty);
    await saved.close();
    expect(await zip.readAsBytes(), original);
    expect(await File('${targetRoot.path}/anx_shared_prefs.json').exists(),
        isFalse);
  });

  test('reimport does not duplicate or overwrite local edits', () async {
    final zip = await backup();
    await (await prepare(zip)).apply(target, targetRoot);
    await target.update(
        'tb_books', {'last_read_position': 'local-new', 'group_id': 0},
        where: 'file_md5=?', whereArgs: [digest]);
    await target.update('tb_notes', {'reader_note': 'local edit'});
    final result = await (await prepare(zip)).apply(target, targetRoot);
    expect(result.addedBooks, 0);
    expect(result.addedNotes, 0);
    expect(
        (await target
                .query('tb_books', where: 'file_md5=?', whereArgs: [digest]))
            .single['last_read_position'],
        'local-new');
    expect(
        (await target.query('tb_notes')).single['reader_note'], 'local edit');
    expect((await target.query('tb_reading_time')).single['reading_time'], 50);
  });

  test('identical existing content preserves path, progress and folder',
      () async {
    await target.update('tb_books', {
      'file_md5': digest,
      'file_path': 'file/existing.epub',
      'last_read_position': 'local-chapter-9',
      'reading_percentage': .9
    });
    final plan = await prepare(await backup());
    final result = await plan.apply(target, targetRoot);
    expect(result.addedBooks, 0);
    final book = (await target.query('tb_books', where: 'is_deleted=0')).single;
    expect(book['file_path'], 'file/existing.epub');
    expect(book['last_read_position'], 'local-chapter-9');
    expect(book['group_id'], 0);
    expect(await File('${targetRoot.path}/file/existing.epub').readAsBytes(),
        bookBytes);
    expect((await target.query('tb_notes')).single['book_id'], book['id']);
  });

  test('missing book is listed; no orphan notes/history imported', () async {
    final plan = await prepare(await backup(missing: true));
    expect(plan.missingBooks, ['ANX book']);
    expect(plan.books, 0);
    expect(plan.notes, 0);
    expect(plan.records.where((r) => r.kind == 'time'), isEmpty);
  });

  test('reads committed records present only in backed-up WAL', () async {
    final plan = await prepare(await backup(wal: true));
    expect(plan.books, 1);
    expect(plan.notes, 1);
    await plan.apply(target, targetRoot);
    expect((await target.query('tb_notes')).single['reader_note'], 'ANX note');
  });

  for (final unsafe in ['../outside', 'file/../../outside', 'C:/outside']) {
    test('rejects unsafe ZIP entry $unsafe without target writes', () async {
      final before = await RowSyncStore(target).snapshot();
      await expectLater(
          prepare(await backup(extraPath: unsafe)), throwsFormatException);
      expect(sameSyncRecords(before, await RowSyncStore(target).snapshot()),
          isTrue);
    });
  }
  test('rejects unsupported schema and source triggers', () async {
    await expectLater(
        prepare(await backup(version: 99)), throwsFormatException);
    await expectLater(
        prepare(await backup(trigger: true)), throwsFormatException);
  });
  test('rejects traversal in database asset paths', () async {
    await expectLater(prepare(await backup(filePath: 'file/../outside')),
        throwsFormatException);
  });
  test('rebases legacy Android absolute asset paths', () async {
    final plan = await prepare(await backup(
        filePath:
            '/data/user/0/com.anxcye.anx_reader/app_flutter/file/anx.epub'));
    expect(plan.books, 1);
    expect(plan.missingBooks, isEmpty);
  });
  test('failed database merge rolls back library and only new assets',
      () async {
    final plan = await prepare(await backup());
    plan.records
        .add(const RowSyncRecord('note', 'bad', 1, 'legacy', false, {}));
    final before = await RowSyncStore(target).snapshot();
    await expectLater(plan.apply(target, targetRoot), throwsFormatException);
    expect(
        sameSyncRecords(before, await RowSyncStore(target).snapshot()), isTrue);
    expect(await target.query('tb_notes'), isEmpty);
    final files = await targetRoot
        .list(recursive: true)
        .where((f) => f is File && f.path.endsWith('.epub'))
        .toList();
    expect(files, isEmpty);
  });

  for (final conflict in [false, true]) {
    test('ANX duplicate database entries: conflict=$conflict', () async {
      final original =
          ZipDecoder().decodeBytes(await (await backup()).readAsBytes());
      final sqliteBytes =
          original.findFile('databases/app_database.db')!.content as List<int>;
      final source = File('${temp.path}/duplicate-source.db');
      await source.writeAsBytes(sqliteBytes);
      final zip = File('${temp.path}/duplicates.zip');
      final encoder = ZipFileEncoder()..create(zip.path);
      await encoder.addFile(source, 'databases/app_database.db');
      if (conflict) await source.writeAsBytes([1, 2, 3]);
      await encoder.addFile(source, 'databases/app_database.db');
      final book = File('${temp.path}/payload');
      await book.writeAsBytes(bookBytes);
      await encoder.addFile(book, 'file/anx.epub');
      encoder.close();
      if (conflict) {
        await expectLater(prepare(zip), throwsFormatException);
      } else {
        expect((await prepare(zip)).books, 1);
      }
    });
  }

  test('case-insensitive conflicting ZIP paths are rejected on all platforms',
      () async {
    await expectLater(prepare(await backup(extraPath: 'FILE/anx.epub')),
        throwsFormatException);
  });

  test('corrupt book payload fails CRC before it can enter the library',
      () async {
    final archive =
        ZipDecoder().decodeBytes(await (await backup()).readAsBytes());
    archive.findFile('file/anx.epub')!.compress = false;
    final bytes = ZipEncoder().encode(archive)!;
    var found = false;
    for (var i = 0; i <= bytes.length - bookBytes.length; i++) {
      if (List.generate(bookBytes.length, (offset) => bytes[i + offset])
              .join(',') ==
          bookBytes.join(',')) {
        bytes[i] ^= 1;
        found = true;
        break;
      }
    }
    expect(found, true);
    final zip = File('${temp.path}/corrupt.zip');
    await zip.writeAsBytes(bytes);
    await expectLater(prepare(zip), throwsFormatException);
    expect((await target.query('tb_books')).length, 1);
  });

  test('target asset directory symlink cannot write outside Modu', () async {
    final outside = await Directory('${temp.path}/outside').create();
    await Link('${targetRoot.path}/file').create(outside.path);
    final plan = await prepare(await backup());
    await expectLater(plan.apply(target, targetRoot), throwsFormatException);
    expect(await outside.list().toList(), isEmpty);
    expect((await target.query('tb_books')).length, 1);
  });
}
