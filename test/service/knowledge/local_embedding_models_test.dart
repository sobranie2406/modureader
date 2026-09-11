import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/knowledge/embedding_model_manifest.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:anx_reader/service/knowledge/onnx_embedding_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class DownloadManifestBundle extends CachingAssetBundle {
  static final onnx = List<int>.filled(16, 7);
  static final tokenizer = utf8.encode('{"model":{"type":"WordPiece"}}');
  static const revision = '751bff37182d3f1213fa05d7196b954e230abad9';
  @override
  Future<ByteData> load(String key) async {
    if (key != EmbeddingModelManifest.assetPath) {
      throw StateError('Model weights must never be read from app assets');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
      'models': [
        for (final model in LocalEmbeddingModels.all)
          {
            'id': model.id,
            'repository': model.hfModelId,
            'revision': revision,
            'files': [
              for (final name in ['model_quantized.onnx', 'tokenizer.json'])
                {
                  'name': name,
                  'path': name.endsWith('.onnx') ? 'onnx/$name' : name,
                  'size': bytes(name).length,
                  'sha256': sha256.convert(bytes(name)).toString(),
                }
            ],
          }
      ],
    }))));
  }

  static List<int> bytes(String name) =>
      name.endsWith('.onnx') ? onnx : tokenizer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalEmbeddingModelStore store;
  late List<Uri> requested;
  LocalEmbeddingModelStore makeStore({http.Client? client, Duration? timeout}) {
    return LocalEmbeddingModelStore(
      rootDirectory: root,
      manifest: EmbeddingModelManifest(bundle: DownloadManifestBundle()),
      downloadTimeout: timeout ?? const Duration(seconds: 5),
      client: client ??
          MockClient((request) async {
            requested.add(request.url);
            return http.Response.bytes(
                DownloadManifestBundle.bytes(request.url.path), 200);
          }),
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-download-test-');
    requested = [];
    store = makeStore();
  });
  tearDown(() async {
    store.close();
    await root.delete(recursive: true);
  });

  test('catalog matches four ONNX models and defaults to Chinese BGE', () {
    expect(LocalEmbeddingModels.all.map((m) => m.dimensions),
        [384, 384, 512, 384]);
    expect(LocalEmbeddingModels.byId('unknown').id,
        LocalEmbeddingModels.defaultModelId);
  });
  test('manifest alone never marks a model downloaded or starts a request',
      () async {
    for (final model in LocalEmbeddingModels.all) {
      expect(await store.isDownloaded(model), isFalse);
      await expectLater(store.ensureAvailable(model), throwsStateError);
      await expectLater(
          LocalOnnxEmbeddingProvider(model: model, store: store).embed('test'),
          throwsStateError);
    }
    expect(requested, isEmpty);
  });
  for (final model in LocalEmbeddingModels.all) {
    test(
        '${model.id}: explicit download pins revision, verifies and works offline',
        () async {
      final progress = <double>[];
      await store.download(model, onProgress: progress.add);
      expect(await store.isDownloaded(model), isTrue);
      expect(requested.length, 2);
      expect(
          requested.every((uri) => uri.path
              .contains('/resolve/${DownloadManifestBundle.revision}/')),
          isTrue);
      expect(
          requested.every((uri) => uri.path.contains(model.hfModelId)), isTrue);
      expect(progress.last, 1);
      expect(progress, orderedEquals([...progress]..sort()));
      expect(
          await root
              .list(recursive: true)
              .where((f) => f.path.endsWith('.part'))
              .isEmpty,
          isTrue);
      await store.ensureAvailable(model);
      await store.download(model);
      expect(requested.length, 2,
          reason: 'Verified files are reused without network');
      for (final other
          in LocalEmbeddingModels.all.where((m) => m.id != model.id)) {
        expect(await store.isDownloaded(other), isFalse);
      }
    });
  }
  test('existing files from the bundled edition remain usable offline',
      () async {
    final model = LocalEmbeddingModels.all.first;
    await (await store.modelDirectory(model)).create(recursive: true);
    await (await store.modelFile(model))
        .writeAsBytes(DownloadManifestBundle.onnx);
    await (await store.tokenizerFile(model))
        .writeAsBytes(DownloadManifestBundle.tokenizer);
    await store.ensureAvailable(model);
    expect(requested, isEmpty);
  });
  for (final size in [0, 8, 16, 17]) {
    test(
        'rejects truncated, oversized or hash-mismatched download ($size bytes)',
        () async {
      store.close();
      store = makeStore(
          client: MockClient(
              (_) async => http.Response.bytes(List.filled(size, 9), 200)));
      final model = LocalEmbeddingModels.all.first;
      await expectLater(store.download(model), throwsFormatException);
      expect(await store.isDownloaded(model), isFalse);
      expect(await (await store.modelFile(model)).exists(), isFalse);
      expect(
          await root
              .list(recursive: true)
              .where((f) => f.path.endsWith('.part'))
              .isEmpty,
          isTrue);
    });
  }
  test(
      'tokenizer failure leaves inference unavailable; retry reuses complete ONNX',
      () async {
    store.close();
    var failTokenizer = true;
    store = makeStore(client: MockClient((request) async {
      requested.add(request.url);
      if (failTokenizer && request.url.path.endsWith('.json')) {
        return http.Response('unavailable', 503);
      }
      return http.Response.bytes(
          DownloadManifestBundle.bytes(request.url.path), 200);
    }));
    final model = LocalEmbeddingModels.all.first;
    await expectLater(store.download(model), throwsA(isA<HttpException>()));
    expect(await store.isDownloaded(model), isFalse);
    failTokenizer = false;
    await store.download(model);
    expect(await store.isDownloaded(model), isTrue);
    expect(requested.where((uri) => uri.path.endsWith('.onnx')).length, 1);
  });
  test('same-model downloads across stores do not race on partial files',
      () async {
    final other = makeStore();
    addTearDown(other.close);
    final model = LocalEmbeddingModels.all.first;
    await Future.wait(
        [store.download(model), other.download(model), store.download(model)]);
    expect(requested.length, 2);
    expect(await other.isDownloaded(model), isTrue);
  });
  test('changed cache file is revalidated and repaired', () async {
    final model = LocalEmbeddingModels.all.first;
    await store.download(model);
    final file = await store.modelFile(model);
    await file.writeAsBytes(List.filled(16, 9));
    await file.setLastModified(DateTime.now().add(const Duration(seconds: 1)));
    expect(await store.isDownloaded(model), isFalse);
    await store.download(model);
    expect(await store.isDownloaded(model), isTrue);
    expect(requested.length, 3);
  });
  test('stalled transfer times out and removes partial files', () async {
    store.close();
    final stream = StreamController<List<int>>();
    store = makeStore(
        timeout: const Duration(milliseconds: 20),
        client: MockClient.streaming(
            (_, __) async => http.StreamedResponse(stream.stream, 200)));
    await expectLater(store.download(LocalEmbeddingModels.all.first),
        throwsA(isA<TimeoutException>()));
    await stream.close();
    expect(
        await root
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .isEmpty,
        isTrue);
  });
  test('closed downloader cannot start a transfer', () async {
    store.close();
    await expectLater(
        store.download(LocalEmbeddingModels.all.first), throwsStateError);
    expect(requested, isEmpty);
  });
}
