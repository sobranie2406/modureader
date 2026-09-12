import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:anx_reader/service/sync/sync_client_base.dart';
import 'package:anx_reader/models/remote_file.dart';
import 'package:dio/dio.dart';

class MemorySyncClient extends SyncClientBase {
  @override
  String get protocolName => 'memory';
  @override
  Map<String, dynamic> get config =>
      {'url': 'memory://test', 'username': 'fixture'};
  bool atomic = true;
  @override
  Future<bool> supportsAtomicSyncWrites() async => atomic;
  final files = <String, List<int>>{};
  final revisions = <String, int>{};
  int writes = 0;
  Future<void> Function(int)? beforeWrite;
  @override
  Future<RemoteFile?> readProps(String path) async => files.containsKey(path)
      ? RemoteFile(
          path: path,
          name: path.split('/').last,
          isDir: false,
          size: files[path]!.length,
          eTag: '"${revisions[path] ?? 1}"',
          mTime: DateTime.utc(2026, 9, 9))
      : files.keys.any((key) => key.startsWith('$path/'))
          ? RemoteFile(path: path, name: path.split('/').last, isDir: true)
          : null;
  @override
  Future<void> mkdirAll(String path) async {}
  @override
  Future<List<RemoteFile>> readDir(String path) async {
    final children = <String, RemoteFile>{};
    for (final key in files.keys.where((key) => key.startsWith('$path/'))) {
      final suffix = key.substring(path.length + 1);
      final name = suffix.split('/').first;
      children[name] = RemoteFile(
          name: name,
          path: '$path/$name',
          isDir: suffix.contains('/'),
          size: files[key]!.length);
    }
    return children.values.toList();
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    files[remotePath] = await File(localPath).readAsBytes();
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath,
      {void Function(int, int)? onProgress}) async {
    await File(localPath).writeAsBytes(files[remotePath]!);
  }

  @override
  Future<void> uploadFileConditionally(String localPath, String remotePath,
      {String? expectedETag, bool createOnly = false}) async {
    writes++;
    await beforeWrite?.call(writes);
    final current = await readProps(remotePath);
    if ((createOnly && current != null) ||
        (!createOnly && current?.eTag != expectedETag)) {
      final options = RequestOptions(path: remotePath);
      throw DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 412));
    }
    files[remotePath] = await File(localPath).readAsBytes();
    revisions[remotePath] = (revisions[remotePath] ?? 1) + 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// The HTTP CAS regression below has a pre-verified endpoint. Capability probing
// against real HTTP servers is covered separately in webdav_capabilities_test.
class VerifiedWebdavClient extends WebdavClient {
  VerifiedWebdavClient(
      {required super.url, required super.username, required super.password});
  @override
  Future<bool> supportsAtomicSyncWrites() async => true;
}

class MissingValidatorClient extends MemorySyncClient {
  MissingValidatorClient(this.missingAttempts);
  final int missingAttempts;
  int attempts = 0;
  Future<void> Function()? onMissing;

  @override
  Future<RemoteFile?> readProps(String path) async {
    final file = await super.readProps(path);
    if (file == null || attempts >= missingAttempts) return file;
    return RemoteFile(
        path: file.path,
        name: file.name,
        isDir: file.isDir,
        size: file.size,
        mTime: file.mTime);
  }

  @override
  Future<void> uploadFileConditionally(String localPath, String remotePath,
      {String? expectedETag, bool createOnly = false}) async {
    attempts++;
    if (!createOnly && !WebdavClient.isStrongETag(expectedETag)) {
      await onMissing?.call();
      throw MissingSyncValidatorException();
    }
    await super.uploadFileConditionally(localPath, remotePath,
        expectedETag: expectedETag, createOnly: createOnly);
  }
}

Future<Database> fixture(
    {int bookId = 1, bool install = true, String? path}) async {
  final db = await databaseFactoryFfi.openDatabase(path ?? inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  for (final sql in [
    createBookSQL,
    createNoteSQL,
    createReadingTimeSQL,
    createGroupSQL,
    createStyleSQL,
    createThemeSQL
  ]) {
    await db.execute(sql);
  }
  await db.execute('ALTER TABLE tb_books ADD COLUMN rating REAL');
  await db.execute('ALTER TABLE tb_books ADD COLUMN group_id INTEGER');
  await db.execute('ALTER TABLE tb_books ADD COLUMN file_md5 TEXT');
  await db.execute('ALTER TABLE tb_notes ADD COLUMN reader_note TEXT');
  await db.insert('tb_groups', {'id': 0, 'name': 'Root', 'is_deleted': 0});
  await db.insert('tb_books', bookRow(bookId));
  await db.setVersion(7);
  if (install) await db.transaction((txn) => RowSyncStore.install(txn));
  return db;
}

Map<String, Object?> bookRow(int id, {String md5 = 'same-content'}) => {
      'id': id,
      'title': 'Synthetic book',
      'cover_path': '',
      'file_path': 'file/$md5.epub',
      'author': 'Test',
      'file_md5': md5,
      'group_id': 0,
      'last_read_position': 'start',
      'reading_percentage': 0.0,
      'is_deleted': 0,
      'create_time': '2026-09-01T00:00:00Z',
      'update_time': '2026-09-01T00:00:00Z',
    };
Map<String, Object?> noteRow(int bookId, String cfi) => {
      'book_id': bookId,
      'cfi': cfi,
      'content': cfi,
      'type': 'highlight',
      'create_time': '2026-09-09T00:00:00Z',
      'update_time': '2026-09-09T00:00:00Z',
    };

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database a;
  late Database b;
  late RowSyncStore sa;
  late RowSyncStore sb;
  setUp(() async {
    a = await fixture();
    b = await fixture(bookId: 77);
    sa = RowSyncStore(a);
    sb = RowSyncStore(b);
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  Future<void> converge() async {
    await sa.merge(await sb.snapshot());
    await sb.merge(await sa.snapshot());
  }

  test(
      'independent notes and books survive ID collisions; references stay local',
      () async {
    await a.insert('tb_notes', noteRow(1, 'A'));
    await b.insert('tb_notes', noteRow(77, 'B'));
    await a.insert('tb_books', bookRow(2, md5: 'A'));
    await b.insert('tb_books', bookRow(2, md5: 'B'));
    await converge();
    expect((await a.query('tb_books')).length, 3);
    expect((await b.query('tb_books')).length, 3);
    expect((await a.query('tb_notes')).map((r) => r['book_id']).toSet(), {1});
    expect((await b.query('tb_notes')).map((r) => r['book_id']).toSet(), {77});
    expect((await a.query('tb_notes')).map((r) => r['content']).toSet(),
        {'A', 'B'});
    expect(jsonEncode((await sa.snapshot()).map((r) => r.toMap()).toList()),
        jsonEncode((await sb.snapshot()).map((r) => r.toMap()).toList()));
  });

  test(
      'latest actual position wins even when moving backwards; metadata is independent',
      () async {
    await a.update('tb_books',
        {'last_read_position': 'chapter9', 'reading_percentage': .9},
        where: 'id=1');
    await converge();
    await b.update('tb_books',
        {'last_read_position': 'chapter2', 'reading_percentage': .2},
        where: 'id=77');
    await a.update('tb_books', {'title': 'Changed on desktop'}, where: 'id=1');
    await converge();
    final book = (await a.query('tb_books')).single;
    expect(book['last_read_position'], 'chapter2');
    expect(book['reading_percentage'], .2);
    expect(book['title'], 'Changed on desktop');
  });

  test('editing a note resolves by operation time rather than file timestamp',
      () async {
    await a.insert('tb_notes', noteRow(1, 'shared'));
    await converge();
    await a.update('tb_notes', {'reader_note': 'earlier'});
    await converge();
    await b.update('tb_notes', {'reader_note': 'latest'});
    await converge();
    expect((await a.query('tb_notes')).single['reader_note'], 'latest');
  });

  test('note tombstone survives stale edits and local integer ID reuse',
      () async {
    final id = await a.insert('tb_notes', noteRow(1, 'old'));
    await converge();
    await a.delete('tb_notes', where: 'id=?', whereArgs: [id]);
    await b.update('tb_notes', {'reader_note': 'offline change'});
    await a.insert('tb_notes', {'id': id, ...noteRow(1, 'new')});
    await converge();
    expect((await a.query('tb_notes')).map((r) => r['cfi']), ['new']);
    expect((await b.query('tb_notes')).map((r) => r['cfi']), ['new']);
    await converge();
    expect((await a.query('tb_notes')).length, 1);
  });

  test(
      'book deletion is independent of reading; explicit restore is newer life operation',
      () async {
    await a.update('tb_books', {'is_deleted': 1}, where: 'id=1');
    await b.update('tb_books', {'last_read_position': 'offline'},
        where: 'id=77');
    await converge();
    expect((await b.query('tb_books')).single['is_deleted'], 1);
    await b.update('tb_books', {'is_deleted': 0}, where: 'id=77');
    await converge();
    expect((await a.query('tb_books')).single['is_deleted'], 0);
  });

  test('new reading sessions union once and delete does not resurrect',
      () async {
    await a.insert('tb_reading_time',
        {'book_id': 1, 'date': '2026-09-09', 'reading_time': 30});
    await b.insert('tb_reading_time',
        {'book_id': 77, 'date': '2026-09-09', 'reading_time': 40});
    for (var i = 0; i < 4; i++) {
      await converge();
    }
    expect(
        (await a.rawQuery(
                'SELECT SUM(reading_time) AS total FROM tb_reading_time'))
            .single['total'],
        70);
    final daily = await a.rawQuery(ReadingTimeDao.dailyBookReadingQuery, [1]);
    expect(daily.length, 1);
    expect(daily.single['reading_time'], 70);
    await a.delete('tb_reading_time');
    await converge();
    expect(await b.query('tb_reading_time'), isEmpty);
  });

  test('legacy daily totals take max and future sessions are additive',
      () async {
    final x = await fixture(install: false);
    final y = await fixture(install: false);
    try {
      await x.insert('tb_reading_time',
          {'book_id': 1, 'date': '2026-09-08', 'reading_time': 120});
      await y.insert('tb_reading_time',
          {'book_id': 1, 'date': '2026-09-08', 'reading_time': 150});
      await x.transaction((t) => RowSyncStore.install(t));
      await y.transaction((t) => RowSyncStore.install(t));
      final sx = RowSyncStore(x);
      final sy = RowSyncStore(y);
      await sx.merge(await sy.snapshot());
      await x.insert('tb_reading_time',
          {'book_id': 1, 'date': '2026-09-08', 'reading_time': 20});
      await sy.merge(await sx.snapshot());
      await sx.merge(await sy.snapshot());
      expect(
          (await x.rawQuery(
                  'SELECT SUM(reading_time) AS total FROM tb_reading_time'))
              .single['total'],
          170);
    } finally {
      await x.close();
      await y.close();
    }
  });

  test('tag relations remap IDs while fonts and reading themes stay local',
      () async {
    await a
        .insert('tb_styles', {'font_size': 18, 'font_family': 'Private font'});
    final tag =
        await a.insert('tb_styles', {'font_size': 1, 'font_family': 'History'});
    await a.insert(
        'tb_styles', {'font_size': 2, 'line_height': 1, 'letter_spacing': tag});
    await converge();
    final styles = await b.query('tb_styles');
    expect(styles.length, 2);
    final localTag = styles.singleWhere((r) => r['font_size'] == 1);
    final link = styles.singleWhere((r) => r['font_size'] == 2);
    expect(link['line_height'], 77);
    expect(link['letter_spacing'], localTag['id']);
    expect(jsonEncode((await sa.snapshot()).map((r) => r.toMap()).toList()),
        isNot(contains('Private font')));
  });

  test(
      'invalid reference rolls back all changes and re-enables change tracking',
      () async {
    final remote = await sb.snapshot();
    final bad = RowSyncRecord('note', 'broken', 1234, 'r', false, {
      for (final entry in noteRow(77, 'broken').entries) entry.key: entry.value,
      'book_id': 'missing',
      'chapter': null,
      'color': null,
      'reader_note': null
    });
    await expectLater(sa.merge([...remote, bad]), throwsFormatException);
    expect(await a.query('tb_notes'), isEmpty);
    await a.insert('tb_notes', noteRow(1, 'after rollback'));
    expect((await sa.snapshot()).where((r) => r.kind == 'note').length, 1);
  });

  test(
      'archive round trip excludes local IDs, font styles and app-private tables',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-archive-test-');
    try {
      await a.execute('CREATE TABLE private_preferences (api_key TEXT)');
      await a.insert('private_preferences', {'api_key': 'do-not-export'});
      final file = '${temp.path}/archive.db';
      await RowSyncArchive.write(file, await sa.snapshot());
      final records = await RowSyncArchive.read(file);
      await sb.merge(records);
      final archive = await databaseFactory.openDatabase(file,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      try {
        final tables = await archive
            .rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
        expect(tables.map((r) => r['name']).toSet(),
            {'modu_sync_manifest', syncRecordsTable});
      } finally {
        await archive.close();
      }
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('live WebDAV conditional PUT retries a competing writer and merges both',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-cas-test-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      await a.insert('tb_notes', noteRow(1, 'desktop'));
      final base = '${temp.path}/base.db';
      await RowSyncArchive.write(base, await sb.snapshot());
      var cloud = await File(base).readAsBytes();
      var revision = 1;
      var puts = 0;
      final requests = <String>[];
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        if (request.uri.path.endsWith('/record-log-v1')) {
          await request.drain<void>();
          request.response.statusCode = 404;
        } else if (request.method == 'OPTIONS') {
          await request.drain<void>();
          request.response.statusCode = 200;
        } else if (request.method == 'PROPFIND') {
          await request.drain<void>();
          request.response.statusCode = 207;
          request.response.write(
              '''<d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop>
            <d:resourcetype/><d:getetag>"$revision"</d:getetag><d:getcontentlength>${cloud.length}</d:getcontentlength>
            <d:getlastmodified>Wed, 09 Sep 2026 13:00:00 GMT</d:getlastmodified>
            </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>''');
        } else if (request.method == 'GET') {
          request.response.add(cloud);
        } else if (request.method == 'PUT') {
          final body =
              await request.fold<List<int>>([], (a, b) => a..addAll(b));
          puts++;
          if (puts == 1) {
            await b.insert('tb_notes', noteRow(77, 'phone concurrent'));
            final other = '${temp.path}/other.db';
            await RowSyncArchive.write(other, await sb.snapshot());
            cloud = await File(other).readAsBytes();
            revision++;
          }
          if (request.headers.value('if-match') != '"$revision"') {
            request.response.statusCode = 412;
          } else {
            cloud = Uint8List.fromList(body);
            revision++;
            request.response.statusCode = 204;
          }
        } else {
          request.response.statusCode = 405;
        }
        await request.response.close();
      });
      final client = VerifiedWebdavClient(
          url: 'http://127.0.0.1:${server.port}/library',
          username: 'test',
          password: 'test');
      await RowSyncEngine(store: sa, client: client, cache: temp).synchronize();
      expect(puts, 2);
      expect(requests.any((r) => r.startsWith('DELETE')), isFalse);
      expect(
          requests.every((r) =>
              r.endsWith('/library/modu/database8.db') ||
              r.endsWith('/record-log-v1')),
          isTrue);
      await File('${temp.path}/published.db').writeAsBytes(cloud);
      await sb.merge(await RowSyncArchive.read('${temp.path}/published.db'));
      expect((await b.query('tb_notes')).map((r) => r['content']).toSet(),
          {'desktop', 'phone concurrent'});
    } finally {
      await server.close(force: true);
      await temp.delete(recursive: true);
    }
  });

  test(
      'all app sync entry points use row merge, not database replacement or orphan deletion',
      () {
    final source = File('lib/providers/sync.dart').readAsStringSync();
    expect(source, contains('RowSyncEngine('));
    expect(source, isNot(contains('safeDownloadDatabase(')));
    expect(source, isNot(contains('determineSyncDirection(')));
    expect(
        source, isNot(contains('await client.remove(SyncPaths.data(file))')));
    expect(
        source,
        contains(RegExp(
            r'if \(_syncRunning\) \{\s*if \(!automatic\) _pendingManualDirection = direction;\s*return;')));
  });

  test(
      'legacy archive migration preserves both sides and leaves database7 untouched',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-migrate-test-');
    try {
      final old = await fixture(install: false, path: '${temp.path}/legacy.db');
      await old.insert('tb_notes', noteRow(1, 'old cloud note'));
      await old.close();
      await a.insert('tb_notes', noteRow(1, 'new local note'));
      final client = MemorySyncClient();
      final original = await File('${temp.path}/legacy.db').readAsBytes();
      client.files['modu/database7.db'] = original;
      expect(
          await RowSyncEngine(store: sa, client: client, cache: temp)
              .synchronize(),
          RowSyncOutcome.published);
      expect(client.files['modu/database7.db'], original);
      expect(client.files.containsKey('modu/database8.db'), isTrue);
      expect((await a.query('tb_notes')).map((r) => r['content']).toSet(),
          {'old cloud note', 'new local note'});
      final writes = client.writes;
      expect(
          await RowSyncEngine(store: sa, client: client, cache: temp)
              .synchronize(),
          RowSyncOutcome.unchanged);
      expect(client.writes, writes);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  for (final missingAttempts in [1, 10]) {
    test('missing validator retries safely ($missingAttempts failures)',
        () async {
      final temp =
          await Directory.systemTemp.createTemp('modu-validator-test-');
      try {
        final client = MissingValidatorClient(missingAttempts);
        final cloudPath = '${temp.path}/cloud.db';
        await RowSyncArchive.write(cloudPath, await sb.snapshot());
        client.files[RowSyncEngine.remotePath] =
            await File(cloudPath).readAsBytes();
        await a.insert('tb_notes', noteRow(1, 'local note'));
        // A second device publishes while the validator is missing. Retrying
        // must download that new snapshot, not just fetch its new ETag.
        client.onMissing = () async {
          if (client.attempts != 1) return;
          await b.insert('tb_notes', noteRow(77, 'concurrent cloud note'));
          final concurrentPath = '${temp.path}/concurrent.db';
          await RowSyncArchive.write(concurrentPath, await sb.snapshot());
          client.files[RowSyncEngine.remotePath] =
              await File(concurrentPath).readAsBytes();
          client.revisions[RowSyncEngine.remotePath] = 2;
        };
        final run = RowSyncEngine(
                store: sa,
                client: client,
                cache: temp,
                validatorRetryDelay: Duration.zero)
            .synchronize();
        if (missingAttempts == 1) {
          expect(await run, RowSyncOutcome.published);
          expect(client.attempts, 2);
          expect(client.writes, 1);
          await File(cloudPath)
              .writeAsBytes(client.files[RowSyncEngine.remotePath]!);
          final records = await RowSyncArchive.read(cloudPath);
          expect(records.where((r) => r.kind == 'note').length, 2);
        } else {
          expect(await run, RowSyncOutcome.published);
          expect(client.attempts, 3);
          expect(client.writes, 0);
          expect(client.files.keys.any((p) => p.contains('/record-log-v1/')),
              isTrue);
        }
        expect((await a.query('tb_notes')).map((r) => r['content']).toSet(),
            {'local note', 'concurrent cloud note'});
      } finally {
        await temp.delete(recursive: true);
      }
    });
  }

  test('fresh empty device downloads records without overwriting cloud',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-empty-test-');
    final empty = await fixture(install: false);
    try {
      await empty.delete('tb_books');
      await empty.transaction((t) => RowSyncStore.install(t));
      final store = RowSyncStore(empty);
      final client = MemorySyncClient();
      await RowSyncEngine(store: store, client: client, cache: temp)
          .synchronize();
      expect(client.writes, 0);
      await a.insert('tb_notes', noteRow(1, 'cloud note'));
      await RowSyncArchive.write('${temp.path}/cloud.db', await sa.snapshot());
      client.files['modu/database8.db'] =
          await File('${temp.path}/cloud.db').readAsBytes();
      await RowSyncEngine(store: store, client: client, cache: temp)
          .synchronize();
      expect((await empty.query('tb_books')).length, 1);
      expect((await empty.query('tb_notes')).single['content'], 'cloud note');
      expect(client.writes, 0);
    } finally {
      await empty.close();
      await temp.delete(recursive: true);
    }
  });

  test('changes made while uploading are retained and included in another pass',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-live-edit-test-');
    try {
      final client = MemorySyncClient();
      client.beforeWrite = (attempt) async {
        if (attempt == 1)
          await a.insert('tb_notes', noteRow(1, 'during transfer'));
      };
      await RowSyncEngine(store: sa, client: client, cache: temp).synchronize();
      expect(client.writes, 2);
      await File('${temp.path}/published.db')
          .writeAsBytes(client.files['modu/database8.db']!);
      final records = await RowSyncArchive.read('${temp.path}/published.db');
      expect(records.where((r) => r.kind == 'note').single.data['content'],
          'during transfer');
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
      'continuous conflicts stop after three attempts without overwriting cloud',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-conflict-test-');
    try {
      final client = MemorySyncClient();
      await RowSyncArchive.write('${temp.path}/cloud.db', await sb.snapshot());
      final original = await File('${temp.path}/cloud.db').readAsBytes();
      client.files['modu/database8.db'] = original;
      await a.insert('tb_notes', noteRow(1, 'unsent'));
      client.beforeWrite = (_) async {
        client.revisions['modu/database8.db'] =
            (client.revisions['modu/database8.db'] ?? 1) + 1;
      };
      await expectLater(
          RowSyncEngine(store: sa, client: client, cache: temp).synchronize(),
          throwsStateError);
      expect(client.writes, 3);
      expect(client.files['modu/database8.db'], original);
      expect((await a.query('tb_notes')).single['content'], 'unsent');
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('corrupt cloud and failed assets cannot publish or remove local data',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-failure-test-');
    try {
      final client = MemorySyncClient();
      client.files['modu/database8.db'] = utf8.encode('not a database');
      await expectLater(
          RowSyncEngine(store: sa, client: client, cache: temp).synchronize(),
          throwsA(anything));
      expect(client.writes, 0);
      expect((await a.query('tb_books')).length, 1);
      await expectLater(
          RowSyncEngine(
              store: sa,
              client: client,
              cache: temp,
              beforePublish: () async =>
                  throw StateError('asset upload failed')).synchronize(),
          throwsStateError);
      expect(client.writes, 0);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test(
      'deleted tag absorbs an offline new link without blocking synchronization',
      () async {
    final id =
        await a.insert('tb_styles', {'font_size': 1, 'font_family': 'Tag'});
    await converge();
    final bid = (await b.query('tb_styles')).single['id'];
    await a.delete('tb_styles', where: 'id=?', whereArgs: [id]);
    await b.insert('tb_styles',
        {'font_size': 2, 'line_height': 77, 'letter_spacing': bid});
    await converge();
    expect(await b.query('tb_styles'), isEmpty);
    await converge();
    expect(await a.query('tb_styles'), isEmpty);
  });

  test('hard-deleted group retains a tombstone and referenced books', () async {
    await a.insert('tb_groups',
        {'id': 5, 'name': 'Group', 'parent_id': 0, 'is_deleted': 0});
    await a.update('tb_books', {'group_id': 5});
    await converge();
    await a.delete('tb_groups', where: 'id=5');
    await converge();
    expect((await b.query('tb_books')).length, 1);
    final groupId = (await b.query('tb_books')).single['group_id'];
    expect(
        (await b.query('tb_groups', where: 'id=?', whereArgs: [groupId]))
            .single['is_deleted'],
        1);
  });
}
