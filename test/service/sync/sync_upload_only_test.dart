import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'package:modu_reader/service/sync/sync_preview.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show MemorySyncClient, bookRow, fixture, noteRow;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database a;
  late Database b;
  late Directory temp;

  setUp(() async {
    a = await fixture();
    b = await fixture(bookId: 77);
    temp = await Directory.systemTemp.createTemp('modu-upload-only-');
  });

  tearDown(() async {
    await a.close();
    await b.close();
    await temp.delete(recursive: true);
  });

  Future<List<RowSyncRecord>> cloud(MemorySyncClient client) async {
    final file = '${temp.path}/cloud.db';
    await File(file).writeAsBytes(client.files[RowSyncEngine.remotePath]!);
    return RowSyncArchive.read(file);
  }

  test('upload-only never imports the cloud and keeps cloud-only records',
      () async {
    final client = MemorySyncClient();
    await b.insert('tb_notes', noteRow(77, 'cloud-note'));
    final bCache = await Directory('${temp.path}/b').create();
    await RowSyncEngine(store: RowSyncStore(b), client: client, cache: bCache)
        .synchronize();

    await a.insert('tb_notes', noteRow(1, 'local-note'));
    await a.insert('tb_books', bookRow(3, md5: 'local-only'));
    final before = await RowSyncStore(a).snapshot();
    final aCache = await Directory('${temp.path}/a').create();

    final outcome = await RowSyncEngine(
      store: RowSyncStore(a),
      client: client,
      cache: aCache,
      onPreview: (_) async =>
          const SyncPreviewDecision(SyncConflictResolution.uploadOnly),
    ).synchronize();

    expect(outcome, RowSyncOutcome.published);
    // The local library is untouched: the cloud note and cloud book never
    // arrive, while the local note and book stay exactly as they were.
    expect(sameSyncRecords(await RowSyncStore(a).snapshot(), before), isTrue);
    expect((await a.query('tb_notes')).map((row) => row['content']),
        ['local-note']);
    expect((await a.query('tb_books')).map((row) => row['file_md5']).toSet(),
        {'same-content', 'local-only'});

    // The cloud keeps what only it knows and gains this device's records.
    final published = await cloud(client);
    expect(
        published
            .where((r) => r.kind == 'note' && !r.deleted)
            .map((r) => r.data['content'])
            .toSet(),
        {'cloud-note', 'local-note'});
    expect(
        published
            .where((r) => r.kind == 'book' && !r.deleted)
            .map((r) => r.data['file_md5'])
            .toSet(),
        contains('local-only'));

    // A second upload-only pass is a no-op for both sides.
    final writes = client.writes;
    await RowSyncEngine(
      store: RowSyncStore(a),
      client: client,
      cache: aCache,
      onPreview: (_) async =>
          const SyncPreviewDecision(SyncConflictResolution.uploadOnly),
    ).synchronize();
    expect(client.writes, writes);
    expect((await a.query('tb_notes')).map((row) => row['content']),
        ['local-note']);
  });

  test('upload-only still publishes a local deletion', () async {
    final client = MemorySyncClient();
    final bCache = await Directory('${temp.path}/b').create();
    await RowSyncEngine(store: RowSyncStore(b), client: client, cache: bCache)
        .synchronize();
    final aCache = await Directory('${temp.path}/a').create();
    await RowSyncEngine(store: RowSyncStore(a), client: client, cache: aCache)
        .synchronize();

    await a.delete('tb_books');
    await RowSyncEngine(
      store: RowSyncStore(a),
      client: client,
      cache: aCache,
      onPreview: (_) async =>
          const SyncPreviewDecision(SyncConflictResolution.uploadOnly),
    ).synchronize();

    final published = await cloud(client);
    expect(published.where((r) => r.kind == 'book' && !r.deleted), isEmpty);
  });

  test('upload-only preview reports no incoming changes', () async {
    final client = MemorySyncClient();
    await b.insert('tb_notes', noteRow(77, 'cloud-note'));
    await b.insert('tb_books', bookRow(4, md5: 'cloud-only'));
    final bCache = await Directory('${temp.path}/b').create();
    await RowSyncEngine(store: RowSyncStore(b), client: client, cache: bCache)
        .synchronize();
    final published = await cloud(client);

    await a.insert('tb_notes', noteRow(1, 'local-note'));
    await a.insert('tb_notes', noteRow(1, 'local-note-2'));
    final local = await RowSyncStore(a).snapshot();
    final preview = buildSyncPreview(
      context: SyncPreviewContext(local: local, remote: published),
      resolution: SyncConflictResolution.uploadOnly,
    );

    expect(preview.uploadOnly, isTrue);
    expect(preview.hasDownloadChanges, isFalse);
    expect(preview.noteDelta, 0);
    expect(preview.readingTimeDelta, 0);
    expect(preview.addedBooks, isEmpty);
    expect(preview.removedBooks, isEmpty);
    expect(preview.cloudRemovedBooks, isEmpty,
        reason: 'Cloud-only books are preserved, not removed');
    // Upload deltas come from the local view, not from an imported merge.
    expect(preview.localNoteCount, 2);
    expect(preview.mergedNoteCount, preview.localNoteCount);
    // The cloud keeps its own note and gains both local ones.
    expect(preview.uploadNoteAfter, 3);
    expect(preview.uploadNoteDelta, 2, reason: '2 local notes vs 1 cloud note');
  });

  test('legacy copies sharing a baseline take max on repeated merges',
      () async {
    final x = await fixture(install: false);
    final y = await fixture(install: false);
    try {
      await x.insert('tb_reading_time',
          {'book_id': 1, 'date': '2026-09-08', 'reading_time': 60});
      await y.insert('tb_reading_time',
          {'book_id': 1, 'date': '2026-09-08', 'reading_time': 60});
      // A copied old library already includes these 60 seconds. Reading on the
      // copy before upgrading extends that total, not a second independent row.
      await y.update('tb_reading_time', {'reading_time': 120});
      await x.transaction((txn) => RowSyncStore.install(txn));
      await y.transaction((txn) => RowSyncStore.install(txn));
      final sx = RowSyncStore(x);
      final sy = RowSyncStore(y);

      Future<int> total(Database db) async => (await db.rawQuery(
              'SELECT SUM(reading_time) AS total FROM tb_reading_time'))
          .single['total'] as int;

      await sx.merge(await sy.snapshot());
      expect(await total(x), 120,
          reason: 'The shared baseline is counted once');
      await sx.merge(await sy.snapshot());
      expect(await total(x), 120);
      await sy.merge(await sx.snapshot());
      expect(await total(y), 120);
      await sx.merge(await sy.snapshot());
      expect(await total(x), 120);
    } finally {
      await x.close();
      await y.close();
    }
  });
}
