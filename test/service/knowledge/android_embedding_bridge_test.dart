import 'dart:typed_data';
import 'package:anx_reader/service/knowledge/android_embedding_bridge.dart';
import 'package:anx_reader/service/knowledge/onnx_embedding_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = AndroidEmbeddingBridge();
  final calls = <MethodCall>[];
  Object? response;
  PlatformException? error;
  setUp(() {
    calls.clear();
    response = null;
    error = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidEmbeddingBridge.channel, (call) async {
      calls.add(call);
      if (error != null) throw error!;
      return response;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidEmbeddingBridge.channel, null);
  });

  for (final dimension in [384, 512]) {
    test('Android transfers only the final $dimension-dimensional vector',
        () async {
      response = Float64List(dimension)..[0] = 1;
      final vector = await bridge.embed([101, 123, 102], dimension);
      expect(vector.length, dimension);
      expect(vector.first, 1);
      expect(calls.single.method, 'embed');
      expect(calls.single.arguments['ids'], isA<Int64List>());
      expect(calls.single.arguments['ids'], [101, 123, 102]);
      expect(calls.single.arguments['dimensions'], dimension);
    });
  }
  test('native memory errors reach indexing instead of becoming success',
      () async {
    error = PlatformException(code: 'LOCAL_EMBEDDING_MEMORY');
    await expectLater(
        bridge.embed([101, 102], 512), throwsA(isA<PlatformException>()));
  });
  test('rejects missing, wrong-dimensional and nonfinite outputs', () async {
    for (final bad in [
      null,
      [1.0],
      List<double>.filled(512, double.nan)
    ]) {
      response = bad;
      await expectLater(bridge.embed([101, 102], 512), throwsFormatException);
    }
  });
  test('load and close use the dedicated native session lifecycle', () async {
    await bridge.load('/fixture/model.onnx');
    await bridge.close();
    expect(calls.map((c) => c.method), ['load', 'close']);
  });
  test('actual tensor length is bounded after retokenizing a prefix', () {
    final small = [101, 42, 102];
    expect(boundEmbeddingTokens(small), same(small));
    final long = [101, ...List<int>.filled(800, 42), 102];
    final result = boundEmbeddingTokens(long);
    expect(result.length, 512);
    expect(result.first, 101);
    expect(result.last, 102);
  });
}
