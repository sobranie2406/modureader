import 'package:modu_reader/enums/chart_mode.dart';
import 'package:modu_reader/models/reading_time_deletion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  ReadingTimeDeletion scope(DateTime date,
          {ChartMode mode = ChartMode.week, bool day = false, int book = 1}) =>
      readingTimeDeletion(
        bookId: book,
        date: date,
        mode: mode,
        isSelectingDay: day,
      );

  test('calendar ranges include cross-year weeks and leap months', () {
    expect(scope(DateTime(2026, 1, 1)),
        (bookId: 1, start: '2025-12-29', end: '2026-01-04'));
    expect(scope(DateTime(2024, 2, 10), mode: ChartMode.month),
        (bookId: 1, start: '2024-02-01', end: '2024-02-29'));
    expect(scope(DateTime(2026, 10, 18), mode: ChartMode.year),
        (bookId: 1, start: '2026-01-01', end: '2026-12-31'));
    expect(scope(DateTime(2026, 10, 18), mode: ChartMode.heatmap),
        (bookId: 1, start: null, end: null));
    expect(scope(DateTime(2026, 10, 18), mode: ChartMode.year, day: true),
        (bookId: 1, start: '2026-10-18', end: '2026-10-18'));
  });

  test('undo is independent for different days of the same book', () {
    final first = scope(DateTime(2026, 10, 17), day: true);
    final second = scope(DateTime(2026, 10, 18), day: true);
    final pending = {first, second};
    pending.remove(scope(DateTime(2026, 10, 18), day: true));
    expect(pending, {first});
  });

  for (final mode in ChartMode.values) {
    test('SQL deletes only the selected book and $mode interval', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute('CREATE TABLE history (book_id INTEGER, date TEXT)');
      for (final book in [1, 2]) {
        for (final date in [
          '2025-12-31',
          '2026-01-01',
          '2026-10-11',
          '2026-10-12',
          '2026-10-18T23:59:59',
          '2026-10-19',
          '2026-10-31',
          '2026-11-01',
          '2026-12-31',
          '2027-01-01',
        ]) {
          await db.insert('history', {'book_id': book, 'date': date});
        }
      }
      final deletion = scope(DateTime(2026, 10, 18), mode: mode);
      final removed = await db.delete('history',
          where: deletion.where, whereArgs: deletion.whereArgs);
      expect(
          removed,
          switch (mode) {
            ChartMode.week => 2,
            ChartMode.month => 5,
            ChartMode.year => 8,
            ChartMode.heatmap => 10,
          });
      expect((await db.query('history', where: 'book_id = 2')).length, 10);
    });
  }

  test('reported case: deleting seven seconds retains earlier history',
      () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('CREATE TABLE history '
        '(book_id INTEGER, date TEXT, reading_time INTEGER)');
    for (final row in [
      {'book_id': 1, 'date': '2026-10-16', 'reading_time': 22320},
      {'book_id': 1, 'date': '2026-10-18', 'reading_time': 3},
      {'book_id': 1, 'date': '2026-10-18T15:00:00', 'reading_time': 4},
      {'book_id': 2, 'date': '2026-10-18', 'reading_time': 60},
    ]) {
      await db.insert('history', row);
    }
    final deletion = scope(DateTime(2026, 10, 18), day: true);
    expect(
        await db.delete('history',
            where: deletion.where, whereArgs: deletion.whereArgs),
        2);
    final remaining = await db.query('history', orderBy: 'book_id');
    expect(remaining.map((row) => row['reading_time']), [22320, 60]);
  });
}
