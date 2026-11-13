import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:modu_reader/models/narration_position.dart';
import 'package:modu_reader/models/reading_position_snapshot.dart';
import 'package:modu_reader/service/book_player/reader_progress_session.dart';
import 'package:modu_reader/service/sync/row_sync_engine.dart';
import 'package:modu_reader/service/sync/row_sync_record.dart';
import 'package:modu_reader/service/sync/row_sync_store.dart';
import 'row_sync_test.dart' show fixture, bookRow, MemorySyncClient;
import 'suspended_reader_sync_diagnostic_test.dart' show IsolatedBookDao;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  const first = 'epubcfi(/6/2!/4/2, /1:0,/1:10)';
  const second = 'epubcfi(/6/4!/4/2,/1:0,/1:12)';

  test(
      'resume targets saved speech, while stopped or absent speech uses the page',
      () {
    for (final state in ['playing', 'paused', 'stopped']) {
      final snapshot = ReadingPositionSnapshot(first, .4, 'revision',
          narration: NarrationPosition(second, state));
      expect(snapshot.resumePosition, state == 'stopped' ? first : second);
      expect(snapshot.position, first);
      expect(snapshot.narration!.state, state);
    }
    expect(const ReadingPositionSnapshot(first, .4, 'revision').resumePosition,
        first);
  });

  test('exit checkpoint drains page 8 then saves the visible page 10',
      () async {
    final db = await fixture();
    addTearDown(db.close);
    final dao = IsolatedBookDao(db);
    final session = ReaderProgressSession(dao, 1);
    await session.refresh();
    final writing =
        session.record('chapter-2-page-8', .28, generation: session.generation);
    final checkpoint = session.checkpointPage(
        'chapter-2-page-10-first-line', .30,
        generation: session.generation);
    await Future.wait([writing, checkpoint]);
    await session.flush();
    final saved = await dao.readReadingPosition(1);
    expect(saved.position, 'chapter-2-page-10-first-line');
    expect(saved.narration, isNull);
    expect(saved.percentage, .30);
    await session.checkpointPage(saved.position, saved.percentage,
        generation: session.generation);
    expect((await dao.readReadingPosition(1)).revision, saved.revision);
  });

  test(
      'exit checkpoint preserves speech and cannot overwrite newer remote progress',
      () async {
    final db = await fixture();
    addTearDown(db.close);
    final dao = IsolatedBookDao(db);
    final session = ReaderProgressSession(dao, 1);
    await session.refresh();
    for (final state in ['playing', 'paused']) {
      await session.record(first, .4,
          generation: session.generation,
          narration: NarrationPosition(first, state));
      await session.checkpointPage(second, .8, generation: session.generation);
      expect((await dao.readReadingPosition(1)).position, first);
    }
    await session.recordNarration(const NarrationPosition(first, 'stopped'),
        generation: session.generation);
    await dao.updateReadingPosition(1, second, .8);
    await session.checkpointPage('old-screen', .1,
        generation: session.generation);
    expect((await dao.readReadingPosition(1)).position, second);
  });

  for (final conflict in [false, true]) {
    test(
        'sync replaces the retained speech cursor without publishing stale data, conflict=$conflict',
        () async {
      final db = await fixture();
      addTearDown(db.close);
      final dao = IsolatedBookDao(db);
      final session = ReaderProgressSession(dao, 1);
      await session.refresh();
      await session.record(first, .4,
          generation: session.generation,
          narration: const NarrationPosition(first, 'playing'));
      await dao.updateReadingPosition(1, second, .8,
          narration: const NarrationPosition(second, 'paused'));
      final remote = await dao.readReadingPosition(1);
      if (conflict) {
        expect(
            await session.recordNarration(
                const NarrationPosition(first, 'paused'),
                generation: session.generation),
            false);
      }
      final live = await session.refresh();
      expect(live.position, second);
      expect(live.percentage, .8);
      expect(live.narration?.cfi, second);
      expect(live.narration?.state, 'paused');
      expect(live.revision, remote.revision);
      await session.flush();
      final unchanged = await dao.readReadingPosition(1);
      expect(unchanged.position, second);
      expect(unchanged.revision, remote.revision);
      // Pausing the restored cursor must not reintroduce the old location.
      expect(
          await session.recordNarration(
              const NarrationPosition(second, 'paused'),
              generation: session.generation),
          true);
      final saved = await dao.readReadingPosition(1);
      expect(saved.position, second);
      expect(saved.percentage, .8);
      expect(saved.narration?.cfi, second);
      expect(saved.narration?.state, 'paused');
    });
  }

  test('refresh accepts the merged cursor and never revives a deleted book',
      () async {
    final db = await fixture();
    addTearDown(db.close);
    final dao = IsolatedBookDao(db),
        session = ReaderProgressSession(IsolatedBookDao(db), 1);
    await session.refresh();
    await session.record(first, .4,
        generation: session.generation,
        narration: const NarrationPosition(first, 'playing'));
    await dao.updateReadingPosition(1, second, .8,
        narration: const NarrationPosition(second, 'paused'));
    final refresh = session.refresh();
    expect((await refresh).position, second);
    // A newly opened/idle reader still imports the remote cursor normally.
    expect((await session.refresh()).position, second);
    await db.update('tb_books', {'is_deleted': 1},
        where: 'id=?', whereArgs: [1]);
    expect((await session.refresh()).deleted, true);
    expect(
        await session.record(first, .4, generation: session.generation), false);
  });

  test(
      'optional speech envelope validates without changing legacy position payload',
      () {
    const r = RowSyncRecord('position', 'md5:book', 20, 'rev', false,
        {'last_read_position': first, 'reading_percentage': .4},
        narration: NarrationPosition(first, 'playing'));
    RowSyncStore.validate(r);
    final roundTrip = RowSyncRecord.fromMap(r.toMap());
    expect(roundTrip.narration?.cfi, first);
    expect(roundTrip.narration?.canResume, true);
    final legacy = RowSyncRecord.fromMap({...r.toMap()}..remove('narration'));
    expect(legacy.data, r.data);
    RowSyncStore.validate(legacy);
    for (final records in [
      [r, legacy],
      [legacy, r]
    ]) {
      expect(mergeSyncRecords([records[0]], [records[1]]).single.narration?.cfi,
          first);
    }
    final newerLegacy =
        RowSyncRecord(legacy.kind, legacy.id, 21, 'newer', false, legacy.data);
    expect(mergeSyncRecords([r], [newerLegacy]).single.narration, isNull);
    for (final invalid in [
      '',
      '{}',
      '{"cfi":"x","state":"playing"}',
      '{"cfi":"epubcfi(x)","state":"unknown"}'
    ]) {
      expect(() => NarrationPosition.decode(invalid), throwsFormatException);
    }
  });

  test('pause queued behind a speech cursor cannot roll reading progress back',
      () async {
    final db = await fixture();
    addTearDown(db.close);
    final session = ReaderProgressSession(IsolatedBookDao(db), 1);
    await session.refresh();
    final moving = session.record(second, .8,
        generation: session.generation,
        narration: const NarrationPosition(second, 'playing'));
    final pausing = session.recordNarration(
        const NarrationPosition(second, 'paused'),
        generation: session.generation);
    expect(await moving, true);
    expect(await pausing, true);
    final latest = await session.refresh();
    expect(latest.position, second);
    expect(latest.percentage, .8);
    expect(latest.narration?.state, 'paused');
    final revision = latest.revision;
    await session.recordNarration(const NarrationPosition(second, 'paused'),
        generation: session.generation);
    expect((await session.refresh()).revision, revision);
  });

  for (final etag in [true, false]) {
    test('speech cursor/state sync across book IDs, etag=$etag', () async {
      final a = await fixture();
      final b = await fixture(bookId: 91);
      final dir = await Directory.systemTemp.createTemp('modu-narration-test-');
      addTearDown(() async {
        await a.close();
        await b.close();
        await dir.delete(recursive: true);
      });
      await a.insert('tb_books', bookRow(2, md5: 'another-book'));
      final client = MemorySyncClient()..atomic = etag;
      final syncA = RowSyncEngine(
          store: RowSyncStore(a),
          client: client,
          cache: await Directory('${dir.path}/a').create());
      final syncB = RowSyncEngine(
          store: RowSyncStore(b),
          client: client,
          cache: await Directory('${dir.path}/b').create());
      final session = ReaderProgressSession(IsolatedBookDao(a), 1);
      final openReceiver = ReaderProgressSession(IsolatedBookDao(b), 91);
      await openReceiver.refresh();
      final oldReceiverGeneration = openReceiver.generation;
      await session.refresh();
      await session.record(first, .4,
          generation: session.generation,
          narration: const NarrationPosition(first, 'playing'));
      await syncA.synchronize();
      await syncB.synchronize();
      final receiver = IsolatedBookDao(b);
      // The receiver remains open while its device sleeps. On wake, sync
      // finishes before refreshing its retained reader session.
      final restored = await openReceiver.refresh();
      expect(restored.position, first);
      expect(restored.narration?.cfi, first);
      expect(
          await openReceiver.record('stale-screen', .1,
              generation: oldReceiverGeneration),
          false);
      expect(restored.narration?.state, 'playing');
      expect(restored.narration?.canResume, true);
      expect(
          (await IsolatedBookDao(a).readReadingPosition(2)).narration, isNull);
      // Page and paused narration can legitimately be in different passages.
      await receiver.updateReadingPosition(91, second, .8,
          expectedRevision: restored.revision,
          narration: const NarrationPosition(first, 'paused'));
      await syncB.synchronize();
      await syncA.synchronize();
      // Stale open reader cannot overwrite the newly received speech cursor.
      expect(
          await session.recordNarration(
              const NarrationPosition(first, 'paused'),
              generation: session.generation),
          false);
      final back = await session.refresh();
      expect(back.position, second);
      expect(back.percentage, .8);
      expect(back.narration?.cfi, first);
      expect(back.narration?.state, 'paused');
    });
  }

  test('v8 narration migration preserves metadata and is idempotent', () async {
    final db = await fixture();
    addTearDown(db.close);
    final before = await RowSyncStore(db).snapshot();
    await db.execute('ALTER TABLE $syncRecordsTable DROP COLUMN narration');
    await RowSyncStore.installNarration(db);
    await RowSyncStore.installNarration(db);
    expect(sameSyncRecords(before, await RowSyncStore(db).snapshot()), true);
  });
}
