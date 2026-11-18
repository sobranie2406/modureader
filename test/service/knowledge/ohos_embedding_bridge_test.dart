import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/knowledge/ohos_embedding_bridge.dart';
import 'package:modu_reader/service/knowledge/onnx_embedding_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = OhosEmbeddingBridge();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  void handle(Object? Function(MethodCall) respond) {
    messenger.setMockMethodCallHandler(OhosEmbeddingBridge.channel,
        (call) async {
      calls.add(call);
      return respond(call);
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(OhosEmbeddingBridge.channel, null);
    calls.clear();
  });

  test('HarmonyOS support requires an available native runtime', () async {
    expect(await bridge.isAvailable(), isFalse);
    expect(LocalOnnxEmbeddingProvider.supportsPlatform('ohos'), isFalse);
    handle((call) => false);
    expect(await bridge.isAvailable(), isFalse);
    handle((call) => call.method == 'isAvailable');
    expect(
        LocalOnnxEmbeddingProvider.supportsPlatform('ohos',
            ohosAvailable: await bridge.isAvailable()),
        isTrue);
    expect(LocalOnnxEmbeddingProvider.supportsPlatform('android'), isTrue);
  });

  test('HarmonyOS transfers the model path, tokens and normalized vector',
      () async {
    handle((call) =>
        call.method == 'embed' ? (Float64List(512)..[0] = 1.0) : null);
    await bridge.load('/fixtures/model.onnx');
    final vector = await bridge.embed([101, 42, 102], 512);
    await bridge.close();

    expect(calls.map((call) => call.method), ['load', 'embed', 'close']);
    expect(calls.first.arguments, {'modelPath': '/fixtures/model.onnx'});
    final arguments = calls[1].arguments as Map;
    expect(arguments['ids'], isA<Int64List>());
    expect(arguments['ids'], [101, 42, 102]);
    expect(arguments['dimensions'], 512);
    expect(vector, hasLength(512));
    expect(vector.first, 1.0);
  });

  test('HarmonyOS rejects malformed native embedding results', () async {
    for (final value in [
      null,
      [0],
      [0, double.nan],
      [0, '1']
    ]) {
      handle((call) => value);
      await expectLater(bridge.embed([101, 102], 2), throwsFormatException);
    }
  });
}
