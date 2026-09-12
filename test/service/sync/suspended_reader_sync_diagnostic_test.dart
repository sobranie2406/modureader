// Regressions for the long-lived reader: stale snapshots must never become new
// edits. Both reliable ETag and immutable-log transports exercise real DAOs.
import 'dart:io';

import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/models/reading_position_snapshot.dart';
import 'package:anx_reader/service/book_player/reader_progress_session.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_record.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'row_sync_test.dart' show fixture, noteRow, MemorySyncClient;

// Exercise production DAO methods, replacing only the connection plumbing.
// No DBHelper, preferences, real WebDAV account or user book is accessed.
class IsolatedBookDao extends BookDao {
  IsolatedBookDao(this.db);
  final Database db;
  @override
  Future<R> transaction<R>(Future<R> Function(Transaction) action) =>
      db.transaction(action);
  // Tests without a supplied baseline model deliberate actions on fresh data.
  @override
  Future<ReadingPositionSnapshot?> updateReadingPosition(
          int bookId, String position, double percentage,
          {String? expectedRevision}) async =>
      super.updateReadingPosition(bookId, position, percentage,
          expectedRevision:
              expectedRevision ?? (await readReadingPosition(bookId)).revision);
}

class IsolatedNoteDao extends BookNoteDao {
  IsolatedNoteDao(this.db);
  final Database db;
  @override
  Future<R> transaction<R>(Future<R> Function(Transaction) action) =>
      db.transaction(action);
  @override
  Future<int> update(String table, Map<String, Object?> values,
          {String? where,
          List<Object?>? whereArgs,
          ConflictAlgorithm? conflictAlgorithm}) =>
      db.update(table, values,
          where: where,
          whereArgs: whereArgs,
          conflictAlgorithm: conflictAlgorithm);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  for (final reliableETag in [true, false]) {
    group(reliableETag ? 'reliable ETag' : 'no reliable ETag', () {
      late Database eink, desktop;
      late Directory sandbox;
      late RowSyncEngine einkSync, desktopSync;
      late IsolatedBookDao einkBooks, desktopBooks;

      setUp(() async {
        sandbox =
            await Directory.systemTemp.createTemp('modu-resume-diagnostic-');
        eink = await fixture();
        desktop = await fixture(bookId: 77);
        final cloud = MemorySyncClient()..atomic = reliableETag;
        einkSync = RowSyncEngine(
            store: RowSyncStore(eink),
            client: cloud,
            cache: await Directory('${sandbox.path}/eink').create());
        desktopSync = RowSyncEngine(
            store: RowSyncStore(desktop),
            client: cloud,
            cache: await Directory('${sandbox.path}/desktop').create());
        einkBooks = IsolatedBookDao(eink);
        desktopBooks = IsolatedBookDao(desktop);
        await einkBooks.updateReadingPosition(1, 'chapter-2', .2);
        await eink.insert('tb_notes', {
          ...noteRow(1, 'shared-annotation'),
          'reader_note': 'Original comment',
          'color': 'FFFF00',
        });
        await einkSync.synchronize();
        await desktopSync.synchronize();
      });

      tearDown(() async {
        await eink.close();
        await desktop.close();
        await sandbox.delete(recursive: true);
      });

      Future<void> desktopReadsAndWrites() async {
        await desktopBooks.updateReadingPosition(77, 'chapter-8', .8);
        await desktop.insert('tb_notes', {
          ...noteRow(77, 'new-desktop-annotation'),
          'reader_note': 'New desktop note',
        });
        await desktopSync.synchronize();
      }

      Future<RowSyncRecord> position(Database db) async =>
          (await RowSyncStore(db).snapshot())
              .singleWhere((r) => r.kind == 'position');

      test('control: repeated sync alone preserves remote notes and position',
          () async {
        await desktopReadsAndWrites();
        for (var round = 0; round < 4; round++) {
          await einkSync.synchronize();
          await desktopSync.synchronize();
        }
        for (final db in [eink, desktop]) {
          expect((await db.query('tb_books')).single['last_read_position'],
              'chapter-8');
          expect(await db.query('tb_notes'), hasLength(2));
        }
      });

      test(
          'stale reader save after pull is rejected, preserving position and new notes',
          () async {
        // These fields represent the still-open reader's state before locking.
        final sleepingPage = (await eink.query('tb_books')).single;
        final sleepingVersion = await einkBooks.readReadingPosition(1);
        await desktopReadsAndWrites();
        await einkSync.synchronize();
        final downloaded = await position(eink);
        expect(downloaded.data['last_read_position'], 'chapter-8');

        // Same production DAO call used by saveReadingProgress on pause/dispose.
        // No page turn or deliberate backward reading has taken place.
        final saved = await einkBooks.updateReadingPosition(
            1,
            sleepingPage['last_read_position'] as String,
            (sleepingPage['reading_percentage'] as num).toDouble(),
            expectedRevision: sleepingVersion.revision);
        expect(saved, isNull);
        final staleSave = await position(eink);
        expect(staleSave.clock, downloaded.clock);
        await einkSync.synchronize();
        await desktopSync.synchronize();
        for (final db in [eink, desktop]) {
          expect((await db.query('tb_books')).single['last_read_position'],
              'chapter-8');
          expect(await db.query('tb_notes'), hasLength(2));
        }
      });

      test('saving unchanged page preserves its operation clock and revision',
          () async {
        final before = await position(eink);
        await einkBooks.updateReadingPosition(1, 'chapter-2', .2);
        final after = await position(eink);
        expect(after.data, before.data);
        expect(after.clock, before.clock);
        expect(after.revision, before.revision);
      });

      test(
          'stale note editor is rejected without overwriting remote comment or draft',
          () async {
        // Simulates an editor left open while the device sleeps.
        final openEditor =
            BookNote.fromDb((await eink.query('tb_notes')).single);
        final edited = BookNote.fromDb((await desktop.query('tb_notes')).single)
          ..readerNote = 'Updated on desktop';
        await IsolatedNoteDao(desktop).updateBookNoteById(edited);
        await desktopSync.synchronize();
        await einkSync.synchronize();
        expect((await eink.query('tb_notes')).single['reader_note'],
            'Updated on desktop');

        // The old editor submits its cached object, without an expected revision.
        await expectLater(IsolatedNoteDao(eink).updateBookNoteById(openEditor),
            throwsA(isA<NoteConflictException>()));
        expect(openEditor.readerNote, 'Original comment');
        await einkSync.synchronize();
        await desktopSync.synchronize();
        for (final db in [eink, desktop]) {
          expect((await db.query('tb_notes')).single['reader_note'],
              'Updated on desktop');
        }
      });

      test('control: genuine backward reading should still win', () async {
        await desktopReadsAndWrites();
        await einkSync.synchronize();
        // A real user action deliberately returns to an earlier chapter.
        await einkBooks.updateReadingPosition(1, 'chapter-3', .3);
        await einkSync.synchronize();
        await desktopSync.synchronize();
        expect((await desktop.query('tb_books')).single['last_read_position'],
            'chapter-3');
      });

      test('sleep/dispose flush never writes the stale reader position',
          () async {
        final session = ReaderProgressSession(einkBooks, 1);
        await session.refresh();
        await desktopReadsAndWrites();
        await einkSync.synchronize();
        final synced = await position(eink);
        for (var i = 0; i < 5; i++) await session.flush();
        expect((await position(eink)).revision, synced.revision);
        expect((await session.refresh()).position, 'chapter-8');
      });

      test(
          'queued stale actions fail after conflict, fresh backward action succeeds',
          () async {
        final session = ReaderProgressSession(einkBooks, 1);
        await session.refresh();
        final generation = session.generation;
        await desktopReadsAndWrites();
        await einkSync.synchronize();
        final first = session.record('chapter-2', .2, generation: generation);
        final second = session.record('chapter-3', .3, generation: generation);
        expect(await first, false);
        expect(await second, false);
        expect(session.current!.position, 'chapter-8');
        await session.refresh();
        expect(
            await session.record('chapter-4', .4,
                generation: session.generation),
            true);
        await einkSync.synchronize();
        await desktopSync.synchronize();
        expect(
            (await position(desktop)).data['last_read_position'], 'chapter-4');
      });

      test(
          'rapid genuine page turns serialize, without losing the final position',
          () async {
        final session = ReaderProgressSession(einkBooks, 1);
        await session.refresh();
        final generation = session.generation;
        final first = session.record('chapter-3', .3, generation: generation);
        final second = session.record('chapter-4', .4, generation: generation);
        expect(await first, true);
        expect(await second, true);
        await session.flush();
        expect((await position(eink)).data['last_read_position'], 'chapter-4');
      });

      test('an open editor cannot resurrect a remotely deleted note', () async {
        final draft = BookNote.fromDb((await eink.query('tb_notes')).single)
          ..readerNote = 'Unsaved local draft';
        await desktop.delete('tb_notes');
        await desktopSync.synchronize();
        await einkSync.synchronize();
        await expectLater(IsolatedNoteDao(eink).updateBookNoteById(draft),
            throwsA(isA<NoteConflictException>()));
        expect(draft.readerNote, 'Unsaved local draft');
        expect(await eink.query('tb_notes'), isEmpty);
      });

      test('unchanged note save does not create a fresh sync revision',
          () async {
        final draft = BookNote.fromDb((await eink.query('tb_notes')).single);
        // Normalize legacy nullable display fields with an explicit first save.
        final dao = IsolatedNoteDao(eink);
        await dao.updateBookNoteById(draft);
        final before = (await RowSyncStore(eink).snapshot())
            .singleWhere((r) => r.kind == 'note');
        await dao.updateBookNoteById(draft);
        final after = (await RowSyncStore(eink).snapshot())
            .singleWhere((r) => r.kind == 'note');
        expect(after.revision, before.revision);
        expect(after.clock, before.clock);
      });
    });
  }
}
