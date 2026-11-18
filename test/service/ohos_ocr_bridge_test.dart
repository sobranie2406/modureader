import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:modu_reader/service/ocr/local_ocr_service.dart';
import 'package:modu_reader/service/ocr/ocr_model_store.dart';
import 'package:modu_reader/service/ocr/ohos_ocr_bridge.dart';

class _FixtureStore extends OcrModelStore {
  _FixtureStore(Directory directory) : super(directory: directory);

  @override
  Future<void> verify() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final png = img.encodePng(img.Image(width: 32, height: 32));
  late Directory directory;
  late _FixtureStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-ohos-ocr-');
    store = _FixtureStore(directory);
    await File('${directory.path}/rec.yml')
        .writeAsString('PostProcess:\n  name: CTCLabelDecode\n'
            '  character_dict: [A, B, C, D, E, F, G, H, I, J]');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(OhosOcrBridge.channel, null);
    store.close();
    await directory.delete(recursive: true);
  });

  test('HarmonyOS uses the root bridge for both models and returns regions',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(OhosOcrBridge.channel, (call) async {
      calls.add(call.method);
      final args = call.arguments;
      if (call.method == 'load') {
        expect(args['path'], directory.path);
      } else if (call.method == 'run') {
        expect(args['data'], isA<Float32List>());
        final shape = args['shape'] as List;
        expect(args['data'].length,
            shape.fold<int>(1, (area, size) => area * (size as int)));
        if (args['name'] == 'det') {
          expect(shape, [1, 3, 32, 32]);
          final map = Float32List(32 * 32);
          for (var y = 8; y < 12; y++) {
            for (var x = 4; x < 14; x++) {
              map[y * 32 + x] = .9;
            }
          }
          return {
            'data': map,
            'shape': [1, 1, 32, 32]
          };
        }
        expect(args['name'], 'rec');
        expect(shape, [1, 3, 48, 320]);
        return {
          'data': (Float32List(12)..[1] = .9),
          'shape': [1, 1, 12]
        };
      }
      return null;
    });

    final result = await LocalOcrService(ohosBridge: const OhosOcrBridge())
        .recognizeWithRegions(png, store, OcrCancellation());
    expect(result.text, 'A');
    expect(result.regions, hasLength(1));
    expect(calls, ['load', 'run', 'run', 'close']);
  });

  test('HarmonyOS cancellation waits for native cleanup and skips recognition',
      () async {
    final detector = Completer<Map<String, Object?>>();
    final started = Completer<void>();
    final closing = Completer<void>();
    final finish = Completer<void>();
    final cancel = OcrCancellation();
    messenger.setMockMethodCallHandler(OhosOcrBridge.channel, (call) async {
      if (call.method == 'run') {
        expect(call.arguments['name'], 'det');
        started.complete();
        return detector.future;
      } else if (call.method == 'close') {
        closing.complete();
        await finish.future;
      }
      return null;
    });
    final service = LocalOcrService(ohosBridge: const OhosOcrBridge());
    final result = service.recognizeWithRegions(png, store, cancel);
    final cancelled = expectLater(result, throwsStateError);
    await started.future;
    cancel.cancel();
    detector.complete({
      'data': Float32List(1024),
      'shape': [1, 1, 32, 32]
    });
    await closing.future;
    await expectLater(store.deleteDownloaded(), throwsStateError);
    await expectLater(
        service.recognizeWithRegions(png, store, OcrCancellation()),
        throwsStateError);
    finish.complete();
    await cancelled;
  });

  test('HarmonyOS native timeout returns an error and releases the worker',
      () async {
    final calls = <String>[];
    final stalled = Completer<Object?>();
    messenger.setMockMethodCallHandler(OhosOcrBridge.channel, (call) async {
      calls.add(call.method);
      if (call.method == 'load') return stalled.future;
      return null;
    });
    final service = LocalOcrService(
        ohosBridge: const OhosOcrBridge(timeout: Duration(milliseconds: 30)));
    await expectLater(
        service.recognizeWithRegions(png, store, OcrCancellation()),
        throwsA(isA<TimeoutException>()));
    stalled.complete();
    expect(calls, ['load', 'close']);
    await store.deleteDownloaded();
  });

  test('HarmonyOS without a registered runtime fails before starting OCR',
      () async {
    final service = LocalOcrService(ohosBridge: const OhosOcrBridge());
    await expectLater(
        service.recognizeWithRegions(png, store, OcrCancellation()),
        throwsA(isA<MissingPluginException>()));
    await store.deleteDownloaded();
  });
}
