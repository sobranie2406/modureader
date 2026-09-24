import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/config_transfer/config_qr_bridge.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'ai-secret-sentinel': 'do-not-touch',
      'sync-sentinel': 'do-not-touch',
      'onlineTtsService': 'openai',
      'isSystemTts': false,
    });
    await Prefs().initPrefs();
  });

  Map<String, dynamic> example() {
    final data = TtsConfigTransfer.defaults();
    data['service'] = 'openai';
    data['rate'] = 1.4;
    data['pitch'] = 0.8;
    data['volume'] = 0.5;
    data['allowMixWithOtherAudio'] = true;
    for (final id in TtsConfigTransfer.services) {
      data['providers'][id]['voice'] = 'voice-$id';
    }
    data['providers']['openai']['config'] = <String, dynamic>{
      'key': 'test-only-secret',
      'url': 'https://example.test/v1/audio/speech',
      'model': 'test-model',
      'voice': 'voice-openai',
      'instructions': '温柔地朗读',
    };
    return data;
  }

  test('Modu link round-trip preserves providers, voices and playback settings',
      () async {
    final data = example();
    final token = ConfigTransferCodec.encode(kind: 'tts', data: data);
    expect(token, startsWith('modu:'));
    final decoded = ConfigTransferCodec.decode(token);
    expect(decoded.kind, 'tts');
    await TtsConfigTransfer.apply(Prefs(), decoded.data);
    expect(TtsConfigTransfer.snapshot(Prefs()), data);
    expect(Prefs().prefs.getString('ai-secret-sentinel'), 'do-not-touch');
  });

  test('QR image round-trip decodes the same TTS link', () async {
    final token = ConfigTransferCodec.encode(kind: 'tts', data: example());
    final directory = await Directory.systemTemp.createTemp('modu-tts-qr-');
    try {
      final file = File('${directory.path}/settings.png');
      final bytes = await ConfigQrBridge.generate(token);
      expect(bytes, isNotNull);
      await file.writeAsBytes(bytes!);
      expect(await ConfigQrBridge.decodeImage(file.path), token);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
      'clearing only resets TTS and does not resurrect legacy selected service',
      () async {
    await TtsConfigTransfer.apply(Prefs(), example());
    await TtsConfigTransfer.apply(Prefs(), TtsConfigTransfer.defaults());
    expect(TtsConfigTransfer.snapshot(Prefs()), TtsConfigTransfer.defaults());
    expect(Prefs().prefs.getString('ai-secret-sentinel'), 'do-not-touch');
    expect(Prefs().prefs.getString('sync-sentinel'), 'do-not-touch');
  });

  test('config voice is authoritative over an outdated separate selection', () {
    final data = example();
    data['providers']['openai']['voice'] = 'old-voice';
    expect(TtsConfigTransfer.validate(data)['providers']['openai']['voice'],
        'voice-openai');
  });

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'unknown version': (d) => d['version'] = 2,
    'unknown service': (d) => d['service'] = 'arbitrary',
    'missing provider': (d) => d['providers'].remove('edge'),
    'invalid voice': (d) => d['providers']['edge']['voice'] = 123,
    'nested config': (d) => d['providers']['openai']['config']['key'] = {},
    'invalid URL': (d) =>
        d['providers']['openai']['config']['url'] = 'file:///tmp/x',
    'invalid format': (d) =>
        d['providers']['xiaomi']['config']['format'] = 'unknown',
    'invalid volume': (d) => d['volume'] = 2,
    'invalid pitch': (d) => d['pitch'] = 0,
    'invalid rate': (d) => d['rate'] = double.nan,
    'invalid mix': (d) => d['allowMixWithOtherAudio'] = 'yes',
  };
  for (final entry in invalid.entries) {
    test('${entry.key}: rejects entire import before writing', () async {
      await TtsConfigTransfer.apply(Prefs(), example());
      final before = TtsConfigTransfer.snapshot(Prefs());
      final data = example();
      entry.value(data);
      await expectLater(
          TtsConfigTransfer.apply(Prefs(), data), throwsFormatException);
      expect(TtsConfigTransfer.snapshot(Prefs()), before);
    });
  }
}
