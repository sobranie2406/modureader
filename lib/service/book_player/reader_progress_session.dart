import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/models/reading_position_snapshot.dart';

/// Serializes real reading actions and database refreshes for one open reader.
/// Lifecycle saves merely drain work; they never invent a new reading action.
class ReaderProgressSession {
  ReaderProgressSession(this.dao, this.bookId);
  final BookDao dao;
  final int bookId;
  ReadingPositionSnapshot? current;
  int generation = 0;
  Future<void> _pending = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<ReadingPositionSnapshot> refresh() => _serial(() async {
        final next = await dao.readReadingPosition(bookId);
        if (current?.revision != next.revision) generation++;
        return current = next;
      });

  Future<bool> record(String position, double percentage,
          {required int generation}) =>
      _serial(() async {
        if (current == null || generation != this.generation) return false;
        final next = await dao.updateReadingPosition(
            bookId, position, percentage,
            expectedRevision: current!.revision);
        if (next == null) {
          current = await dao.readReadingPosition(bookId);
          this.generation++;
          return false;
        }
        current = next;
        return true;
      });

  Future<void> flush() => _pending;
}
