import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/providers/private_library.dart';
import 'package:modu_reader/dao/book.dart';
import 'package:modu_reader/dao/reading_time.dart';
import 'package:modu_reader/models/book.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'last_read_book_provider.g.dart';

class LastReadBookData {
  const LastReadBookData({
    required this.book,
    this.lastReadDate,
  });

  final Book book;
  final DateTime? lastReadDate;
}

@riverpod
class LastReadBook extends _$LastReadBook {
  @override
  Future<LastReadBookData?> build() async {
    ref.watch(privateLibraryRevisionProvider);
    return _load();
  }

  Future<LastReadBookData?> _load() async {
    final latestRecord = await readingTimeDao.selectLatestReadingRecord();

    Book? book;
    DateTime? lastReadDate;

    if (latestRecord != null) {
      final bookId = latestRecord['book_id'] as int?;
      final dateString = latestRecord['date'] as String?;
      lastReadDate = dateString != null ? DateTime.tryParse(dateString) : null;

      if (bookId != null) {
        try {
          final candidate = await bookDao.selectBookById(bookId);
          if (!candidate.isDeleted &&
              PrivateLibrary.instance.isVisible(candidate)) {
            book = candidate;
          }
        } catch (_) {
          // ignore if book not found
        }
      }
    }

    if (book == null) {
      final books = await bookDao.selectNotDeleteBooks(visibleOnly: true);
      if (books.isNotEmpty) {
        book = books.first;
      }
    }

    if (book == null) {
      return null;
    }

    return LastReadBookData(
      book: book,
      lastReadDate: lastReadDate,
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _load());
  }
}
