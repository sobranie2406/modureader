import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/dao/book_note.dart';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/service/book_player/quick_mark_service.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Notes extends BookNoteDao {
  _Notes(this.db);
  final Database db;
  Future<void> Function()? beforeMerge;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction) action) =>
      db.transaction(action);
  @override
  Future<int> save(BookNote note) => db.insert(BookNoteDao.table, note.toMap());
  @override
  Future<List<BookNote>> selectBookNoteByCfiAndBookId(
          String cfi, int bookId) async =>
      (await db.query(BookNoteDao.table,
              where: 'cfi = ? AND book_id = ?', whereArgs: [cfi, bookId]))
          .map(BookNote.fromDb)
          .toList();
  @override
  Future<List<BookNote>> selectBookNotesByBookId(int bookId) async => (await db
          .query(BookNoteDao.table, where: 'book_id = ?', whereArgs: [bookId]))
      .map(BookNote.fromDb)
      .toList();
  @override
  Future<BookNote?> mergeQuickMarks({
    required int bookId,
    required String cfi,
    required String text,
    required String color,
    required List<({int id, String cfi, String text})> sources,
  }) async {
    final change = beforeMerge;
    beforeMerge = null;
    await change?.call();
    return super.mergeQuickMarks(
        bookId: bookId, cfi: cfi, text: text, color: color, sources: sources);
  }
}

void main() {
  late Database db;
  late _Notes dao;
  late QuickMarkService service;
  late DocumentReflowPage page;
  final created = DateTime.utc(2026, 9, 1);

  Future<QuickMarkResult> stroke(int start, int end,
          {DocumentReflowAnchor? anchor,
          DocumentReflowPage? snapshot,
          int bookId = 7,
          String color = 'ffcc00'}) =>
      service.saveReflowStroke(
          bookId: bookId,
          anchor: anchor ?? (snapshot ?? page).anchor(start, end),
          page: snapshot ?? page,
          chapter: '当前页',
          color: color);

  Future<int> seed(int start, int end,
          {DocumentReflowAnchor? anchor,
          String? content,
          String type = 'highlight',
          String color = 'ffcc00',
          String? comment,
          int bookId = 7}) =>
      db.insert(
          BookNoteDao.table,
          BookNote(
                  bookId: bookId,
                  content: content ?? page.text.substring(start, end),
                  cfi: (anchor ?? page.anchor(start, end)).encode(),
                  chapter: '原页',
                  type: type,
                  color: color,
                  readerNote: comment,
                  createTime: created,
                  updateTime: created)
              .toMap());
  Future<List<BookNote>> all() async =>
      (await db.query(BookNoteDao.table, orderBy: 'id'))
          .map(BookNote.fromDb)
          .toList();

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE tb_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER, content TEXT,
      cfi TEXT, chapter TEXT, type TEXT, color TEXT, reader_note TEXT,
      create_time TEXT, update_time TEXT)''');
    dao = _Notes(db);
    service = QuickMarkService(dao);
    page = DocumentReflowPage(page: 2, ocr: true, rawText: '一二三四五六七八九十');
  });
  tearDown(() => db.close());

  test('sync waits for a pending quick-mark write before draining', () async {
    await seed(0, 3);
    final entered = Completer<void>(), release = Completer<void>();
    dao.beforeMerge = () async {
      entered.complete();
      await release.future;
    };
    final saving = stroke(3, 5);
    await entered.future;
    var flushed = false;
    final draining = service.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(flushed, isFalse);
    release.complete();
    await Future.wait([saving, draining]);
    expect(flushed, isTrue);
    expect((await all()).single.content, page.text.substring(0, 5));
  });

  test('saves source text and canonical original-page geometry', () async {
    page = DocumentReflowPage(
        page: 2,
        ocr: true,
        rawText: '一二三四五六',
        rawRegions: const [
          DocumentTextRegion(0, 3, DocumentImageRect(.1, .2, .3, .1)),
          DocumentTextRegion(3, 6, DocumentImageRect(.1, .4, .3, .1)),
        ]);
    final result = await stroke(1, 5,
        anchor: DocumentReflowAnchor(2, true, page.revision, 1, 5),
        color: 'bad color');
    expect(result.note.content, page.text.substring(1, 5));
    expect(result.note.cfi, page.anchor(1, 5).encode());
    expect(DocumentReflowAnchor.parse(result.note.cfi)!.rects, hasLength(2));
    expect(result.note.type, 'highlight');
    expect(result.note.color, 'ffd54f');
    expect(result.note.chapter, '当前页');
  });

  test('duplicate strokes retain annotated, recolored and underlined notes',
      () async {
    final id =
        await seed(3, 6, type: 'underline', color: 'ff0000', comment: '保留批注');
    final results = await Future.wait([stroke(3, 6), stroke(3, 6)]);
    expect(await all(), hasLength(1));
    for (final result in results) {
      expect(result.note.id, id);
      expect(result.note.type, 'underline');
      expect(result.note.color, 'ff0000');
      expect(result.note.readerNote, '保留批注');
      expect(result.replacedCfis, isEmpty);
    }
  });

  test('concurrent first reflow strokes do not add duplicates', () async {
    final results =
        await Future.wait([stroke(3, 6), stroke(3, 6), stroke(3, 6)]);
    expect(await all(), hasLength(1));
    expect(results.map((r) => r.note.id).toSet(), hasLength(1));
  });

  test('queued strokes merge a connected chain and preserve creation metadata',
      () async {
    final first = await seed(0, 3);
    final last = await seed(6, 9);
    final result = await stroke(3, 6);
    final notes = await all();
    expect(notes, hasLength(1));
    expect(result.note.id, first);
    expect(result.note.cfi, page.anchor(0, 9).encode());
    expect(result.note.content, page.text.substring(0, 9));
    expect(result.note.chapter, '原页');
    expect(result.note.createTime, created);
    expect(result.note.updateTime.isAfter(created), isTrue);
    expect(result.replacedCfis,
        [page.anchor(0, 3).encode(), page.anchor(6, 9).encode()]);
    expect(notes.single.id, isNot(last));
  });

  test('overlap and adjacency merge, but gaps do not', () async {
    await seed(0, 2);
    await seed(7, 9);
    expect((await stroke(1, 4)).note.cfi, page.anchor(0, 4).encode());
    expect(await all(), hasLength(2));
    expect((await stroke(4, 5)).note.cfi, page.anchor(0, 5).encode());
    expect(await all(), hasLength(2));
  });

  test('duplicate strokes inside an existing range do not add another note',
      () async {
    await seed(0, 9);
    await Future.wait([stroke(2, 4), stroke(2, 4), stroke(0, 9)]);
    final notes = await all();
    expect(notes, hasLength(1));
    expect(notes.single.cfi, page.anchor(0, 9).encode());
  });

  for (final change in [
    'comment',
    'color',
    'type',
    'page',
    'ocr',
    'revision',
    'content',
    'original'
  ]) {
    test('preserves an adjacent note with different $change', () async {
      var anchor = page.anchor(0, 3);
      if (change == 'page') {
        anchor = DocumentReflowAnchor(3, true, page.revision, 0, 3);
      } else if (change == 'ocr') {
        anchor = DocumentReflowAnchor(2, false, page.revision, 0, 3);
      } else if (change == 'revision') {
        anchor = DocumentReflowPage(page: 2, ocr: true, rawText: '另一版本')
            .anchor(0, 3);
      }
      final id = await seed(0, 3,
          anchor: anchor,
          content: change == 'content' ? '旧文本' : null,
          comment: change == 'comment' ? '保留批注' : null,
          color: change == 'color' ? 'ff0000' : 'ffcc00',
          type: change == 'type' ? 'underline' : 'highlight');
      if (change == 'original') {
        await db.update(
            BookNoteDao.table, {'cfi': page.anchor(0, 3).originalReference},
            where: 'id = ?', whereArgs: [id]);
      }
      final before = (await all()).single.toMap();
      final result = await stroke(3, 6);
      expect(result.note.cfi, page.anchor(3, 6).encode());
      expect(result.replacedCfis, isEmpty);
      expect(await all(), hasLength(2));
      expect((await all()).first.toMap(), before);
    });
  }

  test('a different book cannot be merged', () async {
    await seed(0, 3, bookId: 8);
    await stroke(3, 6);
    expect(await all(), hasLength(2));
    expect((await all()).first.cfi, page.anchor(0, 3).encode());
  });

  test('invalid or stale anchors fail without poisoning the shared save queue',
      () async {
    for (final anchor in [
      DocumentReflowAnchor(2, true, page.revision, -1, 3),
      DocumentReflowAnchor(2, true, page.revision, 3, 3),
      DocumentReflowAnchor(2, true, page.revision, 0, 99),
      DocumentReflowAnchor(3, true, page.revision, 0, 3),
      DocumentReflowAnchor(2, false, page.revision, 0, 3),
      DocumentReflowAnchor(2, true, '0' * 64, 0, 3),
      DocumentReflowAnchor(2, true, page.revision, 0, 3, original: true),
    ]) {
      await expectLater(stroke(0, 3, anchor: anchor), throwsFormatException);
    }
    expect(await all(), isEmpty);
    await service.saveStroke(
        bookId: 7,
        cfi: 'epubcfi(/6/2!/4/2:0)',
        text: '电子书原文',
        chapter: '一',
        color: 'ffcc00');
    await stroke(0, 3);
    expect(await all(), hasLength(2));
  });

  test('a late edit to a source prevents destructive merging', () async {
    final id = await seed(0, 3);
    dao.beforeMerge = () async {
      await db.update(BookNoteDao.table, {'reader_note': '刚写的批注'},
          where: 'id = ?', whereArgs: [id]);
    };
    final result = await stroke(3, 6);
    expect(result.replacedCfis, isEmpty);
    expect(result.note.cfi, page.anchor(3, 6).encode());
    final notes = await all();
    expect(notes, hasLength(2));
    expect(notes.first.readerNote, '刚写的批注');
    expect(notes.first.cfi, page.anchor(0, 3).encode());
  });

  test('a colliding protected union is not overwritten', () async {
    await seed(0, 3);
    final protected = await seed(0, 6, color: 'ff0000', comment: '保留');
    final result = await stroke(3, 6);
    expect(result.replacedCfis, isEmpty);
    final notes = await all();
    expect(notes, hasLength(3));
    expect(notes.firstWhere((n) => n.id == protected).readerNote, '保留');
    expect(notes.firstWhere((n) => n.id == protected).color, 'ff0000');
  });

  test('more than 128 connected sources are retained', () async {
    page = DocumentReflowPage(page: 2, ocr: true, rawText: 'a' * 130);
    for (var start = 0; start < 129; start++) {
      await seed(start, start + 1);
    }
    final result = await stroke(129, 130);
    expect(result.replacedCfis, isEmpty);
    expect(result.note.cfi, page.anchor(129, 130).encode());
    expect(await all(), hasLength(130));
  });

  test('failed merging rolls back all originals and the queue recovers',
      () async {
    await seed(0, 3);
    await seed(6, 9);
    await db.execute('''CREATE TRIGGER fail_delete BEFORE DELETE ON tb_notes
      BEGIN SELECT RAISE(ABORT, 'fixture failure'); END''');
    await expectLater(stroke(3, 6), throwsA(isA<DatabaseException>()));
    expect((await all()).map((n) => n.cfi),
        [page.anchor(0, 3).encode(), page.anchor(6, 9).encode()]);
    await db.execute('DROP TRIGGER fail_delete');
    expect((await stroke(3, 6)).note.cfi, page.anchor(0, 9).encode());
    expect(await all(), hasLength(1));
  });
}
