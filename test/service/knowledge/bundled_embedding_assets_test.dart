import 'dart:io';

import 'package:anx_reader/service/knowledge/bundled_embedding_assets.dart';
import 'package:anx_reader/service/knowledge/embedding_model_manifest.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'local_embedding_models_test.dart' show DownloadManifestBundle;

class OfflineBundle extends DownloadManifestBundle {
  final reads = <String>[];
  bool corrupt = false;
  bool catalogOnly = false;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        if (!catalogOnly)
          for (final model in LocalEmbeddingModels.all)
            for (final name in ['model_quantized.onnx', 'tokenizer.json'])
              'assets/models/embeddings/${model.id}/$name': [
                {'asset': 'assets/models/embeddings/${model.id}/$name'}
              ],
      })!;
    }
    if (key == EmbeddingModelManifest.assetPath) return super.load(key);
    reads.add(key);
    final bytes = DownloadManifestBundle.bytes(key);
    return ByteData.sublistView(
        Uint8List.fromList(corrupt ? List.filled(bytes.length, 9) : bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late OfflineBundle bundle;
  late LocalEmbeddingModelStore store;
  late int networkCalls;

  LocalEmbeddingModelStore makeStore() => LocalEmbeddingModelStore(
        rootDirectory: root,
        bundledAssets: BundledEmbeddingAssets(bundle: bundle),
        manifest: EmbeddingModelManifest(bundle: bundle),
        client: MockClient((_) async {
          networkCalls++;
          throw StateError('Offline mode must not contact the network');
        }),
      );

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-bundled-test-');
    bundle = OfflineBundle();
    networkCalls = 0;
    store = makeStore();
  });
  tearDown(() async {
    store.close();
    await root.delete(recursive: true);
  });

  test('all four bundled models prepare, verify and reuse without network',
      () async {
    for (final model in LocalEmbeddingModels.all) {
      expect(await store.isBundled(model), isTrue);
      expect(await store.isDownloaded(model), isFalse);
      await store.ensureAvailable(model);
      expect(await store.isDownloaded(model), isTrue);
      await store.ensureAvailable(model);
      await store.download(model);
    }
    expect(bundle.reads.length, 8);
    expect(networkCalls, 0);
  });

  test('a catalogue without weights is not advertised as bundled', () async {
    bundle.catalogOnly = true;
    final model = LocalEmbeddingModels.all.first;
    expect(await store.isBundled(model), isFalse);
    await expectLater(store.ensureAvailable(model), throwsStateError);
    expect(networkCalls, 0);
  });

  test('corrupt assets fail integrity checks and clean temporary files',
      () async {
    bundle.corrupt = true;
    final model = LocalEmbeddingModels.all.first;
    await expectLater(store.ensureAvailable(model), throwsFormatException);
    expect(await store.isDownloaded(model), isFalse);
    expect(
        await root
            .list(recursive: true)
            .where((f) => f.path.endsWith('.part'))
            .isEmpty,
        isTrue);
    expect(networkCalls, 0);
  });

  test('changed local files are repaired from bundled assets offline',
      () async {
    final model = LocalEmbeddingModels.all.first;
    await store.ensureAvailable(model);
    final file = await store.modelFile(model);
    await file.writeAsBytes(List.filled(16, 0));
    await file.setLastModified(DateTime.now().add(const Duration(seconds: 1)));
    await store.ensureAvailable(model);
    expect(await store.isDownloaded(model), isTrue);
    expect(bundle.reads.length, 3);
    expect(networkCalls, 0);
  });

  test('concurrent preparations share one verified copy operation', () async {
    final other = makeStore();
    addTearDown(other.close);
    final model = LocalEmbeddingModels.all.first;
    await Future.wait(
        [store.ensureAvailable(model), other.ensureAvailable(model)]);
    expect(bundle.reads.length, 2);
    expect(await other.isDownloaded(model), isTrue);
    expect(networkCalls, 0);
  });
}
