import 'package:modu_reader/enums/chart_mode.dart';

// Capture the selected interval when deleting, not when leaving statistics.
typedef ReadingTimeDeletion = ({int bookId, String? start, String? end});

ReadingTimeDeletion readingTimeDeletion({
  required int bookId,
  required DateTime date,
  required ChartMode mode,
  required bool isSelectingDay,
}) {
  final day = DateTime(date.year, date.month, date.day);
  late DateTime start;
  late DateTime end;
  if (isSelectingDay) {
    start = end = day;
  } else {
    switch (mode) {
      case ChartMode.week:
        start = DateTime(day.year, day.month, day.day - day.weekday + 1);
        end = DateTime(start.year, start.month, start.day + 6);
      case ChartMode.month:
        start = DateTime(day.year, day.month, 1);
        end = DateTime(day.year, day.month + 1, 0);
      case ChartMode.year:
        start = DateTime(day.year, 1, 1);
        end = DateTime(day.year, 12, 31);
      case ChartMode.heatmap:
        return (bookId: bookId, start: null, end: null);
    }
  }
  return (
    bookId: bookId,
    start: start.toIso8601String().substring(0, 10),
    end: end.toIso8601String().substring(0, 10),
  );
}

extension ReadingTimeDeletionQuery on ReadingTimeDeletion {
  String get where => start == null
      ? 'book_id = ?'
      : 'book_id = ? AND DATE(date) BETWEEN DATE(?) AND DATE(?)';

  List<Object?> get whereArgs => [
        bookId,
        if (start != null) ...[start, end]
      ];
}
