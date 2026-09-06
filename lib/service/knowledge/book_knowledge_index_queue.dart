import 'dart:async';
import 'dart:collection';
import 'package:anx_reader/service/feedback/crash_journal.dart';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/foundation.dart';

enum BookKnowledgeQueueStatus {
  queued,
  extracting,
  preparing,
  vectorizing,
  cancelling,
  completed,
  failed,
  cancelled,
}

extension BookKnowledgeQueueStatusX on BookKnowledgeQueueStatus {
  bool get isActive => switch (this) {
        BookKnowledgeQueueStatus.queued ||
        BookKnowledgeQueueStatus.extracting ||
        BookKnowledgeQueueStatus.preparing ||
        BookKnowledgeQueueStatus.vectorizing ||
        BookKnowledgeQueueStatus.cancelling =>
          true,
        _ => false,
      };
}

@immutable
class BookKnowledgeQueueItem {
  const BookKnowledgeQueueItem({
    required this.book,
    required this.status,
    required this.requestedAt,
    this.completed = 0,
    this.total = 0,
    this.errorMessage,
    this.finishedAt,
  });

  final Book book;
  final BookKnowledgeQueueStatus status;
  final DateTime requestedAt;
  final int completed;
  final int total;
  final String? errorMessage;
  final DateTime? finishedAt;

  double? get progress {
    final phaseProgress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
    return switch (status) {
      BookKnowledgeQueueStatus.queued => 0,
      BookKnowledgeQueueStatus.extracting => phaseProgress * 0.25,
      BookKnowledgeQueueStatus.preparing => 0.25 + phaseProgress * 0.05,
      BookKnowledgeQueueStatus.vectorizing => 0.30 + phaseProgress * 0.70,
      BookKnowledgeQueueStatus.completed => 1,
      BookKnowledgeQueueStatus.cancelling ||
      BookKnowledgeQueueStatus.failed ||
      BookKnowledgeQueueStatus.cancelled =>
        null,
    };
  }

  BookKnowledgeQueueItem copyWith({
    BookKnowledgeQueueStatus? status,
    int? completed,
    int? total,
    String? errorMessage,
    bool clearError = false,
    DateTime? finishedAt,
  }) {
    return BookKnowledgeQueueItem(
      book: book,
      status: status ?? this.status,
      requestedAt: requestedAt,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}

typedef BookKnowledgeIndexWorker = Future<IndexBuildResult> Function(
  Book book,
  IndexProgressCallback onProgress,
  bool Function() isCancelled,
);

/// A process-wide, single-worker queue for bookshelf vectorization jobs.
///
/// Enqueueing never waits for extraction or embedding. Books are processed in
/// FIFO order, one at a time, so an ONNX model cannot monopolize resources by
/// running several books concurrently. The queue lives outside bookshelf
/// widgets and therefore continues while the reader route is open.
class BookKnowledgeIndexQueue extends ChangeNotifier {
  BookKnowledgeIndexQueue({BookKnowledgeIndexWorker? worker})
      : _worker = worker ?? _defaultWorker;

  final BookKnowledgeIndexWorker _worker;
  final LinkedHashMap<int, BookKnowledgeQueueItem> _items = LinkedHashMap();
  final ListQueue<int> _pending = ListQueue();
  final Set<int> _cancelRequested = <int>{};
  final Map<int, Completer<void>> _settled = <int, Completer<void>>{};
  bool _isDraining = false;

  static Future<IndexBuildResult> _defaultWorker(
    Book book,
    IndexProgressCallback onProgress,
    bool Function() isCancelled,
  ) {
    return BookKnowledgeIndexService().build(
      book,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
  }

  List<BookKnowledgeQueueItem> get items => List.unmodifiable(_items.values);

  List<BookKnowledgeQueueItem> get activeItems => List.unmodifiable(
        _items.values.where((item) => item.status.isActive),
      );

  BookKnowledgeQueueItem? get current {
    for (final item in _items.values) {
      if (item.status != BookKnowledgeQueueStatus.queued &&
          item.status.isActive) {
        return item;
      }
    }
    return null;
  }

  int get queuedCount => _items.values
      .where((item) => item.status == BookKnowledgeQueueStatus.queued)
      .length;

  BookKnowledgeQueueItem? itemFor(int bookId) => _items[bookId];

  /// Returns false when this book is already queued or running.
  bool enqueue(Book book) {
    final existing = _items[book.id];
    if (existing != null && existing.status.isActive) return false;

    _items[book.id] = BookKnowledgeQueueItem(
      book: book,
      status: BookKnowledgeQueueStatus.queued,
      requestedAt: DateTime.now(),
    );
    _pending.add(book.id);
    _settled[book.id] = Completer<void>();
    notifyListeners();
    unawaited(_drain());
    return true;
  }

  int enqueueAll(Iterable<Book> books) {
    var added = 0;
    for (final book in books) {
      if (enqueue(book)) added++;
    }
    return added;
  }

  /// Cancels a queued/running task and resolves after its worker has stopped.
  Future<void> cancel(int bookId) async {
    final item = _items[bookId];
    if (item == null || !item.status.isActive) return;

    _cancelRequested.add(bookId);
    if (item.status == BookKnowledgeQueueStatus.queued) {
      _pending.remove(bookId);
      _items[bookId] = item.copyWith(
        status: BookKnowledgeQueueStatus.cancelled,
        finishedAt: DateTime.now(),
      );
      _completeSettlement(bookId);
      notifyListeners();
      return;
    }

    _items[bookId] = item.copyWith(
      status: BookKnowledgeQueueStatus.cancelling,
    );
    notifyListeners();
    await _settled[bookId]?.future;
  }

  Future<void> cancelAndRemove(int bookId) async {
    await cancel(bookId);
    _pending.remove(bookId);
    _cancelRequested.remove(bookId);
    _settled.remove(bookId);
    if (_items.remove(bookId) != null) notifyListeners();
  }

  void clearFinished() {
    final finishedIds = _items.entries
        .where((entry) => !entry.value.status.isActive)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in finishedIds) {
      _items.remove(id);
      _cancelRequested.remove(id);
      _settled.remove(id);
    }
    if (finishedIds.isNotEmpty) notifyListeners();
  }

  Future<void> _drain() async {
    if (_isDraining) return;
    _isDraining = true;
    try {
      while (_pending.isNotEmpty) {
        final bookId = _pending.removeFirst();
        final queued = _items[bookId];
        if (queued == null || _cancelRequested.contains(bookId)) {
          _completeSettlement(bookId);
          continue;
        }

        _items[bookId] = queued.copyWith(
          status: BookKnowledgeQueueStatus.extracting,
          completed: 0,
          total: 0,
          clearError: true,
        );
        notifyListeners();

        try {
          final result = await _worker(
            queued.book,
            (stage, completed, total) {
              _handleProgress(bookId, stage, completed, total);
            },
            () => _cancelRequested.contains(bookId),
          );
          final wasCancelled = _cancelRequested.contains(bookId) ||
              result.status == IndexBuildStatus.cancelled;
          final latest = _items[bookId] ?? queued;
          _items[bookId] = latest.copyWith(
            status: wasCancelled
                ? BookKnowledgeQueueStatus.cancelled
                : BookKnowledgeQueueStatus.completed,
            completed: wasCancelled ? latest.completed : 1,
            total: wasCancelled ? latest.total : 1,
            finishedAt: DateTime.now(),
          );
        } on Object catch (error, stackTrace) {
          CrashJournal.recordError(error, stackTrace);
          final latest = _items[bookId] ?? queued;
          if (_cancelRequested.contains(bookId)) {
            _items[bookId] = latest.copyWith(
              status: BookKnowledgeQueueStatus.cancelled,
              finishedAt: DateTime.now(),
            );
          } else {
            _items[bookId] = latest.copyWith(
              status: BookKnowledgeQueueStatus.failed,
              errorMessage: error.toString(),
              finishedAt: DateTime.now(),
            );
            AnxLog.severe(
              'Knowledge queue failed for book=$bookId: $error\n$stackTrace',
            );
          }
        } finally {
          _cancelRequested.remove(bookId);
          _completeSettlement(bookId);
          notifyListeners();
        }

        // Match ReadAny's pipeline: always yield between books so navigation
        // and reader gestures get a frame before the next task starts.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _isDraining = false;
      if (_pending.isNotEmpty) unawaited(_drain());
    }
  }

  void _handleProgress(
    int bookId,
    String stage,
    int completed,
    int total,
  ) {
    if (_cancelRequested.contains(bookId)) return;
    final item = _items[bookId];
    if (item == null || !item.status.isActive) return;

    final status = stage.startsWith('@extract:')
        ? BookKnowledgeQueueStatus.extracting
        : stage.startsWith('@embedding')
            ? BookKnowledgeQueueStatus.vectorizing
            : BookKnowledgeQueueStatus.preparing;
    _items[bookId] = item.copyWith(
      status: status,
      completed: completed,
      total: total,
    );
    notifyListeners();
  }

  void _completeSettlement(int bookId) {
    final completer = _settled[bookId];
    if (completer != null && !completer.isCompleted) completer.complete();
  }
}

final bookKnowledgeIndexQueue = BookKnowledgeIndexQueue();

/// Adds a newly imported book to the same observable FIFO queue used by the
/// bookshelf's manual vectorization actions.
bool enqueueImportedBookForAutomaticIndexing({
  required Book book,
  required bool vectorModelEnabled,
  required bool autoVectorizeOnImport,
  BookKnowledgeIndexQueue? queue,
}) {
  if (!vectorModelEnabled ||
      !autoVectorizeOnImport ||
      book.id <= 0 ||
      book.isDeleted) {
    return false;
  }
  return (queue ?? bookKnowledgeIndexQueue).enqueue(book);
}

/// Requeues books whose automatic indexing was interrupted before an index
/// file was committed. This runs once when the bookshelf is created.
Future<int> enqueueMissingBooksForAutomaticIndexing({
  required Iterable<Book> books,
  required bool vectorModelEnabled,
  required bool autoVectorizeOnImport,
  required Future<bool> Function(Book book) hasIndex,
  required bool Function(Book book) isBookAvailable,
  BookKnowledgeIndexQueue? queue,
}) async {
  if (!vectorModelEnabled || !autoVectorizeOnImport) return 0;

  final targetQueue = queue ?? bookKnowledgeIndexQueue;
  var added = 0;
  for (final book in books) {
    if (book.id <= 0 || book.isDeleted || !isBookAvailable(book)) continue;
    if (await hasIndex(book)) continue;
    if (targetQueue.enqueue(book)) added++;
  }
  return added;
}
