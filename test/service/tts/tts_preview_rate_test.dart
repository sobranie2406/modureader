import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/edge_tts_backend.dart';
import 'package:anx_reader/service/tts/openai_tts_backend.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  OnlineTts ttsFor(dynamic backend) => OnlineTts.forTesting(
        collect: (_) async => const [],
        synthesize: (_) async => Uint8List.fromList([1]),
        backend: backend,
      );

  /// A preview asks for rate 1.0; every engine must then synthesize and play at
  /// its neutral speed, whatever the reader slider says.
  test('a preview at 1.0x is neutral for every engine', () {
    for (final backend in [
      XiaomiMimoTtsProvider(),
      EdgeTtsProvider(),
      OpenAiTtsProvider(),
      DashScopeTtsProvider(),
    ]) {
      final tts = ttsFor(backend);
      expect(tts.previewSynthesisRateFor(1.0), 1.0,
          reason: '${backend.runtimeType} synthesis');
      expect(tts.previewPlaybackRateFor(1.0), 1.0,
          reason: '${backend.runtimeType} playback');
    }
  });

  test('the reader speed only scales the playback rate for MiMo', () {
    final tts = ttsFor(XiaomiMimoTtsProvider());
    expect(tts.previewSynthesisRateFor(2.5), 1.0);
    expect(tts.previewPlaybackRateFor(2.5), 2.5);
  });

  test('Edge keeps a bounded synthesis range and accelerates locally', () {
    final tts = ttsFor(EdgeTtsProvider());
    expect(tts.previewSynthesisRateFor(2.5), 2.0);
    expect(tts.previewPlaybackRateFor(2.5), 1.25);
    expect(tts.previewPlaybackRateFor(3.5), 1.75);
  });
}
