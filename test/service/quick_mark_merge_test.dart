import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/book_player/quick_mark_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Notes extends BookNoteDao {
  _Notes(this.db);
  final Database db;
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
}

void main() {
  late Database db;
  late _Notes dao;
  late QuickMarkService service;
  const left = 'epubcfi(/6/2!/4/2,/1:0,/1:3)';
  const right = 'epubcfi(/6/2!/4/2,/1:6,/1:9)';
  const middle = 'epubcfi(/6/2!/4/2,/1:3,/1:6)';
  const union = 'epubcfi(/6/2!/4/2,/1:0,/1:9)';
  final created = DateTime.utc(2026, 9, 1);

  Future<void> seed() async {
    for (final (id, cfi, text) in [(1, left, '一二三'), (2, right, '七八九')]) {
      await db.insert(
          BookNoteDao.table,
          BookNote(
                  id: id,
                  bookId: 7,
                  content: text,
                  cfi: cfi,
                  chapter: '第一章',
                  type: 'highlight',
                  color: 'ffcc00',
                  createTime: created,
                  updateTime: created)
              .toMap());
    }
  }

  Future<QuickMarkResult> stroke({Map? overrideMerge}) => service.saveStroke(
      bookId: 7,
      cfi: middle,
      text: '四五六',
      chapter: '当前章节',
      color: 'ffcc00',
      merge: overrideMerge ??
          {
            'cfi': union,
            'text': '一二三四五六七八九',
            'sources': [
              {'id': 1, 'cfi': left, 'text': '一二三'},
              {'id': 2, 'cfi': right, 'text': '七八九'},
            ],
          });
  Future<List<BookNote>> all() async =>
      (await db.query(BookNoteDao.table)).map(BookNote.fromDb).toList();

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE tb_notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT, book_id INTEGER, content TEXT,
      cfi TEXT, chapter TEXT, type TEXT, color TEXT, reader_note TEXT,
      create_time TEXT, update_time TEXT)''');
    dao = _Notes(db);
    service = QuickMarkService(dao);
    await seed();
  });
  tearDown(() => db.close());

  test(
      'connected strokes become one persistent note preserving id and creation metadata',
      () async {
    final result = await stroke();
    final notes = await all();
    expect(notes, hasLength(1));
    expect(notes.single.id, 1);
    expect(notes.single.cfi, union);
    expect(notes.single.content, '一二三四五六七八九');
    expect(notes.single.createTime, created);
    expect(notes.single.chapter, '第一章');
    expect(notes.single.updateTime.isAfter(created), isTrue);
    expect(result.replacedCfis, [left, right]);
    expect(result.toJson()['annotation']['hasReaderNote'], isFalse);
  });

  for (final change in [
    {'reader_note': '保留我的批注'},
    {'color': 'ff0000'},
    {'type': 'underline'},
    {'book_id': 8},
    {'content': '正文已变化'},
    {'cfi': 'epubcfi(/6/4!/4/2)'},
  ]) {
    test(
        'changed source $change is retained and the new stroke is saved separately',
        () async {
      await db.update(BookNoteDao.table, change, where: 'id = 2');
      final result = await stroke();
      expect(result.replacedCfis, isEmpty);
      expect(result.note.cfi, middle);
      final notes = await all();
      expect(notes, hasLength(3));
      expect(notes.firstWhere((n) => n.id == 1).cfi, left);
      for (final entry in change.entries) {
        expect(
            notes.firstWhere((n) => n.id == 2).toMap()[entry.key], entry.value);
      }
    });
  }

  test('failed deletion rolls back the expanded range and keeps both originals',
      () async {
    await db.execute('''CREATE TRIGGER fail_delete BEFORE DELETE ON tb_notes
      BEGIN SELECT RAISE(ABORT, 'fixture failure'); END''');
    await expectLater(stroke(), throwsA(isA<DatabaseException>()));
    final notes = await all();
    expect(notes.map((n) => n.cfi), [left, right]);
    expect(notes.map((n) => n.content), ['一二三', '七八九']);
    await db.execute('DROP TRIGGER fail_delete');
    expect((await stroke()).note.cfi, union,
        reason: 'failure must not poison the save queue');
  });

  test('a colliding unrelated annotation is not overwritten', () async {
    await db.insert(
        BookNoteDao.table,
        BookNote(
                bookId: 7,
                content: 'protected',
                cfi: union,
                chapter: '',
                type: 'highlight',
                color: 'ff0000',
                readerNote: '保留',
                updateTime: created)
            .toMap());
    expect((await stroke()).replacedCfis, isEmpty);
    expect(await all(), hasLength(4));
  });

  test('cross-spine/malformed merge plans never remove an existing mark',
      () async {
    final result = await stroke(overrideMerge: {
      'cfi': 'epubcfi(/6/4!/4/2,/1:0,/1:9)',
      'text': '一二三四五六七八九',
      'sources': [
        {'id': 1, 'cfi': left, 'text': '一二三'}
      ],
    });
    expect(result.replacedCfis, isEmpty);
    expect(await all(), hasLength(3));
  });
}
