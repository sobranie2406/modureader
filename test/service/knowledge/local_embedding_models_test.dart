import 'dart:io';

import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('catalog matches ReadAny four local ONNX models', () {
    expect(
      LocalEmbeddingModels.all.map((model) => model.id),
      [
        'all-MiniLM-L6-v2',
        'bge-small-en-v1.5',
        'bge-small-zh-v1.5',
        'multilingual-e5-small',
      ],
    );
    expect(
      LocalEmbeddingModels.all.map((model) => model.dimensions),
      [384, 384, 512, 384],
    );
    expect(LocalEmbeddingModels.all.singleWhere((m) => m.recommended).id,
        LocalEmbeddingModels.defaultModelId);
  });

  test('unknown model preference falls back to recommended model', () {
    expect(
      LocalEmbeddingModels.byId('not-a-model').id,
      LocalEmbeddingModels.defaultModelId,
    );
  });

  test('downloads ONNX model and tokenizer using atomic files', () async {
    final root = await Directory.systemTemp.createTemp('modu-model-store-');
    final requested = <Uri>[];
    final store = LocalEmbeddingModelStore(
      rootDirectory: root,
      minimumModelBytes: 1,
      minimumTokenizerBytes: 1,
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path.endsWith('tokenizer.json')) {
          return http.Response('{"model":{"type":"WordPiece"}}', 200);
        }
        return http.Response.bytes(List<int>.filled(16, 7), 200);
      }),
    );
    addTearDown(() async {
      store.close();
      await root.delete(recursive: true);
    });

    final progress = <double>[];
    final model = LocalEmbeddingModels.all.first;
    await store.download(model, onProgress: progress.add);

    expect(await store.isDownloaded(model), isTrue);
    expect(requested, [model.modelUri, model.tokenizerUri]);
    expect(progress.last, 1);
    expect(
      await File('${(await store.modelFile(model)).path}.part').exists(),
      isFalse,
    );
    expect(
      await File('${(await store.tokenizerFile(model)).path}.part').exists(),
      isFalse,
    );
  });

  test('rejects an invalid tokenizer file', () async {
    final root = await Directory.systemTemp.createTemp('modu-model-store-');
    final store = LocalEmbeddingModelStore(
      rootDirectory: root,
      minimumModelBytes: 1,
      minimumTokenizerBytes: 1,
    );
    addTearDown(() async {
      store.close();
      await root.delete(recursive: true);
    });
    final model = LocalEmbeddingModels.all.first;
    final directory = await store.modelDirectory(model);
    await directory.create(recursive: true);
    await (await store.modelFile(model)).writeAsBytes([1, 2, 3]);
    await (await store.tokenizerFile(model)).writeAsString('not json');

    expect(await store.isDownloaded(model), isFalse);
  });
}
