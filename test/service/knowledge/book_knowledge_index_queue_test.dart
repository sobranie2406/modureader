import 'dart:async';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Book book(int id) => Book(
        id: id,
        title: 'Book $id',
        coverPath: '',
        filePath: '',
        lastReadPosition: '',
        readingPercentage: 0,
        author: 'Author',
        isDeleted: false,
        rating: 0,
        createTime: DateTime(2026),
        updateTime: DateTime(2026),
      );

  test('processes different books in FIFO order without concurrent workers',
      () async {
    final started = <int>[];
    final gates = <int, Completer<void>>{
      1: Completer<void>(),
      2: Completer<void>(),
    };
    final secondStarted = Completer<void>();
    final queue = BookKnowledgeIndexQueue(
      worker: (book, onProgress, isCancelled) async {
        started.add(book.id);
        if (book.id == 2) secondStarted.complete();
        onProgress('@embedding', 1, 2);
        await gates[book.id]!.future;
        return const IndexBuildResult(status: IndexBuildStatus.completed);
      },
    );
    addTearDown(queue.dispose);

    expect(queue.enqueue(book(1)), isTrue);
    expect(queue.enqueue(book(2)), isTrue);
    expect(started, [1]);
    expect(queue.itemFor(2)?.status, BookKnowledgeQueueStatus.queued);

    gates[1]!.complete();
    await secondStarted.future;
    expect(started, [1, 2]);
    expect(queue.itemFor(1)?.status, BookKnowledgeQueueStatus.completed);

    final completed = _waitForStatus(
      queue,
      2,
      BookKnowledgeQueueStatus.completed,
    );
    gates[2]!.complete();
    await completed;
  });

  test('deduplicates a book that is queued or running', () async {
    final gate = Completer<void>();
    var calls = 0;
    final queue = BookKnowledgeIndexQueue(
      worker: (book, onProgress, isCancelled) async {
        calls++;
        await gate.future;
        return const IndexBuildResult(status: IndexBuildStatus.completed);
      },
    );
    addTearDown(queue.dispose);

    expect(queue.enqueue(book(1)), isTrue);
    expect(queue.enqueue(book(1)), isFalse);
    expect(calls, 1);

    final completed = _waitForStatus(
      queue,
      1,
      BookKnowledgeQueueStatus.completed,
    );
    gate.complete();
    await completed;
    expect(calls, 1);
  });

  test('a failed book does not prevent the next queued book from running',
      () async {
    final secondStarted = Completer<void>();
    final queue = BookKnowledgeIndexQueue(
      worker: (book, onProgress, isCancelled) async {
        if (book.id == 1) throw StateError('broken book');
        secondStarted.complete();
        return const IndexBuildResult(status: IndexBuildStatus.completed);
      },
    );
    addTearDown(queue.dispose);

    queue.enqueueAll([book(1), book(2)]);
    await secondStarted.future;
    await _waitForStatus(
      queue,
      2,
      BookKnowledgeQueueStatus.completed,
    );

    expect(queue.itemFor(1)?.status, BookKnowledgeQueueStatus.failed);
    expect(queue.itemFor(2)?.status, BookKnowledgeQueueStatus.completed);
  });

  test('can cancel a queued book without interrupting the running book',
      () async {
    final firstGate = Completer<void>();
    final started = <int>[];
    final queue = BookKnowledgeIndexQueue(
      worker: (book, onProgress, isCancelled) async {
        started.add(book.id);
        if (book.id == 1) await firstGate.future;
        return const IndexBuildResult(status: IndexBuildStatus.completed);
      },
    );
    addTearDown(queue.dispose);

    queue.enqueue(book(1));
    queue.enqueue(book(2));
    await queue.cancel(2);

    expect(queue.itemFor(2)?.status, BookKnowledgeQueueStatus.cancelled);
    expect(started, [1]);

    final completed = _waitForStatus(
      queue,
      1,
      BookKnowledgeQueueStatus.completed,
    );
    firstGate.complete();
    await completed;
    expect(started, [1]);
  });

  test('automatic import indexing honors both settings and uses the queue',
      () async {
    final gate = Completer<void>();
    final queue = BookKnowledgeIndexQueue(
      worker: (book, onProgress, isCancelled) async {
        await gate.future;
        return const IndexBuildResult(status: IndexBuildStatus.completed);
      },
    );
    addTearDown(queue.dispose);

    expect(
      enqueueImportedBookForAutomaticIndexing(
        book: book(1),
        vectorModelEnabled: false,
        autoVectorizeOnImport: true,
        queue: queue,
      ),
      isFalse,
    );
    expect(
      enqueueImportedBookForAutomaticIndexing(
        book: book(1),
        vectorModelEnabled: true,
        autoVectorizeOnImport: false,
        queue: queue,
      ),
      isFalse,
    );
    expect(queue.itemFor(1), isNull);

    expect(
      enqueueImportedBookForAutomaticIndexing(
        book: book(1),
        vectorModelEnabled: true,
        autoVectorizeOnImport: true,
        queue: queue,
      ),
      isTrue,
    );
    expect(queue.itemFor(1)?.status.isActive, isTrue);

    final completed = _waitForStatus(
      queue,
      1,
      BookKnowledgeQueueStatus.completed,
    );
    gate.complete();
    await completed;
  });

  test('startup recovery queues only available books missing an index',
      () async {
    final gate = Completer<void>();
    final queue = BookKnowledgeIndexQueue(
      worker: (book, onProgress, isCancelled) async {
        await gate.future;
        return const IndexBuildResult(status: IndexBuildStatus.completed);
      },
    );
    addTearDown(queue.dispose);

    final added = await enqueueMissingBooksForAutomaticIndexing(
      books: [book(1), book(2), book(3)],
      vectorModelEnabled: true,
      autoVectorizeOnImport: true,
      hasIndex: (candidate) async => candidate.id == 1,
      isBookAvailable: (candidate) => candidate.id != 3,
      queue: queue,
    );

    expect(added, 1);
    expect(queue.itemFor(1), isNull);
    expect(queue.itemFor(2)?.status.isActive, isTrue);
    expect(queue.itemFor(3), isNull);

    final completed = _waitForStatus(
      queue,
      2,
      BookKnowledgeQueueStatus.completed,
    );
    gate.complete();
    await completed;
  });
}

Future<void> _waitForStatus(
  BookKnowledgeIndexQueue queue,
  int bookId,
  BookKnowledgeQueueStatus expected,
) {
  if (queue.itemFor(bookId)?.status == expected) return Future<void>.value();
  final completer = Completer<void>();
  void listener() {
    if (queue.itemFor(bookId)?.status != expected || completer.isCompleted) {
      return;
    }
    queue.removeListener(listener);
    completer.complete();
  }

  queue.addListener(listener);
  return completer.future.timeout(const Duration(seconds: 2));
}
