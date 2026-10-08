import 'package:anx_reader/service/statistic/reading_insights.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'sync/row_sync_test.dart' show fixture, bookRow, noteRow;

void main() {
  sqfliteFfiInit();
  late Database db;
  setUp(() async => db = await fixture(install: false));
  tearDown(() => db.close());

  Future<void> read(int book, String date, int seconds) => db.insert(
      'tb_reading_time',
      {'book_id': book, 'date': date, 'reading_time': seconds});

  test('empty history has zero averages and no recommendations', () async {
    final data = await ReadingInsights.load(db, now: DateTime(2026, 10, 8));
    expect(data.dailyAverageSeconds, 0);
    expect(data.weekDays, 0);
    expect(data.weekBooks, 0);
    expect(data.recent, isEmpty);
    expect(data.mostAnnotated, isEmpty);
  });

  test(
      'days are distinct across books/sessions, invalid and future entries excluded',
      () async {
    await db.insert('tb_books', bookRow(2));
    await read(1, '2026-10-04', 600); // Previous Sunday.
    await read(1, '2026-10-05', 600);
    await read(1, '2026-10-05T12:00:00', 600);
    await read(2, '2026-10-05', 1200);
    await read(2, '2026-10-08', 600);
    await read(1, '2026-10-09', 9999);
    await read(1, 'invalid', 9999);
    await read(1, '2026-10-07', 0);
    await read(1, '2026-10-06', -100);
    final data = await ReadingInsights.load(db, now: DateTime(2026, 10, 8, 18));
    expect(data.totalSeconds, 3600);
    expect(data.activeDays, 3);
    expect(data.dailyAverageSeconds, 1200);
    expect(data.bestDaySeconds, 2400);
    expect(data.weekSeconds, 3000);
    expect(data.weekDays, 2);
    expect(data.weekBooks, 2);
    expect(data.recent.map((entry) => entry.book.id), [2, 1]);
  });

  test('week boundaries cross years and do not use a rolling seven day window',
      () async {
    await read(1, '2025-12-28', 300);
    await read(1, '2025-12-29', 600);
    await read(1, '2026-01-01', 900);
    final data = await ReadingInsights.load(db, now: DateTime(2026, 1, 1));
    expect(data.weekSeconds, 1500);
    expect(data.weekDays, 2);
    expect(data.activeDays, 3);
  });

  test('rankings limit to three, retain deleted metadata and exclude reviews',
      () async {
    for (var id = 1; id <= 4; id++) {
      if (id > 1) await db.insert('tb_books', bookRow(id));
      await read(id, '2026-10-0$id', 60);
      for (var n = 0; n < id; n++) {
        await db.insert('tb_notes', noteRow(id, '$n'));
      }
    }
    await db.insert('tb_notes', noteRow(1, 'review')..['type'] = 'review');
    await db.insert('tb_notes', noteRow(1, 'bookmark')..['type'] = 'bookmark');
    await db.update('tb_books', {'is_deleted': 1}, where: 'id = 4');
    final data = await ReadingInsights.load(db, now: DateTime(2026, 10, 8));
    expect(data.recent.map((entry) => entry.book.id), [4, 3, 2]);
    expect(data.mostAnnotated.map((entry) => entry.book.id), [4, 3, 2]);
    expect(data.mostAnnotated.map((entry) => entry.noteCount), [4, 3, 2]);
    expect(data.recent.first.book.isDeleted, true);
    expect(
        (await db.query('tb_books', where: 'id = 4')).single['is_deleted'], 1);
  });
}
