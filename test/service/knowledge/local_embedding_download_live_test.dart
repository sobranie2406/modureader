import 'dart:io';

import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:flutter_test/flutter_test.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('downloads pinned Chinese BGE and tokenizer from the real source',
      () async {
    // Flutter's unit-test binding otherwise replaces every HTTP response by 400.
    await HttpOverrides.runWithHttpOverrides(() async {
      final root = await Directory.systemTemp.createTemp('modu-live-download-');
      final store = LocalEmbeddingModelStore(rootDirectory: root);
      try {
        final model =
            LocalEmbeddingModels.byId(LocalEmbeddingModels.defaultModelId);
        expect(await store.isDownloaded(model), isFalse);
        var lastMilestone = -1;
        await store.download(model, onProgress: (progress) {
          final milestone = (progress * 5).floor();
          if (milestone != lastMilestone) {
            lastMilestone = milestone;
            // Public model progress only; no book content, credentials or paths.
            // ignore: avoid_print
            print('BGE download/verification: ${(progress * 100).round()}%');
          }
        });
        expect(await store.isDownloaded(model), isTrue);
        await store.ensureAvailable(model);
      } finally {
        store.close();
        await root.delete(recursive: true);
      }
    }, _RealHttpOverrides());
  },
      skip: Platform.environment['MODU_TEST_MODEL_DOWNLOAD'] != '1',
      timeout: const Timeout(Duration(minutes: 10)));
}
