import 'dart:io';

import 'package:anx_reader/service/knowledge/embedding_model_manifest.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit opt-in only: downloads about 218 MB of public model files to a
// temporary directory, verifies them through the production downloader, then
// removes that directory. Ordinary test runs never contact a model server.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('public Gitee mirror: all four models verify without authentication',
      () async {
    final originalOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final root = await Directory.systemTemp.createTemp('modu-mirror-live-');
    final store = LocalEmbeddingModelStore(
      rootDirectory: root,
      downloadSource: EmbeddingDownloadSource.gitee,
    );
    try {
      for (final model in LocalEmbeddingModels.all) {
        await store.download(model);
        expect(await store.isDownloaded(model), isTrue);
        expect(await (await store.modelFile(model)).exists(), isTrue);
        // SHA/size checks happen in the production download and availability
        // paths, including the assembled E5 parts.
        // ignore: avoid_print
        print('Verified Gitee model: ${model.id}');
      }
    } finally {
      store.close();
      await root.delete(recursive: true);
      HttpOverrides.global = originalOverrides;
    }
  },
      skip: !const bool.fromEnvironment('MODU_VERIFY_MODEL_MIRROR'),
      timeout: const Timeout(Duration(minutes: 15)));
}
