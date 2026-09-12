import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'row_sync_test.dart' show fixture, noteRow, MemorySyncClient;

class ConcurrentLogClient extends MemorySyncClient {
  final ready = Completer<void>();
  int uploads = 0;
  bool concurrent = true;
  bool corrupt = false;
  @override
  Future<void> uploadFile(String localPath, String remotePath,
      {bool replace = true,
      void Function(int, int)? onProgress,
      CancelToken? cancelToken}) async {
    if (concurrent) {
      if (++uploads == 2) ready.complete();
      await ready.future;
    }
    await super.uploadFile(localPath, remotePath);
    if (corrupt) files[remotePath] = [1, 2, 3];
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late Database a, b;
  late RowSyncStore sa, sb;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('modu-log-test-');
    a = await fixture();
    b = await fixture(bookId: 77);
    sa = RowSyncStore(a);
    sb = RowSyncStore(b);
  });
  tearDown(() async {
    await a.close();
    await b.close();
    await temp.delete(recursive: true);
  });
  Future<RowSyncOutcome> sync(RowSyncStore store, MemorySyncClient client) =>
      RowSyncEngine(store: store, client: client, cache: temp).synchronize();

  test('simultaneous no-ETag publishers converge without overwriting shared DB',
      () async {
    final client = ConcurrentLogClient()..atomic = false;
    await a.insert('tb_notes', noteRow(1, 'desktop'));
    await b.insert('tb_notes', noteRow(77, 'phone'));
    await Future.wait([sync(sa, client), sync(sb, client)]);
    client.concurrent = false;
    expect(client.files.length, 2);
    final original = {
      for (final e in client.files.entries) e.key: List<int>.of(e.value)
    };
    await sync(sa, client);
    await sync(sb, client);
    expect((await a.query('tb_notes')).map((r) => r['content']).toSet(),
        {'desktop', 'phone'});
    expect(sameSyncRecords(await sa.snapshot(), await sb.snapshot()), isTrue);
    expect(client.files, original);
    expect(client.writes, 0);
    expect(client.files.containsKey(RowSyncEngine.remotePath), isFalse);
  });

  test('deletions and reading sessions survive replay; backward position wins',
      () async {
    final client = MemorySyncClient()..atomic = false;
    await a.insert('tb_notes', noteRow(1, 'delete-me'));
    await a.insert('tb_reading_time',
        {'book_id': 1, 'date': '2026-09-12', 'reading_time': 20});
    await sync(sa, client);
    await sync(sb, client);
    await b.delete('tb_notes');
    await b.update('tb_books',
        {'last_read_position': 'chapter2', 'reading_percentage': .2});
    await b.insert('tb_reading_time',
        {'book_id': 77, 'date': '2026-09-12', 'reading_time': 30});
    await sync(sb, client);
    for (var i = 0; i < 3; i++) {
      await sync(sa, client);
      await sync(sb, client);
    }
    expect(await a.query('tb_notes'), isEmpty);
    expect(
        (await a.query('tb_books')).single['last_read_position'], 'chapter2');
    expect(
        (await a.rawQuery('SELECT SUM(reading_time) AS n FROM tb_reading_time'))
            .single['n'],
        50);
  });

  test('transport capability changes never split the library', () async {
    final client = MemorySyncClient();
    await sync(sa, client);
    final oldDatabase = List<int>.of(client.files[RowSyncEngine.remotePath]!);
    client.atomic = false;
    await b.insert('tb_notes', noteRow(77, 'no-etag'));
    await sync(sb, client);
    expect(client.files[RowSyncEngine.remotePath], oldDatabase);
    client.atomic = true;
    await a.insert('tb_notes', noteRow(1, 'etag-recovered'));
    await sync(sa, client);
    expect(client.writes, 2);
    client.atomic = false;
    await sync(sb, client);
    expect(sameSyncRecords(await sa.snapshot(), await sb.snapshot()), isTrue);
    expect((await b.query('tb_notes')).map((r) => r['content']).toSet(),
        {'no-etag', 'etag-recovered'});
  });

  test('legacy migration seeds the log once and preserves database7', () async {
    final client = MemorySyncClient()..atomic = false;
    final legacyPath = '${temp.path}/legacy.db';
    final legacy = await fixture(install: false, path: legacyPath);
    await legacy.insert('tb_notes', noteRow(1, 'legacy-note'));
    await legacy.close();
    final original = await File(legacyPath).readAsBytes();
    client.files['modu/database7.db'] = original;
    await sync(sa, client);
    await sync(sb, client);
    await b.delete('tb_notes');
    await sync(sb, client);
    await sync(sa, client);
    expect(await a.query('tb_notes'), isEmpty);
    expect(client.files['modu/database7.db'], original);
    expect(client.files.containsKey(RowSyncEngine.remotePath), isFalse);
  });

  test('corrupt/partial published batch is not acknowledged or merged',
      () async {
    final client = ConcurrentLogClient()
      ..atomic = false
      ..concurrent = false
      ..corrupt = true;
    await a.insert('tb_notes', noteRow(1, 'keep-local'));
    await expectLater(sync(sa, client), throwsFormatException);
    final before = await sb.snapshot();
    await expectLater(sync(sb, client), throwsFormatException);
    expect(sameSyncRecords(before, await sb.snapshot()), isTrue);
    expect((await a.query('tb_notes')).single['content'], 'keep-local');
    expect(client.files.length, 1);
    client.corrupt = false;
    await sync(sa, client);
    await sync(sb, client);
    expect((await b.query('tb_notes')).single['content'], 'keep-local');
    expect(client.files.length, 1);
  });

  test('unknown future log entries fail closed, not an empty remote', () async {
    final client = MemorySyncClient()..atomic = false;
    client.files['modu/record-log-v1/unknown/file.db'] = [1];
    await expectLater(sync(sa, client), throwsFormatException);
    expect(client.writes, 0);
  });

  test('pending publication survives disposable cache removal', () async {
    final client = ConcurrentLogClient()
      ..atomic = false
      ..concurrent = false
      ..corrupt = true;
    final cache = await Directory('${temp.path}/cache').create();
    final durable = await Directory('${temp.path}/database').create();
    Future<RowSyncOutcome> run() => RowSyncEngine(
            store: sa, client: client, cache: cache, durableDirectory: durable)
        .synchronize();
    await a.insert('tb_notes', noteRow(1, 'survive-cache-cleanup'));
    await expectLater(run(), throwsFormatException);
    await cache.delete(recursive: true);
    await cache.create();
    client.corrupt = false;
    expect(await run(), RowSyncOutcome.published);
    await sync(sb, client);
    expect(
        (await b.query('tb_notes')).single['content'], 'survive-cache-cleanup');
    expect(
        await durable
            .list(recursive: true)
            .where((e) => e is File && e.path.endsWith('.db'))
            .toList(),
        isEmpty);
  });
}
