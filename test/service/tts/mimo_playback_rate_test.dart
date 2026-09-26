import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_rate_recovery_test.dart' show NativePlayer;
import 'tts_reader_sequence_test.dart' show until;

class RatePlayer extends NativePlayer {
  final rates = <double>[];
  final playedRates = <double>[];
  int resumes = 0;

  @override
  Future<void> setPlaybackRate(double value) async => rates.add(value);
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async => resumes++;
  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    playedRates.add(rates.last);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late XiaomiMimoTtsProvider provider;
  late RatePlayer player;
  late List<Map<String, dynamic>> requests;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await Prefs().saveOnlineTtsConfig('xiaomi', {
      'key': 'test-only',
      // Isolate the static audio cache between tests.
      'stylePrompt': '自然朗读 ${DateTime.now().microsecondsSinceEpoch}',
    });
    requests = [];
    final client = MockClient((request) async {
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'finish_reason': 'stop',
                'message': {
                  'audio': {
                    'data': base64Encode([73, 68, 51, 0])
                  }
                },
              }
            ],
          }),
          200);
    });
    addTearDown(client.close);
    provider = XiaomiMimoTtsProvider.forTesting(client: client);
    player = RatePlayer();
  });

  test(
      'live rate changes preserve prefetched audio; paused changes do not resume',
      () async {
    Prefs().ttsRate = 1.2;
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => player,
      collect: (_) async => const [
        TtsSentence(text: '第一句测试'),
        TtsSentence(text: '第二句测试'),
      ],
    );
    addTearDown(tts.stop);
    await tts.init(() async => '第一句测试', () async => ++cursor < 2 ? '第二句测试' : '',
        () async => '');
    final reading = tts.speak();
    await until(() => player.playedRates.length == 1 && requests.length == 2);
    expect(player.playedRates, [1.2]);
    tts.rate = 1.8;
    await until(() => player.rates.last == 1.8);
    await tts.pause();
    final before = player.rates.length;
    tts.rate = 0.7;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(player.rates.length, before);
    expect(player.resumes, 0);
    await tts.resume();
    expect(player.rates.last, 0.7);
    expect(player.resumes, 1);
    player.completed.add(null);
    await until(() => player.playedRates.length == 2);
    expect(player.playedRates, [1.2, 0.7]);
    expect(requests.length, 2);
    for (final request in requests) {
      expect(request.toString(), isNot(contains('语速约为')));
    }
    player.completed.add(null);
    await reading;
    expect(tts.playbackError, isNull);
  });

  test('preview uses saved local speed and clamps legacy zero speed', () async {
    Prefs().ttsRate = 0;
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => player,
      collect: (_) async => [],
    );
    addTearDown(tts.stop);
    await tts.speakWithVoice('试听正文', 'mimo_default');
    expect(player.playedRates, [0.5]);
    tts.rate = 1.6;
    await tts.speakWithVoice('再次试听', 'mimo_default');
    expect(player.playedRates.last, 1.6);
    expect(requests.length, 2);
  });
}
