import 'dart:async';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('shutdown cancels every job, waits for cleanup and rejects new work',
      () async {
    final release = Completer<void>();
    late bool Function() cancelled;
    final started = <int>[];
    final queue =
        BookKnowledgeIndexQueue(worker: (book, progress, isCancelled) async {
      started.add(book.id);
      cancelled = isCancelled;
      await release.future;
      return const IndexBuildResult(status: IndexBuildStatus.cancelled);
    });
    queue.enqueue(book(1));
    queue.enqueue(book(2));
    var stopped = false;
    final closing = queue.pauseAndCancelAll().then((_) => stopped = true);
    expect(cancelled(), isTrue);
    expect(queue.enqueue(book(3)), isFalse);
    expect(stopped, isFalse);
    expect(queue.itemFor(2)?.status, BookKnowledgeQueueStatus.cancelled);
    release.complete();
    await closing;
    expect(stopped, isTrue);
    expect(started, [1]);
    expect(queue.activeItems, isEmpty);
    await Future<void>.delayed(Duration.zero);
    queue.dispose();
  });

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

  test('turning automatic indexing off cancels automatic jobs, not manual ones',
      () async {
    SharedPreferences.setMockInitialValues({
      'vectorModelEnabled': true,
      'autoVectorizeOnImport': true,
    });
    await Prefs().initPrefs();
    final gate = Completer<void>();
    final started = <int>[];
    late bool Function() cancellation;
    final queue = BookKnowledgeIndexQueue(
      automaticIndexingAllowed: () => Prefs().autoVectorizeOnImport,
      worker: (book, progress, isCancelled) async {
        started.add(book.id);
        cancellation = isCancelled;
        if (book.id == 1) await gate.future;
        return const IndexBuildResult(status: IndexBuildStatus.completed);
      },
    );
    addTearDown(queue.dispose);
    queue.enqueue(book(1), automatic: true);
    queue.enqueue(book(2), automatic: true);
    queue.enqueue(book(3));
    Prefs().autoVectorizeOnImport = false;
    applyVectorizationQueueSettings(queue: queue);
    expect(cancellation(), isTrue);
    expect(queue.itemFor(2)?.status, BookKnowledgeQueueStatus.cancelled);
    expect(queue.itemFor(3)?.status, BookKnowledgeQueueStatus.queued);
    expect(queue.enqueue(book(4), automatic: true), isFalse);
    gate.complete();
    await _waitForStatus(queue, 3, BookKnowledgeQueueStatus.completed);
    expect(started, [1, 3]);
    expect(queue.itemFor(1)?.status, BookKnowledgeQueueStatus.cancelled);
    // A formerly queued/cancelled book can be started explicitly again.
    expect(queue.enqueue(book(2)), isTrue);
    await _waitForStatus(queue, 2, BookKnowledgeQueueStatus.completed);
  });

  test(
      'stop all persists automatic-off, waits for cleanup and survives restart',
      () async {
    SharedPreferences.setMockInitialValues({
      'vectorModelEnabled': true,
      'autoVectorizeOnImport': true,
    });
    await Prefs().initPrefs();
    final gate = Completer<void>();
    final started = <int>[];
    late bool Function() cancellation;
    final queue =
        BookKnowledgeIndexQueue(worker: (book, progress, cancelled) async {
      started.add(book.id);
      cancellation = cancelled;
      await gate.future;
      return const IndexBuildResult(status: IndexBuildStatus.completed);
    });
    addTearDown(queue.dispose);
    queue.enqueue(book(1));
    queue.enqueue(book(2), automatic: true);
    var settled = false;
    final stopping =
        stopBookVectorization(queue: queue).then((_) => settled = true);
    expect(Prefs().autoVectorizeOnImport, isFalse);
    expect(cancellation(), isTrue);
    expect(queue.itemFor(2)?.status, BookKnowledgeQueueStatus.cancelled);
    expect(settled, isFalse);
    gate.complete();
    await stopping;
    expect(settled, isTrue);
    expect(started, [1]);
    expect(queue.activeItems, isEmpty);
    await Prefs().prefs.reload();
    final restarted =
        BookKnowledgeIndexQueue(worker: (book, progress, cancelled) async {
      fail('Stopped work must not restart');
    });
    addTearDown(restarted.dispose);
    expect(
        await enqueueMissingBooksForAutomaticIndexing(
          books: [book(1), book(2)],
          vectorModelEnabled: Prefs().vectorModelEnabled,
          autoVectorizeOnImport: Prefs().autoVectorizeOnImport,
          hasIndex: (_) async => false,
          isBookAvailable: (_) => true,
          queue: restarted,
        ),
        0);
  });

  test('stopping invalidates a startup scan suspended in an index check',
      () async {
    final gate = Completer<bool>();
    final queue =
        BookKnowledgeIndexQueue(worker: (book, progress, cancelled) async {
      fail('A cancelled startup scan must not enqueue work');
    });
    addTearDown(queue.dispose);
    final recovering = enqueueMissingBooksForAutomaticIndexing(
      books: [book(1), book(2)],
      vectorModelEnabled: true,
      autoVectorizeOnImport: true,
      hasIndex: (_) => gate.future,
      isBookAvailable: (_) => true,
      queue: queue,
    );
    await queue.cancelAutomatic();
    gate.complete(false);
    expect(await recovering, 0);
    expect(queue.activeItems, isEmpty);
  });

  test(
      'startup scan rechecks current preference after asynchronous index lookup',
      () async {
    var enabled = true;
    final gate = Completer<bool>();
    final queue =
        BookKnowledgeIndexQueue(worker: (book, progress, cancelled) async {
      fail('Disabled automatic work must not be queued');
    });
    addTearDown(queue.dispose);
    final recovering = enqueueMissingBooksForAutomaticIndexing(
      books: [book(1)],
      vectorModelEnabled: true,
      autoVectorizeOnImport: true,
      shouldContinue: () => enabled,
      hasIndex: (_) => gate.future,
      isBookAvailable: (_) => true,
      queue: queue,
    );
    enabled = false;
    gate.complete(false);
    expect(await recovering, 0);
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
