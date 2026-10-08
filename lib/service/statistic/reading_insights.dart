import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/models/book.dart';
import 'package:sqflite/sqflite.dart';

class ReadingInsightBook {
  const ReadingInsightBook(this.book, {this.lastDay, this.noteCount = 0});
  final Book book;
  final DateTime? lastDay;
  final int noteCount;
}

class ReadingInsights {
  const ReadingInsights({
    this.totalSeconds = 0,
    this.activeDays = 0,
    this.bestDaySeconds = 0,
    this.weekSeconds = 0,
    this.weekDays = 0,
    this.weekBooks = 0,
    this.recent = const [],
    this.mostAnnotated = const [],
  });

  final int totalSeconds, activeDays, bestDaySeconds;
  final int weekSeconds, weekDays, weekBooks;
  final List<ReadingInsightBook> recent, mostAnnotated;

  int get dailyAverageSeconds =>
      activeDays == 0 ? 0 : (totalSeconds / activeDays).round();

  /// Read-only aggregates; no schema changes, file scanning or cloud requests.
  /// A day is counted once even when several sessions/books were recorded.
  static Future<ReadingInsights> load(DatabaseExecutor db,
      {required DateTime now}) async {
    final today = DateTime(now.year, now.month, now.day);
    final monday = DateTime(
        today.year, today.month, today.day - (today.weekday - DateTime.monday));
    String day(DateTime value) => value.toIso8601String().substring(0, 10);
    const valid = 'reading_time > 0 AND DATE(date) <= DATE(?)';
    final daily = (await db.rawQuery('''
      SELECT COALESCE(SUM(seconds), 0) AS seconds, COUNT(*) AS days,
             COALESCE(MAX(seconds), 0) AS best
      FROM (SELECT SUM(reading_time) AS seconds FROM tb_reading_time
            WHERE $valid GROUP BY DATE(date))
    ''', [day(today)])).single;
    final week = (await db.rawQuery('''
      SELECT COALESCE(SUM(reading_time), 0) AS seconds,
             COUNT(DISTINCT DATE(date)) AS days,
             COUNT(DISTINCT book_id) AS books
      FROM tb_reading_time WHERE $valid AND DATE(date) >= DATE(?)
    ''', [day(today), day(monday)])).single;
    final recent = await db.rawQuery('''
      SELECT b.*, r.last_day FROM tb_books b
      JOIN (SELECT book_id, MAX(DATE(date)) AS last_day
            FROM tb_reading_time WHERE $valid GROUP BY book_id) r
        ON r.book_id = b.id
      ORDER BY r.last_day DESC, b.id DESC LIMIT 3
    ''', [day(today)]);
    final types = BookNoteDao.annotationTypes;
    final notes = await db.rawQuery('''
      SELECT b.*, n.note_count FROM tb_books b
      JOIN (SELECT book_id, COUNT(*) AS note_count FROM tb_notes
            WHERE type IN (${List.filled(types.length, '?').join(',')})
            GROUP BY book_id) n ON n.book_id = b.id
      ORDER BY n.note_count DESC, b.id DESC LIMIT 3
    ''', types);
    int count(Map<String, Object?> row, String key) =>
        (row[key] as num?)?.toInt() ?? 0;
    return ReadingInsights(
      totalSeconds: count(daily, 'seconds'),
      activeDays: count(daily, 'days'),
      bestDaySeconds: count(daily, 'best'),
      weekSeconds: count(week, 'seconds'),
      weekDays: count(week, 'days'),
      weekBooks: count(week, 'books'),
      recent: [
        for (final row in recent)
          ReadingInsightBook(Book.fromDb(row),
              lastDay: DateTime.tryParse(row['last_day'] as String)),
      ],
      mostAnnotated: [
        for (final row in notes)
          ReadingInsightBook(Book.fromDb(row),
              noteCount: count(row, 'note_count')),
      ],
    );
  }
}
