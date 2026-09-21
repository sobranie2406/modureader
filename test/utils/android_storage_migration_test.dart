import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/utils/get_path/android_storage.dart';
import 'package:anx_reader/utils/get_path/android_storage_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.external);
  final String? external;
  @override
  Future<String?> getExternalStoragePath() async => external;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, documents, databases, destination;
  AndroidStorageMigration migration() => AndroidStorageMigration(
      documents: documents, databases: databases, destination: destination);
  File stateFile() =>
      File('${documents.path}/${AndroidStorageMigration.stateName}');
  File receiptFile() =>
      File('${destination.path}/${AndroidStorageMigration.receiptName}');
  Future<File> put(Directory dir, String relative, String text) async {
    final file = File('${dir.path}/$relative');
    await file.parent.create(recursive: true);
    return file.writeAsString(text);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-android-storage-');
    documents = await Directory('${root.path}/private/app_flutter')
        .create(recursive: true);
    databases = await Directory('${root.path}/private/databases').create();
    destination = Directory('${root.path}/Android/data/com.modu.reader/files');
  });
  tearDown(() async => root.delete(recursive: true));

  test(
      'moves all content categories without changing relative paths or sources',
      () async {
    final content = {
      'file/书籍.epub': 'book',
      'cover/cover.png': 'cover',
      'font/俗日困我 盛夏邮青.ttf': 'font',
      'bgimg/paper.png': 'background',
      'ai/history.json': 'conversation',
      'knowledge/42.json': 'index',
      'models/bge/model_quantized.onnx': 'weights',
      'dictionaries/custom.sqlite': 'dictionary',
      'future-directory/data.bin': 'future data',
      'modu.log': 'log',
    };
    for (final entry in content.entries) {
      await put(documents, entry.key, entry.value);
    }
    await put(databases, 'app_database.db', 'database');
    await put(databases, 'app_database.db-wal', 'wal');
    await put(databases, 'app_database.db-shm', 'shm');
    await put(Directory('${root.path}/private/shared_prefs'),
        'FlutterSharedPreferences.xml', 'private credentials');
    await migration().run();
    for (final entry in content.entries) {
      expect(await File('${destination.path}/${entry.key}').readAsString(),
          entry.value);
      expect(await File('${documents.path}/${entry.key}').readAsString(),
          entry.value);
    }
    expect(
        await File('${destination.path}/databases/app_database.db-wal')
            .readAsString(),
        'wal');
    expect(
        await File('${destination.path}/databases/app_database.db-shm')
            .readAsString(),
        'shm');
    expect(
        await Directory('${destination.path}/shared_prefs').exists(), isFalse);
    expect(
        await File('${destination.path}/${AndroidStorageMigration.stateName}')
            .exists(),
        isFalse);
    expect(jsonDecode(await stateFile().readAsString())['complete'], isTrue);
    expect(
        await destination
            .list()
            .where((f) => f.path.contains('.modu-migration-'))
            .isEmpty,
        isTrue);
  });

  test('fresh install succeeds without a legacy database', () async {
    await migration().run();
    await migration().run();
    expect(await destination.exists(), isTrue);
    expect(jsonDecode(await stateFile().readAsString())['database'], isFalse);
  });

  test('committed migration never recopies stale private data on restart',
      () async {
    await put(documents, 'file/book.epub', 'old');
    await put(databases, 'app_database.db', 'old database');
    await migration().run();
    await put(destination, 'file/book.epub', 'new replacement');
    await put(
        destination, 'databases/app_database.db', 'new notes and progress');
    await migration().run();
    expect(
        await File('${destination.path}/databases/app_database.db')
            .readAsString(),
        'new notes and progress');
    expect(await File('${destination.path}/file/book.epub').readAsString(),
        'new replacement');
  });

  test(
      'different existing file is not overwritten; retry resumes verified copies',
      () async {
    await put(documents, 'file/book.epub', 'source');
    await put(destination, 'file/book.epub', 'conflicting target');
    await expectLater(migration().run(), throwsA(isA<FileSystemException>()));
    expect(await File('${documents.path}/file/book.epub').readAsString(),
        'source');
    expect(await File('${destination.path}/file/book.epub').readAsString(),
        'conflicting target');
    expect(await receiptFile().exists(), isFalse);
    // Simulate resolving the conflict / a complete file from an interrupted run.
    await put(destination, 'file/book.epub', 'source');
    await migration().run();
    expect(jsonDecode(await stateFile().readAsString())['complete'], isTrue);
  });

  test('interrupted publication finishes without overwriting verified data',
      () async {
    await put(documents, 'file/book.epub', 'original');
    await migration().run();
    final state = jsonDecode(await stateFile().readAsString());
    state['complete'] = false;
    await stateFile().writeAsString(jsonEncode(state));
    await migration().run();
    expect(jsonDecode(await stateFile().readAsString())['complete'], isTrue);
  });

  test(
      'lost external data fails closed instead of restoring stale private copy',
      () async {
    await put(databases, 'app_database.db', 'old database');
    await migration().run();
    await receiptFile().delete();
    await expectLater(migration().run(), throwsA(isA<FileSystemException>()));
  });

  test('missing migrated database fails rather than opening an empty library',
      () async {
    await put(databases, 'app_database.db', 'database');
    await migration().run();
    await File('${destination.path}/databases/app_database.db').delete();
    await expectLater(migration().run(), throwsA(isA<FileSystemException>()));
    expect(await File('${destination.path}/databases/app_database.db').exists(),
        isFalse);
  });

  test('unmounted/changed target does not silently switch storage', () async {
    await migration().run();
    final other = AndroidStorageMigration(
        documents: documents,
        databases: databases,
        destination: Directory('${root.path}/other'));
    await expectLater(other.run(), throwsA(isA<FileSystemException>()));
  });

  test('invalid private state is not discarded', () async {
    await stateFile().writeAsString('invalid state');
    await expectLater(migration().run(), throwsA(isA<FormatException>()));
    expect(await stateFile().readAsString(), 'invalid state');
  });

  test('symbolic links cannot escape destination', () async {
    await put(documents, 'file/book.epub', 'source');
    await destination.create(recursive: true);
    final outside = await Directory('${root.path}/outside').create();
    await Link('${destination.path}/file').create(outside.path);
    await expectLater(migration().run(), throwsA(isA<FileSystemException>()));
    expect(await outside.list().isEmpty, isTrue);
  });

  test('source symbolic links are not followed or silently omitted', () async {
    final outside = await put(root, 'outside.txt', 'not app data');
    await Link('${documents.path}/link').create(outside.path);
    await expectLater(migration().run(), throwsA(isA<FileSystemException>()));
    expect(await receiptFile().exists(), isFalse);
  });

  test('overlapping source and destination rejected', () async {
    await expectLater(
        AndroidStorageMigration(
                documents: documents,
                databases: databases,
                destination: Directory('${documents.path}/child'))
            .run(),
        throwsA(isA<FileSystemException>()));
  });

  test('real SQLite WAL preserves notes and latest reading position', () async {
    final db = sqlite3.open('${databases.path}/app_database.db');
    try {
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA wal_autocheckpoint=0');
      db.execute('CREATE TABLE notes (text TEXT, position TEXT)');
      db.execute("INSERT INTO notes VALUES ('测试笔记', 'epubcfi(/6/4!/4/2)')");
      // Keep WAL on disk, with no concurrent writer during migration.
      expect(await File('${databases.path}/app_database.db-wal').length(),
          greaterThan(0));
      await migration().run();
      final moved =
          sqlite3.open('${destination.path}/databases/app_database.db');
      try {
        expect(
            moved.select('PRAGMA integrity_check').single.values.single, 'ok');
        expect(moved.select('SELECT * FROM notes').single['text'], '测试笔记');
        expect(moved.select('SELECT * FROM notes').single['position'],
            'epubcfi(/6/4!/4/2)');
      } finally {
        moved.dispose();
      }
    } finally {
      db.dispose();
    }
  });

  test(
      'external directory uses platform path and never falls back to private data',
      () async {
    final previous = PathProviderPlatform.instance;
    try {
      PathProviderPlatform.instance = _Paths(destination.path);
      expect((await androidDataDirectory()).path, destination.path);
      PathProviderPlatform.instance = _Paths(null);
      await expectLater(
          androidDataDirectory(), throwsA(isA<FileSystemException>()));
    } finally {
      PathProviderPlatform.instance = previous;
    }
  });
}
