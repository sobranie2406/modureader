import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book_note.dart';

/// Serialize quick strokes and preserve an existing note at the same location.
class QuickMarkService {
  QuickMarkService(this.dao);
  final BookNoteDao dao;
  Future<void> _tail = Future.value();

  Future<BookNote> save({
    required int bookId,
    required String cfi,
    required String text,
    required String chapter,
    required String color,
  }) {
    final operation = _tail.then((_) async {
      if (text.trim().isEmpty ||
          text.length > 100000 ||
          !cfi.startsWith('epubcfi(') ||
          !cfi.endsWith(')')) {
        throw const FormatException('Invalid quick mark');
      }
      final existing = await dao.selectBookNoteByCfiAndBookId(cfi, bookId);
      if (existing.isNotEmpty) return existing.last;
      final now = DateTime.now();
      final note = BookNote(
          bookId: bookId,
          content: text,
          cfi: cfi,
          chapter: chapter,
          type: 'highlight',
          color: RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(color)
              ? color
              : 'ffd54f',
          createTime: now,
          updateTime: now);
      note.setId(await dao.save(note));
      return note;
    });
    _tail = operation.then<void>((_) {},
        onError: (Object error, StackTrace stack) {});
    return operation;
  }
}
