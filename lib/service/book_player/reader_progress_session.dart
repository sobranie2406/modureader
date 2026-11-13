import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/models/reading_position_snapshot.dart';
import 'package:modu_reader/models/narration_position.dart';

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
        // The merged database is authoritative, including its speech cursor.
        // Keeping an old cursor with the new revision would let it overwrite sync.
        return current = next;
      });

  Future<bool> record(String position, double percentage,
          {required int generation, NarrationPosition? narration}) =>
      _serial(() async {
        if (current == null || generation != this.generation) return false;
        final next = await dao.updateReadingPosition(
            bookId, position, percentage,
            expectedRevision: current!.revision, narration: narration);
        if (next == null) {
          current = await dao.readReadingPosition(bookId);
          this.generation++;
          return false;
        }
        current = next;
        return true;
      });

  /// Exit checkpoints use the displayed page, unless a speech cursor owns the
  /// resume point. CAS still prevents an old open reader from overwriting sync.
  Future<void> checkpointPage(String position, double percentage,
          {required int generation}) =>
      _serial(() async {
        final latest = current;
        if (latest == null ||
            generation != this.generation ||
            latest.narration?.canResume == true) {
          return;
        }
        final next = await dao.updateReadingPosition(
            bookId, position, percentage,
            expectedRevision: latest.revision);
        if (next != null) {
          current = next;
        } else {
          current = await dao.readReadingPosition(bookId);
          this.generation++;
        }
      });

  Future<void> flush() => _pending;

  Future<bool> recordNarration(NarrationPosition narration,
          {required int generation}) =>
      _serial(() async {
        final latest = current;
        if (latest == null || generation != this.generation) return false;
        final next = await dao.updateReadingPosition(
            bookId, latest.position, latest.percentage,
            expectedRevision: latest.revision, narration: narration);
        if (next == null) {
          current = await dao.readReadingPosition(bookId);
          this.generation++;
          return false;
        }
        current = next;
        return true;
      });
}
