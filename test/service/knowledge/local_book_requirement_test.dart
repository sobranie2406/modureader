import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:modu_reader/service/knowledge/embedding_provider.dart';
import 'package:modu_reader/service/knowledge/embedding_model_manifest.dart';
import 'package:modu_reader/service/knowledge/local_embedding_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:modu_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:modu_reader/service/knowledge/index_build_marker.dart';
import 'package:modu_reader/service/knowledge/knowledge_engine.dart';
import 'package:modu_reader/service/knowledge/local_book_requirement.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:modu_reader/widgets/bookshelf/book_knowledge_actions.dart';
import 'package:flutter_test/flutter_test.dart';

class _ModelPaths extends PathProviderPlatform {
  _ModelPaths(this.path);
  final String path;
  @override
  Future<String> getApplicationDocumentsPath() async => path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PathProviderPlatform previousPaths;
  late Directory directory;
  late String previousPath;
  late Book local, remote;
  late BookKnowledgeIndexQueue queue;
  late List<int> started;
  late List<String> messages;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final model = LocalEmbeddingModels.byId(LocalEmbeddingModels.defaultModelId);
  final modelBytes = Uint8List.fromList(utf8.encode('fixture model'));
  final tokenizerBytes = Uint8List.fromList(utf8.encode('{}'));
  final fixtureFiles = {
    'model_quantized.onnx': modelBytes,
    'tokenizer.json': tokenizerBytes,
  };
  late Directory installedModel;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-local-index-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _ModelPaths(directory.path);
    SharedPreferences.setMockInitialValues({
      'vectorModelEnabled': true,
    });
    await Prefs().initPrefs();
    messenger.setMockMessageHandler('flutter/assets', (message) async {
      if (const StringCodec().decodeMessage(message) !=
          EmbeddingModelManifest.assetPath) {
        return null;
      }
      return const StringCodec().encodeMessage(jsonEncode({
        'models': [
          for (final item in LocalEmbeddingModels.all)
            {
              'id': item.id,
              'repository': item.hfModelId,
              'revision': '0' * 40,
              'files': [
                for (final f in fixtureFiles.entries)
                  {
                    'name': f.key,
                    'path': f.key.endsWith('.onnx') ? 'onnx/${f.key}' : f.key,
                    'size': f.value.length,
                    'sha256': sha256.convert(f.value).toString(),
                  },
              ],
            },
        ],
      }));
    });
    rootBundle.evict(EmbeddingModelManifest.assetPath);
    final store = LocalEmbeddingModelStore();
    installedModel = await store.modelDirectory(model);
    store.close();
    await installedModel.create(recursive: true);
    for (final f in fixtureFiles.entries) {
      await File('${installedModel.path}/${f.key}').writeAsBytes(f.value);
    }
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
    messenger.setMockMessageHandler('flutter/assets', null);
    rootBundle.evict(EmbeddingModelManifest.assetPath);
    documentPath = previousPath;
    PathProviderPlatform.instance = previousPaths;
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

  test('disabled model blocks single and batch menu actions before enqueueing',
      () async {
    Prefs().vectorModelEnabled = false;
    await queueBookForVectorization(local,
        queue: queue, showMessage: messages.add);
    await queueBooksForVectorization([local, local],
        queue: queue, showMessage: messages.add);
    expect(queue.items, isEmpty);
    expect(started, isEmpty);
    expect(messages, hasLength(2));
    expect(messages.every((message) => message.contains('未启用')), isTrue);
  });

  test('per-book override cannot bypass the disabled global switch', () async {
    await BookEmbeddingPreferences.save(local, 'local:multilingual-e5-small');
    Prefs().vectorModelEnabled = false;
    await queueBookForVectorization(local,
        queue: queue, showMessage: messages.add);
    expect(queue.items, isEmpty);
    expect(messages.single, contains('未启用'));
  });

  test('missing local model does not start extraction or download files',
      () async {
    await installedModel.delete(recursive: true);
    await queueBookForVectorization(local,
        queue: queue, showMessage: messages.add);
    expect(queue.items, isEmpty);
    expect(started, isEmpty);
    expect(messages.single, contains('尚未下载或文件损坏'));
    expect(await installedModel.exists(), isFalse);
    expect(await Directory('${directory.path}/knowledge').exists(), isFalse);
  });

  test(
      'batch queues an installed default model and skips a missing local override',
      () async {
    await File(remote.fileFullPath).writeAsString('Now local');
    await BookEmbeddingPreferences.save(remote, 'local:multilingual-e5-small');
    await queueBooksForVectorization([remote, local],
        queue: queue, showMessage: messages.add);
    expect(started, [local.id]);
    expect(queue.itemFor(remote.id), isNull);
    expect(messages.single, contains('已将 1 本书'));
    expect(messages.single, contains('已跳过 1 本向量模型不可用'));
    expect(messages.single, contains('Multilingual E5'));
  });

  test('execution rechecks switch and preserves old index and marker',
      () async {
    // Admission succeeds, then settings change before the worker runs.
    await EmbeddingProviderFactory.validateForBook(local);
    Prefs().vectorModelEnabled = false;
    final service = BookKnowledgeIndexService();
    final index = service.indexFile(local.id);
    await index.parent.create(recursive: true);
    await index.writeAsString('preserved-index');
    final marker = indexBuildMarker(index);
    await marker.writeAsString('preserved-marker');
    var events = 0;
    await expectLater(
        service.build(local, onProgress: (_, __, ___) => events++),
        throwsStateError);
    expect(events, 0);
    expect(await index.readAsString(), 'preserved-index');
    expect(await marker.readAsString(), 'preserved-marker');
  });

  test(
      'worker rejects missing model before diagnostics, extraction or marker creation',
      () async {
    await installedModel.delete(recursive: true);
    final service = BookKnowledgeIndexService();
    var events = 0;
    await expectLater(
        service.build(local, onProgress: (_, __, ___) => events++),
        throwsStateError);
    expect(events, 0);
    expect(await service.indexFile(local.id).parent.exists(), isFalse);
  });
}
