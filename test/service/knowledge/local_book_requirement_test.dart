import 'dart:async';
import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/index_build_marker.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/service/knowledge/local_book_requirement.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/bookshelf/book_knowledge_actions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late String previousPath;
  late Book local, remote;
  late BookKnowledgeIndexQueue queue;
  late List<int> started;
  late List<String> messages;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-local-index-');
    previousPath = documentPath;
    documentPath = directory.path;
    local = Book.mock().copyWith(id: 1, filePath: 'local.txt');
    remote = Book.mock().copyWith(id: 2, filePath: 'remote.epub');
    await File(local.fileFullPath).writeAsString('Local content');
    started = [];
    messages = [];
    queue = BookKnowledgeIndexQueue(worker: (book, progress, cancelled) async {
      started.add(book.id);
      return const IndexBuildResult(status: IndexBuildStatus.completed);
    });
  });
  tearDown(() async {
    await queue.pauseAndCancelAll();
    await Future<void>.delayed(Duration.zero);
    queue.dispose();
    documentPath = previousPath;
    await directory.delete(recursive: true);
  });

  test('a remote-only book gets a download instruction, not a failed task',
      () async {
    await queueBookForVectorization(remote,
        queue: queue, showMessage: messages.add);
    expect(started, isEmpty);
    expect(queue.items, isEmpty);
    expect(messages.single, contains('请先下载书籍'));
    expect(messages.single, isNot(contains('已加入')));
    expect(messages.single, isNot(contains(directory.path)));
  });

  test('the same remote record can be queued after its book is downloaded',
      () async {
    await queueBookForVectorization(remote,
        queue: queue, showMessage: messages.add);
    await File(remote.fileFullPath).writeAsString('Downloaded content');
    await queueBookForVectorization(remote,
        queue: queue, showMessage: messages.add);
    expect(started, [remote.id]);
    expect(messages.last, contains('已加入向量化队列'));
  });

  test('mixed batch queues local books and counts skipped books once',
      () async {
    await queueBooksForVectorization([remote, local, remote],
        queue: queue, showMessage: messages.add);
    expect(started, [local.id]);
    expect(queue.itemFor(remote.id), isNull);
    expect(messages, hasLength(1));
    expect(messages.single, contains('已将 1 本书'));
    expect(messages.single, contains('已跳过 1 本'));
    expect(messages.single, contains('请先下载'));
  });

  test('an entirely remote batch is not reported as already queued', () async {
    await queueBooksForVectorization([remote],
        queue: queue, showMessage: messages.add);
    expect(queue.items, isEmpty);
    expect(messages.single, contains('已跳过 1 本'));
    expect(messages.single, isNot(contains('已在向量化队列')));
  });

  test('empty selection does nothing', () async {
    await queueBooksForVectorization([],
        queue: queue, showMessage: messages.add);
    expect(messages, isEmpty);
    expect(queue.items, isEmpty);
  });

  test('blank or directory paths cannot count as downloaded books', () async {
    await Directory('${directory.path}/folder').create();
    for (final path in ['', ' ', 'folder']) {
      await expectLater(
          requireLocalBookForIndexing(remote.copyWith(filePath: path)),
          throwsA(isA<LocalBookRequiredException>()));
    }
    await requireLocalBookForIndexing(local);
  });

  test('duplicate local clicks still use the queue deduplication', () async {
    final release = Completer<void>();
    final busyQueue =
        BookKnowledgeIndexQueue(worker: (book, progress, cancelled) async {
      await release.future;
      return const IndexBuildResult(status: IndexBuildStatus.completed);
    });
    try {
      await queueBookForVectorization(local,
          queue: busyQueue, showMessage: messages.add);
      await queueBookForVectorization(local,
          queue: busyQueue, showMessage: messages.add);
      expect(busyQueue.items, hasLength(1));
      expect(messages.last, contains('已在向量化队列中'));
    } finally {
      release.complete();
      await busyQueue.pauseAndCancelAll();
      await Future<void>.delayed(Duration.zero);
      busyQueue.dispose();
    }
  });

  test(
      'service rejects missing source before markers, model loading or extraction',
      () async {
    final service = BookKnowledgeIndexService();
    var progressEvents = 0;
    await expectLater(
        service.build(remote, onProgress: (_, __, ___) => progressEvents++),
        throwsA(isA<LocalBookRequiredException>()));
    expect(progressEvents, 0);
    expect(await service.indexFile(remote.id).parent.exists(), false);
  });

  test(
      'source removed while queued does not modify an existing index or marker',
      () async {
    final service = BookKnowledgeIndexService();
    final index = service.indexFile(local.id);
    await index.parent.create(recursive: true);
    await index.writeAsString('preserved-index');
    final marker = indexBuildMarker(index);
    await marker.writeAsString('preserved-marker');
    await requireLocalBookForIndexing(local);
    await File(local.fileFullPath).delete();
    await expectLater(
        service.build(local), throwsA(isA<LocalBookRequiredException>()));
    expect(await index.readAsString(), 'preserved-index');
    expect(await marker.readAsString(), 'preserved-marker');
  });

  test('already cancelled work remains cancelled even with a missing file',
      () async {
    final result = await BookKnowledgeIndexService()
        .build(remote, isCancelled: () => true);
    expect(result.status, IndexBuildStatus.cancelled);
  });
}
