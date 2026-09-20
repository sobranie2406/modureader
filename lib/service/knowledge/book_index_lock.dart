import 'dart:async';

final _bookIndexOperations = <int, Future<void>>{};

/// One writer per local book: import must not race indexing or deletion.
Future<T> withBookIndexLock<T>(
    int bookId, Future<T> Function() operation) async {
  final previous = _bookIndexOperations[bookId] ?? Future<void>.value();
  final done = Completer<void>();
  _bookIndexOperations[bookId] = done.future;
  try {
    await previous;
    return await operation();
  } finally {
    done.complete();
    if (identical(_bookIndexOperations[bookId], done.future)) {
      _bookIndexOperations.remove(bookId);
    }
  }
}
