import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/edge_tts_backend.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/openai_tts_backend.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
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

class RecordedDashScope extends RecordedProvider
    implements DashScopeTtsProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final speed in [0.1, 0.2, 0.3, 0.8, 2.1, 3.0, 3.9, 4.0]) {
    for (final name in ['Edge', 'OpenAI', 'DashScope']) {
      test('$name preview reaches ${speed}x', () async {
        final provider = switch (name) {
          'Edge' => RecordedEdge(),
          'OpenAI' => RecordedOpenAi(),
          _ => RecordedDashScope(),
        };
        final player = RatePlayer();
        final tts = OnlineTts.forTesting(
          backend: provider,
          createPlayer: () => player,
          collect: (_) async => [],
        );
        addTearDown(tts.stop);
        tts.rate = speed;
        await tts.speakWithVoice('倍速回归测试', 'test-voice');
        final synthesis = name == 'Edge'
            ? speed.clamp(0.1, 2.0)
            : name == 'OpenAI'
                ? 1.0
                : speed.clamp(0.25, 4.0);
        expect(provider.requestedRates, [synthesis]);
        expect(player.playedRates.single, closeTo(speed / synthesis, 0.000001));
        expect(synthesis * player.playedRates.single, closeTo(speed, 0.000001));
        expect(Prefs().ttsRate, speed);
      });
    }
  }

  test('low-speed live adjustment reuses synthesis and keeps pause state',
      () async {
    final provider = RecordedOpenAi();
    final player = RatePlayer();
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => player,
      collect: (_) async => const [TtsSentence(text: '低速调节')],
    );
    addTearDown(tts.stop);
    tts.rate = 0.1;
    await tts.init(() async => '低速调节', () async => '', () async => '');
    final reading = tts.speak();
    await until(() => player.playedRates.isNotEmpty);
    tts.rate = 0.2;
    await until(() => player.rates.last == 0.2);
    expect(provider.requestedRates, [1.0]);
    await tts.pause();
    tts.rate = 0.1;
    await Future<void>.delayed(Duration.zero);
    expect(player.rates.last, 0.2);
    expect(player.resumes, 0);
    await tts.resume();
    expect(player.rates.last, 0.1);
    player.completed.add(null);
    await reading;
    tts.rate = 0.3;
    await tts.speakWithVoice('恢复合成速度', 'test-voice');
    expect(provider.requestedRates, [1.0, 1.0]);
    expect(player.playedRates.last, 0.3);
  });

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
