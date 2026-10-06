import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../service/sync/row_sync_test.dart' show MemorySyncClient, bookRow;

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory root;
  late PathProviderPlatform previousPaths;
  late String previousDocumentPath;
  String getPath() => '${root.path}/databases/app_database.db';

  setUp(() async {
    await DBHelper.close();
    root = await Directory.systemTemp.createTemp('modu-db-startup-');
    previousPaths = PathProviderPlatform.instance;
    previousDocumentPath = documentPath;
    PathProviderPlatform.instance = _Paths(root.path);
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await initBasePath();
  });
  tearDown(() async {
    await DBHelper.close();
    PathProviderPlatform.instance = previousPaths;
    documentPath = previousDocumentPath;
    await root.delete(recursive: true);
  });

  test('fresh install shares one complete schema across concurrent callers',
      () async {
    final handles = await Future.wait(List.generate(20,
        (index) => index.isEven ? DBHelper().initDB() : DBHelper().database));
    final db = handles.first;
    expect(handles.every((handle) => identical(handle, db)), isTrue);
    expect(await db.getVersion(), currentDbVersion);
    expect(await db.query('tb_notes'), isEmpty);
    expect(await db.query('tb_groups'), hasLength(1));
    expect(await db.query(syncRecordsTable), isNotEmpty);
    expect(
        (await db.rawQuery('PRAGMA table_info(tb_notes)'))
            .map((column) => column['name']),
        contains('reader_note'));
    expect(identical(await DBHelper().initDB(), db), isTrue);
    expect(Directory('${root.path}/file').existsSync(), isTrue);
    await DBHelper().repairLegacyBookCovers();
  });

  test('close waits for an in-flight open and later opens remain usable',
      () async {
    final opening = DBHelper().initDB();
    final closing = DBHelper.close();
    final reopening = DBHelper().database;
    final original = await opening;
    await closing;
    final reopened = await reopening;
    expect(original.isOpen, isFalse);
    expect(reopened.isOpen, isTrue);
    expect(await reopened.query('tb_notes'), isEmpty);
  });

  for (final atomic in [true, false]) {
    test(
        'two fresh installs bootstrap and keep syncing new books (atomic=$atomic)',
        () async {
      final phone = await DBHelper().database;
      var tablet = await databaseFactoryFfi.openDatabase(
          '${root.path}/tablet.db',
          options: OpenDatabaseOptions(
              version: currentDbVersion,
              onCreate: (db, version) =>
                  DBHelper().onUpgradeDatabase(db, 0, version)));
      final client = MemorySyncClient()..atomic = atomic;
      final phoneCache = await Directory('${root.path}/phone-sync').create();
      final tabletCache = await Directory('${root.path}/tablet-sync').create();
      Future<void> sync(Database db, Directory cache) async {
        await RowSyncEngine(
                store: RowSyncStore(db), client: client, cache: cache)
            .synchronize();
      }

      Future<void> expectBooks(Database db, int count) async {
        expect(await db.query('tb_books', where: 'is_deleted=0'),
            hasLength(count));
      }

      try {
        // No legacy import or pre-seeded books before installing sync triggers.
        expect(await phone.query('tb_books'), isEmpty);
        expect(await tablet.query('tb_books'), isEmpty);
        expect(client.files, isEmpty);
        await phone.insert(
            'tb_books', bookRow(1, md5: 'phone-first')..remove('id'));
        await sync(phone, phoneCache);
        await sync(tablet, tabletCache);
        await expectBooks(tablet, 1);
        expect(File('${root.path}/file/phone-first.epub').existsSync(), isFalse,
            reason:
                'metadata creates an undownloaded book without local bytes');
        await tablet.close();
        tablet =
            await databaseFactoryFfi.openDatabase('${root.path}/tablet.db');
        await sync(tablet, tabletCache);
        await expectBooks(tablet, 1);
        await tablet.insert(
            'tb_books', bookRow(2, md5: 'tablet-second')..remove('id'));
        await sync(tablet, tabletCache);
        await sync(phone, phoneCache);
        await expectBooks(phone, 2);
        await phone.insert(
            'tb_books', bookRow(3, md5: 'phone-third')..remove('id'));
        await sync(phone, phoneCache);
        await sync(tablet, tabletCache);
        await expectBooks(tablet, 3);
        expect(
            sameSyncRecords(await RowSyncStore(phone).snapshot(),
                await RowSyncStore(tablet).snapshot()),
            isTrue);
      } finally {
        await tablet.close();
      }
    });
  }

  Future<void> legacy(int version) async {
    final db = await databaseFactoryFfi.openDatabase(getPath());
    for (final sql in [
      createBookSQL,
      createNoteSQL,
      createThemeSQL,
      createStyleSQL,
      createReadingTimeSQL
    ]) {
      await db.execute(sql);
    }
    await db.execute('ALTER TABLE tb_books ADD COLUMN rating REAL');
    if (version == 7) {
      await db.execute('ALTER TABLE tb_books ADD COLUMN group_id INTEGER');
      await db.execute('ALTER TABLE tb_books ADD COLUMN file_md5 TEXT');
      await db.execute('ALTER TABLE tb_notes ADD COLUMN reader_note TEXT');
      await db.execute(createGroupSQL);
      await db.insert('tb_groups', {'id': 0, 'name': 'Root', 'is_deleted': 0});
    }
    await db.insert('tb_books', {
      'id': 41,
      'title': 'Synthetic migration book',
      'author': 'Test',
      'cover_path': 'cover/missing.png',
      'file_path': 'file/missing.epub',
      'is_deleted': 0,
      'last_read_position': 'chapter2',
      'reading_percentage': 0.25,
      'create_time': '2026-09-01T00:00:00',
      'update_time': '2026-09-01T00:00:00'
    });
    await db.insert('tb_notes', {
      'id': 9,
      'book_id': 41,
      'content': 'Keep this note',
      'cfi': 'chapter2',
      'type': 'highlight',
      'create_time': '2026-09-01T00:00:00',
      'update_time': '2026-09-01T00:00:00'
    });
    await db.setVersion(version);
    await db.close();
  }

  for (final version in [3, 7]) {
    test(
        'version $version upgrade preserves books and notes without reentrant DAO opens',
        () async {
      await legacy(version);
      final db = await DBHelper().initDB();
      expect(await db.getVersion(), 8);
      expect((await db.query('tb_books')).single['last_read_position'],
          'chapter2');
      expect((await db.query('tb_notes')).single['content'], 'Keep this note');
      expect(
          (await db
              .query(syncRecordsTable, where: 'kind = ?', whereArgs: ['note'])),
          hasLength(1));
      await DBHelper().repairLegacyBookCovers();
      expect(db.isOpen, isTrue);
    });
  }

  test(
      'failed opening preserves the original file and permits an explicit retry',
      () async {
    final file = File(getPath());
    await file.parent.create(recursive: true);
    await file.writeAsString('intentionally invalid test database');
    await expectLater(DBHelper().initDB(), throwsA(anything));
    expect(await file.readAsString(), 'intentionally invalid test database');
    await file.rename('${file.path}.test-backup');
    final db = await DBHelper().initDB();
    expect(await db.getVersion(), 8);
  });
}
