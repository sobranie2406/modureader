import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/service/book_player/quick_mark_service.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryNotes extends BookNoteDao {
  final notes = <BookNote>[];
  bool failNext = false;
  @override
  Future<List<BookNote>> selectBookNoteByCfiAndBookId(
          String cfi, int bookId) async =>
      notes.where((n) => n.cfi == cfi && n.bookId == bookId).toList();
  @override
  Future<int> save(BookNote note) async {
    if (failNext) {
      failNext = false;
      throw StateError('test failure');
    }
    await Future<void>.delayed(Duration.zero);
    notes.add(note);
    return notes.length;
  }
}

void main() {
  late MemoryNotes dao;
  late QuickMarkService service;
  Future<BookNote> save(
          {String cfi = 'epubcfi(/6/2!/4/2:0)',
          String text = '中文划线\n第二行',
          int book = 7}) =>
      service.save(
          bookId: book, cfi: cfi, text: text, chapter: '第一章', color: 'ffcc00');
  setUp(() {
    dao = MemoryNotes();
    service = QuickMarkService(dao);
  });
  test('quick mark persists an actual highlight with chapter and current color',
      () async {
    final note = await save();
    expect(note.id, 1);
    expect(note.bookId, 7);
    expect(note.type, 'highlight');
    expect(note.chapter, '第一章');
    expect(note.color, 'ffcc00');
    expect(note.content, '中文划线\n第二行');
    expect(note.createTime, isNotNull);
  });
  test('rapid duplicate strokes never replace an existing reader note',
      () async {
    final original = await save();
    original.readerNote = 'Keep my comment';
    original.type = 'underline';
    final results = await Future.wait([save(), save()]);
    expect(dao.notes, hasLength(1));
    expect(results.every((n) => identical(n, original)), isTrue);
    expect(original.readerNote, 'Keep my comment');
    expect(original.type, 'underline');
    await save(book: 8);
    expect(dao.notes, hasLength(2));
  });
  test('concurrent first strokes at same CFI are serialized', () async {
    await Future.wait([save(), save(), save()]);
    expect(dao.notes, hasLength(1));
  });
  test(
      'invalid/empty selection does not write; a failure does not poison later strokes',
      () async {
    await expectLater(save(text: '  '), throwsFormatException);
    await expectLater(save(cfi: 'bad'), throwsFormatException);
    expect(dao.notes, isEmpty);
    dao.failNext = true;
    await expectLater(save(), throwsStateError);
    await save();
    expect(dao.notes, hasLength(1));
  });
}
