import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/local_data/portable_backup.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../sync/row_sync_test.dart' show fixture, bookRow, noteRow;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PrivateLibrary privacy;
  setUp(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    privacy = PrivateLibrary(preferences: Prefs().prefs)..setPluginActive(true);
    await privacy.unlock();
    await privacy.setBooksPrivate([
      Book.mock().copyWith(id: 2, filePath: 'file/private.epub', md5: 'private')
    ], true);
    temp = await Directory.systemTemp.createTemp('portable-private-backup-');
  });
  tearDown(() async {
    privacy.dispose();
    await temp.delete(recursive: true);
  });

  test(
      'export copy removes private rows, associations and deleted bytes while keeping the recovery source and public identities',
      () async {
    final live = File('${temp.path}/recovery.db');
    final db = await fixture(path: live.path);
    const secret = 'PRIVATE_BACKUP_SENTINEL';
    await db.update('tb_books', {'cover_path': 'cover/public.png'},
        where: 'id=1');
    await db.insert('tb_groups',
        {'id': 7, 'name': '${secret}_GROUP', 'parent_id': 0, 'is_deleted': 0});
    await db.insert('tb_books', {
      ...bookRow(2, md5: 'private'),
      'title': '${secret}_BOOK',
      'group_id': 7,
      'cover_path': 'cover/private.png'
    });
    await db.insert('tb_notes', noteRow(1, 'public-note'));
    await db.insert('tb_notes', noteRow(2, '${secret}_NOTE'));
    await db.insert('tb_reading_time', {
      'id': 1,
      'book_id': 1,
      'date': '2026-11-15',
      'reading_time': 3,
      'round': 1
    });
    await db.insert('tb_reading_time', {
      'id': 2,
      'book_id': 2,
      'date': '${secret}_TIME',
      'reading_time': 5,
      'round': 1
    });
    await db.insert('tb_reading_rounds',
        {'book_id': 2, 'round_number': 1, 'end_position': '${secret}_ROUND'});
    await db.insert('tb_styles',
        {'id': 20, 'font_size': 1, 'font_family': '${secret}_TAG'});
    await db.insert('tb_styles',
        {'id': 21, 'font_size': 2, 'line_height': 2, 'letter_spacing': 20});
    await db
        .execute('CREATE TABLE document_cache(book_id INTEGER, content TEXT)');
    await db
        .insert('document_cache', {'book_id': 1, 'content': 'public-cache'});
    await db
        .insert('document_cache', {'book_id': 2, 'content': '${secret}_OCR'});
    await db.execute(
        'CREATE TABLE modu_replaced_book_files(book_id TEXT, old_path TEXT, old_md5 TEXT)');
    await db.insert('modu_replaced_book_files',
        {'book_id': 'md5:private', 'old_path': 'file/${secret}_OLD.epub'});
    await db.insert('modu_replaced_book_files', {
      'book_id': 'md5:same-content',
      'old_path': 'file/${secret}_OLDER.epub',
      'old_md5': 'private'
    });
    await db.insert('modu_replaced_book_files', {
      'book_id': 'md5:same-content',
      'old_path': 'file/public-old.epub',
      'old_md5': 'public-old'
    });
    await RowSyncStore(db).snapshot();
    final before = await db.query('modu_sync_records',
        where: "kind='book' AND local_id=1");
    await db.close();
    final original = await live.readAsBytes();
    expect(latin1.decode(original), contains(secret));
    final exported = await live.copy('${temp.path}/export.db');
    privacy.lock();
    privacy.setPluginActive(false);
    final selection = await sanitizePortableBackup(exported,
        library: privacy, factory: databaseFactoryFfi);
    expect(selection.publicBookIds, {1});
    expect(selection.assets, {'file/same-content.epub', 'cover/public.png'});
    expect(await live.readAsBytes(), original,
        reason: 'local recovery remains complete');
    expect(
        latin1.decode(await exported.readAsBytes()), isNot(contains(secret)));
    final result = await databaseFactoryFfi.openDatabase(exported.path,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      expect((await result.query('tb_books')).map((row) => row['id']), [1]);
      for (final table in ['tb_notes', 'tb_reading_time', 'document_cache']) {
        expect((await result.query(table)).map((row) => row['book_id']), [1]);
      }
      expect(await result.query('tb_reading_rounds'), isEmpty);
      expect(
          (await result.query('modu_replaced_book_files'))
              .map((row) => row['old_path']),
          ['file/public-old.epub']);
      expect(await result.query('tb_styles'), isEmpty);
      expect((await result.query('tb_groups')).map((row) => row['id']), [0]);
      final after = (await result.query('modu_sync_records',
              where: "kind='book' AND local_id=1"))
          .single;
      for (final key in ['sync_id', 'clock', 'revision']) {
        expect(after[key], before.single[key]);
      }
      expect(
          await result.query('modu_sync_records',
              where: "sync_id='md5:private'"),
          isEmpty);
      await result.insert('tb_notes', noteRow(1, 'after-restore'));
      expect(
          (await result.query('modu_sync_records', where: "kind='note'"))
              .length,
          2,
          reason: 'original tracking triggers remain');
    } finally {
      await result.close();
    }
    for (final suffix in ['-wal', '-shm', '-journal']) {
      expect(await File('${exported.path}$suffix').exists(), false);
    }
  });

  test(
      'portable preferences retain public per-book settings and exclude private or unknown local IDs',
      () {
    final result = portableBackupPreferences({
      'privateLibrary_v1': {'type': 'string', 'value': 'secret'},
      'ttsRoleBook_1': {'type': 'string', 'value': 'public'},
      'ttsRoleBook_2': {'type': 'string', 'value': 'private'},
      'ttsRoleBook_99': {'type': 'string', 'value': 'unknown'},
      'bookTranslationModes': {
        'type': 'string',
        'value': '{"1":"a","2":"b","99":"c"}'
      },
      'ordinary': true,
    }, {
      1
    });
    expect(result.keys.toSet(),
        {'ttsRoleBook_1', 'bookTranslationModes', 'ordinary'});
    expect(
        jsonDecode((result['bookTranslationModes'] as Map)['value'] as String),
        {'1': 'a'});
  });

  test(
      'private local IDs remain excluded after replacement even in a legacy copy without sync metadata',
      () async {
    final file = File('${temp.path}/legacy-export.db');
    final db = await fixture(path: file.path, install: false);
    await db.insert('tb_books', {
      ...bookRow(2, md5: 'replacement'),
      'title': 'PRIVATE_REPLACED_CONTENT'
    });
    await db.insert('tb_notes', noteRow(2, 'PRIVATE_REPLACED_NOTE'));
    await db.close();
    final selection = await sanitizePortableBackup(file,
        library: privacy, factory: databaseFactoryFfi);
    expect(selection.publicBookIds, {1});
    expect(selection.assets, {'file/same-content.epub'});
    expect(latin1.decode(await file.readAsBytes()),
        isNot(contains('PRIVATE_REPLACED')));
  });

  test(
      'portable AI history keeps explicit public sources and excludes protected, private and unscoped records even while unlocked',
      () async {
    await privacy.protectHistory('protected');
    final directory = await Directory('${temp.path}/ai').create();
    await File('${directory.path}/ai_history.json').writeAsString(jsonEncode([
      {
        'id': 'public',
        'readingRequest': {'bookId': 1},
        'messages': ['public text']
      },
      {
        'id': 'private',
        'readingRequest': {'bookId': 2},
        'messages': ['private text']
      },
      {
        'id': 'protected',
        'readingRequest': {'bookId': 1},
        'messages': ['previously private text']
      },
      {
        'id': 'unscoped',
        'messages': ['unknown text']
      },
    ]));
    final data = await portableBackupAiHistory(
        temp, const PortableBackupSelection({1}, {}),
        library: privacy);
    expect((jsonDecode(data) as List).map((row) => row['id']), ['public']);
    await File('${directory.path}/ai_history.json')
        .writeAsString('{broken private text');
    expect(
        await portableBackupAiHistory(
            temp, const PortableBackupSelection({1}, {}),
            library: privacy),
        '[]');
  });
}
