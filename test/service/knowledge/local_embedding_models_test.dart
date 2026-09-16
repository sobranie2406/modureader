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

// Small chunks exercise the same streaming assembly path without allocating
// the real E5 model in a unit test. Real 64 MiB boundaries are checked below.
String fixtureHash(List<int> data) => sha256.convert(data).toString();

class SplitFixtureFile extends EmbeddingModelFile {
  SplitFixtureFile(String name, List<int> data)
      : super(
            name: name,
            size: data.length,
            sha256: fixtureHash(data),
            uri: Uri.parse('https://huggingface.co/Xenova/test/$name'));

  @override
  List<({Uri uri, int size})> downloads(EmbeddingDownloadSource source) => [
        (uri: Uri.parse('$embeddingMirrorBase/$name.part-01'), size: 8),
        (uri: Uri.parse('$embeddingMirrorBase/$name.part-02'), size: size - 8),
      ];
}

class SplitFixtureManifest extends EmbeddingModelManifest {
  static final bytes = List<int>.generate(16, (i) => i);
  @override
  Future<List<EmbeddingModelFile>> files(String id) async => [
        SplitFixtureFile('model_quantized.onnx', bytes),
        SplitFixtureFile('tokenizer.json', bytes),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalEmbeddingModelStore store;
  late List<Uri> requested;
  LocalEmbeddingModelStore makeStore(
      {http.Client? client,
      Duration? timeout,
      EmbeddingModelManifest? manifest}) {
    return LocalEmbeddingModelStore(
      rootDirectory: root,
      useBundledAssets: false,
      manifest:
          manifest ?? EmbeddingModelManifest(bundle: DownloadManifestBundle()),
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
  test('Gitee selection downloads pinned files and reuses them offline',
      () async {
    store.downloadSource = EmbeddingDownloadSource.gitee;
    final model = LocalEmbeddingModels.all.first;
    await store.download(model);
    expect(await store.isDownloaded(model), isTrue);
    expect(requested.length, 2);
    expect(
        requested.every((uri) => uri.toString().startsWith(
            '$embeddingMirrorBase/${model.id}-${DownloadManifestBundle.revision}-')),
        isTrue);
    store.downloadSource = EmbeddingDownloadSource.huggingFace;
    await store.ensureAvailable(model);
    await store.download(model);
    expect(requested.length, 2);
  });
  test('Gitee failure never silently contacts Hugging Face', () async {
    store.close();
    store = makeStore(client: MockClient((request) async {
      requested.add(request.url);
      return http.Response('unavailable', 404);
    }))
      ..downloadSource = EmbeddingDownloadSource.gitee;
    await expectLater(store.download(LocalEmbeddingModels.all.first),
        throwsA(isA<HttpException>()));
    expect(requested.single.host, 'gitee.com');
    expect(
        await root
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .isEmpty,
        isTrue);
  });
  test('accepts observed Gitee attachment CDN with pinned integrity', () async {
    store.close();
    store = makeStore(client: MockClient((request) async {
      requested.add(request.url);
      if (request.url.host == 'gitee.com') {
        return http.Response('', 302, headers: {
          'location':
              'https://foruda.gitee.com/attach_file/123/${request.url.pathSegments.last}'
        });
      }
      return http.Response.bytes(
          DownloadManifestBundle.bytes(request.url.path), 200);
    }))
      ..downloadSource = EmbeddingDownloadSource.gitee;
    await store.download(LocalEmbeddingModels.all.first);
    expect(requested.length, 4);
    expect(await store.isDownloaded(LocalEmbeddingModels.all.first), isTrue);
  });
  for (final target in [
    'http://gitee.com/sobranie2406/modu-models/file',
    'https://example.com/file',
    'https://foruda.gitee.com/unrelated/file',
    'https://foruda.gitee.com.evil.example/attach_file/file',
    'https://gitee.com/another/repo/file',
    'https://gitee.com:8443/sobranie2406/modu-models/file'
  ]) {
    test('rejects unsafe mirror redirect $target', () async {
      store.close();
      store = makeStore(client: MockClient((request) async {
        requested.add(request.url);
        expect(request.followRedirects, isFalse);
        return http.Response('', 302, headers: {'location': target});
      }))
        ..downloadSource = EmbeddingDownloadSource.gitee;
      await expectLater(store.download(LocalEmbeddingModels.all.first),
          throwsFormatException);
      expect(requested.length, 1);
    });
  }
  test('E5 mirror uses ordered parts with original complete integrity metadata',
      () async {
    final file = (await EmbeddingModelManifest().files('multilingual-e5-small'))
        .firstWhere((file) => file.name.endsWith('.onnx'));
    final parts = file.downloads(EmbeddingDownloadSource.gitee);
    expect(parts.length, 2);
    expect(parts.first.size, embeddingMirrorPartSize);
    expect(parts.last.size, file.size - embeddingMirrorPartSize);
    expect(parts.first.uri.path, endsWith('.part-01'));
    expect(parts.last.uri.path, endsWith('.part-02'));
    expect(file.downloads(EmbeddingDownloadSource.huggingFace).single.size,
        file.size);
    expect(file.sha256,
        'f80102d3f2a1229f387d3c81909990d8945513e347b0eab049f7de3c6f98c193');
  });
  for (final fault in [
    'none',
    'truncated',
    'reversed',
    'second part unavailable'
  ]) {
    test('multipart streaming and whole-file integrity: $fault', () async {
      store.close();
      store = makeStore(
          manifest: SplitFixtureManifest(),
          client: MockClient((request) async {
            requested.add(request.url);
            final first = request.url.path.endsWith('01');
            if (!first && fault == 'second part unavailable') {
              return http.Response('not found', 404);
            }
            final index = (fault == 'reversed' ? !first : first) ? 0 : 8;
            var bytes = SplitFixtureManifest.bytes.sublist(index, index + 8);
            if (fault == 'truncated') bytes = bytes.sublist(1);
            return http.Response.bytes(bytes, 200);
          }))
        ..downloadSource = EmbeddingDownloadSource.gitee;
      final model = LocalEmbeddingModels.all.first;
      if (fault == 'none') {
        await store.download(model);
        expect(await (await store.modelFile(model)).readAsBytes(),
            SplitFixtureManifest.bytes);
        expect(await store.isDownloaded(model), isTrue);
        expect(requested.length, 4);
      } else {
        await expectLater(
            store.download(model),
            fault == 'second part unavailable'
                ? throwsA(isA<HttpException>())
                : throwsFormatException);
        expect(await store.isDownloaded(model), isFalse);
        expect(await (await store.modelFile(model)).exists(), isFalse);
      }
      expect(
          await root
              .list(recursive: true)
              .where((f) => f.path.endsWith('.part'))
              .isEmpty,
          isTrue);
    });
  }
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
