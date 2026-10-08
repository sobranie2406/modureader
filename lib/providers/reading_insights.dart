import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/current_reading.dart';
import 'package:anx_reader/service/statistic/reading_insights.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// All four optional cards share one result. Page turns do not reload it;
/// returning from a book or refreshing the library does.
final readingInsightsProvider =
    FutureProvider.autoDispose<ReadingInsights>((ref) {
  ref.watch(currentReadingProvider.select((state) => state.isReading));
  ref.watch(bookListProvider);
  return DBHelper()
      .database
      .then((db) => ReadingInsights.load(db, now: DateTime.now()));
});
