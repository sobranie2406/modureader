import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/edge_tts_backend.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/openai_tts_backend.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mimo_playback_rate_test.dart' show RatePlayer;
import 'tts_reader_sequence_test.dart' show until;

class RecordedProvider extends TtsServiceProvider {
  final requestedRates = <double>[];
  @override
  TtsService get service => TtsService.openai;
  @override
  String getLabel(BuildContext context) => 'Test';
  @override
  String getSelectedVoice() => 'test-voice';
  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    requestedRates.add(rate);
    return Uint8List.fromList([73, 68, 51, 0]);
  }
}

class RecordedEdge extends RecordedProvider implements EdgeTtsProvider {
  @override
  TtsService get service => TtsService.edge;
}

class RecordedOpenAi extends RecordedProvider implements OpenAiTtsProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final speed in [3.0, 4.0]) {
    for (final edge in [false, true]) {
      test('${edge ? 'Edge' : 'OpenAI'} preview reaches ${speed}x', () async {
        final provider = edge ? RecordedEdge() : RecordedOpenAi();
        final player = RatePlayer()..rates.add(1); // Native default speed.
        final tts = OnlineTts.forTesting(
          backend: provider,
          createPlayer: () => player,
          collect: (_) async => [],
        );
        addTearDown(tts.stop);
        tts.rate = speed;
        await tts.speakWithVoice('高倍速回归测试', 'test-voice');
        final requests = provider.requestedRates;
        expect(requests, [edge ? 2 : speed]);
        expect(player.playedRates, [edge ? speed / 2 : 1]);
        expect(requests.single * player.playedRates.single, speed);
        expect(Prefs().ttsRate, speed);
      });
    }
  }

  test('Edge live 3x to 4x preserves audio and lower speed resets acceleration',
      () async {
    final provider = RecordedEdge();
    final player = RatePlayer();
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => player,
      collect: (_) async => const [TtsSentence(text: '播放中调节速度')],
    );
    addTearDown(tts.stop);
    tts.rate = 3;
    await tts.init(() async => '播放中调节速度', () async => '', () async => '');
    final reading = tts.speak();
    await until(() => player.playedRates.isNotEmpty);
    tts.rate = 4;
    await until(() => player.rates.last == 2);
    expect(provider.requestedRates, [2]);
    player.completed.add(null);
    await reading;
    tts.rate = 1;
    await tts.speakWithVoice('恢复普通速度', 'test-voice');
    expect(provider.requestedRates, [2, 1]);
    expect(player.playedRates, [1.5, 1]);
  });
}
