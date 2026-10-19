import 'package:anx_reader/dao/reading_round.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/models/reading_round.dart';
import 'package:sqflite/sqflite.dart';

/// Post-merge reconciliation for synced reading rounds.
///
/// The wire format carries round records and `time.round`; the local
/// `tb_books.current_round` and `tb_reading_rounds.total_reading_time` are
/// derived caches. After every merge (and again after a local upgrade) this
/// method restores these invariants:
///
/// 1. time rows whose round was cancelled on another device (undo) move back to
///    the nearest visible previous round, so they can never become orphans;
/// 2. `tb_books.current_round` follows the highest visible round, so the reader
///    on this device starts writing the same round as the other device;
/// 3. per-round totals are recomputed from the synced time rows, so two
///    devices finishing the same round cannot disagree about a stored total.
class ReadingRoundSync {
  ReadingRoundSync._();

  static Future<void> reconcile(Database db) async {
    await db.transaction((txn) async {
      final roundRows = await txn.query(
        ReadingRoundDao.table,
        columns: ['book_id', 'round_number', 'status'],
      );
      final byBook = <int, Map<int, String>>{};
      for (final row in roundRows) {
        final bookId = row['book_id'] as int?;
        final number = row['round_number'] as int?;
        if (bookId == null || number == null) continue;
        byBook.putIfAbsent(bookId, () => {})[number] =
            row['status'] as String? ?? ReadingRound.statusReading;
      }

      bool visible(String status) => status != ReadingRound.statusCancelled;

      // 1) Re-attribute time rows that belong to a cancelled/missing round.
      final timeRows = await txn.query(
        ReadingTimeDao.table,
        columns: ['id', 'book_id', 'round'],
      );
      for (final row in timeRows) {
        final id = row['id'] as int?;
        final bookId = row['book_id'] as int?;
        final round = (row['round'] as num?)?.toInt() ?? 1;
        if (id == null || bookId == null) continue;
        final rounds = byBook[bookId];
        final status = rounds?[round];
        if (status != null && visible(status)) continue;

        var target = 1;
        if (rounds != null) {
          final candidates = rounds.entries
              .where((entry) => entry.key < round && visible(entry.value))
              .map((entry) => entry.key)
              .toList();
          if (candidates.isNotEmpty) {
            target = candidates.reduce((a, b) => a > b ? a : b);
          }
        }
        if (target != round) {
          await txn.update(
            ReadingTimeDao.table,
            {'round': target},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }

      // 2) Derive current_round; 3) recompute totals.
      for (final entry in byBook.entries) {
        final bookId = entry.key;
        final visibleRounds = entry.value.entries
            .where((entry) => visible(entry.value))
            .toList();
        final readingRounds = visibleRounds
            .where((entry) => entry.value == ReadingRound.statusReading)
            .map((entry) => entry.key)
            .toList();
        final numbers = visibleRounds.map((entry) => entry.key).toList();
        if (numbers.isEmpty) continue;

        final current = readingRounds.isNotEmpty
            ? readingRounds.reduce((a, b) => a > b ? a : b)
            : numbers.reduce((a, b) => a > b ? a : b);
        await txn.update(
          'tb_books',
          {'current_round': current},
          where: 'id = ? AND (current_round IS NULL OR current_round != ?)',
          whereArgs: [bookId, current],
        );

        for (final number in numbers) {
          await txn.rawUpdate(
            'UPDATE ${ReadingRoundDao.table} SET total_reading_time = '
            'COALESCE((SELECT SUM(reading_time) FROM ${ReadingTimeDao.table} '
            'WHERE book_id = ? AND round = ?), 0) '
            'WHERE book_id = ? AND round_number = ?',
            [bookId, number, bookId, number],
          );
        }
      }

      // A book with no visible round rows is on the first round. This also
      // repairs a stale cache left by an interrupted pre-transaction version.
      await txn.rawUpdate(
        'UPDATE tb_books SET current_round = 1 '
        'WHERE (current_round IS NULL OR current_round != 1) '
        'AND id NOT IN (SELECT book_id FROM ${ReadingRoundDao.table} '
        'WHERE status != ?)',
        [ReadingRound.statusCancelled],
      );
    });
  }
}
