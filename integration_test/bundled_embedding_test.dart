import 'dart:io';
import 'dart:math' as math;

import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:anx_reader/service/knowledge/onnx_embedding_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('all four bundled models perform real native inference offline',
      (tester) async {
    final root =
        await Directory.systemTemp.createTemp('modu-offline-inference-');
    var networkRequests = 0;
    final store = LocalEmbeddingModelStore(
      rootDirectory: root,
      client: MockClient((request) async {
        networkRequests++;
        throw StateError('Model download is forbidden in this offline test');
      }),
    );
    try {
      for (final model in LocalEmbeddingModels.all) {
        expect(await store.isBundled(model), isTrue);
        final vectors =
            await LocalOnnxEmbeddingProvider(model: model, store: store)
                .embedBatch(
                    ['默读让阅读更专注。', 'Reading helps us understand the world.']);
        expect(vectors.length, 2);
        for (final vector in vectors) {
          expect(vector.length, model.dimensions);
          expect(vector.every((value) => value.isFinite), isTrue);
          final norm = math.sqrt(
              vector.fold<double>(0, (sum, value) => sum + value * value));
          expect(norm, closeTo(1, 0.0001));
        }
        // This log contains only public model metadata, never user books or keys.
        debugPrint(
            'OFFLINE ONNX PASS: ${model.id}, ${model.dimensions} dimensions');
      }
      expect(networkRequests, 0);
    } finally {
      store.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
