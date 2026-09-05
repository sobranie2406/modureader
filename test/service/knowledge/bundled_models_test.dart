import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/knowledge/bundled_embedding_assets.dart';
import 'package:anx_reader/service/knowledge/bundled_model_defaults.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelBundle extends CachingAssetBundle {
  final Map<String, int> reads = {};
  bool corrupt = false;
  static const payload = [1, 2, 3, 4];

  @override
  Future<ByteData> load(String key) async {
    reads.update(key, (value) => value + 1, ifAbsent: () => 1);
    if (key.endsWith('manifest.json')) {
      return ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode({
        'models': [
          {
            'id': 'test',
            'files': [
              for (final name in ['model_quantized.onnx', 'tokenizer.json'])
                {
                  'name': name,
                  'size': payload.length,
                  'sha256': sha256.convert(payload).toString(),
                }
            ],
          }
        ],
      }))));
    }
    return ByteData.sublistView(
        Uint8List.fromList(corrupt ? [9, 9, 9, 9] : payload));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled files prepare offline, deduplicate, reuse and repair cache',
      () async {
    final root = await Directory.systemTemp.createTemp('modu-bundle-test-');
    addTearDown(() => root.delete(recursive: true));
    final bundle = ModelBundle();
    final assets = BundledEmbeddingAssets(bundle: bundle);
    expect(await assets.contains('test'), isTrue);
    expect(await assets.contains('missing'), isFalse);
    await Future.wait(
        [assets.materialize('test', root), assets.materialize('test', root)]);
    final model = File('${root.path}/model_quantized.onnx');
    expect(await model.readAsBytes(), ModelBundle.payload);
    await assets.materialize('test', root);
    final key = '${BundledEmbeddingAssets.assetRoot}/test/model_quantized.onnx';
    expect(bundle.reads[key], 1);
    await model.writeAsBytes([0, 0, 0, 0]);
    await assets.materialize('test', root);
    expect(await model.readAsBytes(), ModelBundle.payload);
    expect(bundle.reads[key], 2);
  });

  test('corrupt bundled assets and absent models fail explicitly', () async {
    final root = await Directory.systemTemp.createTemp('modu-bundle-test-');
    addTearDown(() => root.delete(recursive: true));
    final assets =
        BundledEmbeddingAssets(bundle: ModelBundle()..corrupt = true);
    await expectLater(assets.materialize('test', root), throwsStateError);
    await expectLater(assets.materialize('missing', root), throwsStateError);
    expect(await root.list().isEmpty, isTrue);
  });

  test('fresh install defaults to local Chinese BGE without auto indexing',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorModelMode'), 'builtin');
    expect(prefs.getString('vectorLocalModelId'), 'bge-small-zh-v1.5');
    expect(prefs.getBool('autoVectorizeOnImport'), isFalse);
  });

  test('upgrade disables auto/remote once, preserves keys and later choices',
      () async {
    SharedPreferences.setMockInitialValues({
      'vectorModelMode': 'remote',
      'autoVectorizeOnImport': true,
      'vectorModelConfig': '{"apiKey":"test-not-a-real-key"}',
      'vectorModelEnabled': false,
    });
    final prefs = await SharedPreferences.getInstance();
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorModelMode'), 'builtin');
    expect(prefs.getBool('autoVectorizeOnImport'), isFalse);
    expect(prefs.getBool('vectorModelEnabled'), isFalse);
    expect(prefs.getString('vectorModelConfig'),
        '{"apiKey":"test-not-a-real-key"}');
    await prefs.setString('vectorModelMode', 'remote');
    await prefs.setBool('autoVectorizeOnImport', true);
    await applyBundledModelDefaults(prefs);
    expect(prefs.getString('vectorModelMode'), 'remote');
    expect(prefs.getBool('autoVectorizeOnImport'), isTrue);
  });
}
