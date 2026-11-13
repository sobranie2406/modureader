import 'dart:async';
import 'dart:io';

import 'package:modu_reader/service/offline_model_import.dart';
import 'package:modu_reader/service/knowledge/embedding_model_manifest.dart';
import 'package:modu_reader/service/knowledge/local_embedding_models.dart';
import 'package:modu_reader/service/ocr/ocr_model_store.dart';
import 'package:modu_reader/service/ocr/ocr_models.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

import 'knowledge/local_embedding_models_test.dart' show DownloadManifestBundle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, target;
  late List<File> sources;
  final expected = {
    'det.onnx': (size: 3, sha256: sha256.convert([1, 2, 3]).toString()),
    'rec.onnx': (size: 3, sha256: sha256.convert([4, 5, 6]).toString()),
  };
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-offline-model-test-');
    target = Directory('${root.path}/installed');
    sources = [
      await File('${root.path}/upstream-det.onnx').writeAsBytes([1, 2, 3]),
      await File('${root.path}/mirror-rec.onnx').writeAsBytes([4, 5, 6]),
    ];
  });
  tearDown(() => root.delete(recursive: true));

  test('matches complete files by pinned hash, no filename dependency',
      () async {
    await importPinnedModelFiles(target, sources.reversed.toList(), expected);
    expect(await File('${target.path}/det.onnx').readAsBytes(), [1, 2, 3]);
    expect(await File('${target.path}/rec.onnx').readAsBytes(), [4, 5, 6]);
    expect(await target.list().length, 2);
    expect(await sources.first.exists(), true);
    await importPinnedModelFiles(target, sources, expected);
    expect(await target.list().length, 2);
  });

  test('bad hash, missing, duplicate and oversized files preserve old model',
      () async {
    await importPinnedModelFiles(target, sources, expected);
    for (final selection in [
      [sources.first],
      [sources.first, sources.first]
    ]) {
      await expectLater(importPinnedModelFiles(target, selection, expected),
          throwsFormatException);
    }
    for (final bytes in [
      [9, 9, 9],
      [4, 5, 6, 7]
    ]) {
      await sources.last.writeAsBytes(bytes);
      await expectLater(importPinnedModelFiles(target, sources, expected),
          throwsFormatException);
      expect(await File('${target.path}/rec.onnx').readAsBytes(), [4, 5, 6]);
      expect(await target.list().length, 2);
    }
  });

  test('unexpected destination does not partially install', () async {
    await Directory('${target.path}/rec.onnx').create(recursive: true);
    await expectLater(importPinnedModelFiles(target, sources, expected),
        throwsA(isA<FileSystemException>()));
    expect(await File('${target.path}/det.onnx').exists(), false);
  });

  test('OCR imports offline and refuses replacement while recognizing',
      () async {
    final model = OcrModelSpec('fixture', 'fixture', 'fixture', {
      for (final entry in expected.entries)
        entry.key: (entry.key, entry.value.size, entry.value.sha256),
    });
    final store = OcrModelStore(directory: target, model: model);
    addTearDown(store.close);
    await store.importFiles(sources);
    await store.verify();
    expect(await store.available(), true);
    await store.withModelFiles(() async {
      await expectLater(store.importFiles(sources), throwsStateError);
    });
  });

  test('embedding import works with no network and exclusive use lease',
      () async {
    final store = LocalEmbeddingModelStore(
        rootDirectory: target,
        manifest: EmbeddingModelManifest(bundle: DownloadManifestBundle()),
        client: MockClient((_) => throw StateError('Must not access network')));
    addTearDown(store.close);
    final model = LocalEmbeddingModels.byId(null);
    final files = [
      for (final name in ['model_quantized.onnx', 'tokenizer.json'])
        await File('${root.path}/$name')
            .writeAsBytes(DownloadManifestBundle.bytes(name))
    ];
    var released = 0;
    Future<void> release() async {
      released++;
    }

    final endUse = await store.acquireUse(model);
    await expectLater(store.importFiles(model, files, releaseModel: release),
        throwsStateError);
    endUse();
    final barrier = Completer<void>();
    final entered = Completer<void>();
    final importing = store.importFiles(model, files, releaseModel: () async {
      entered.complete();
      await barrier.future;
      await release();
    });
    await entered.future;
    await expectLater(store.acquireUse(model), throwsStateError);
    await expectLater(store.download(model), throwsStateError);
    barrier.complete();
    await importing;
    expect(released, 1);
    expect(await store.isDownloaded(model), true);
  });
}
