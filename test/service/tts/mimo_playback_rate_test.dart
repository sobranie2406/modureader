import 'package:modu_reader/service/tts/openai_tts_backend.dart';
import 'dart:convert';
import 'package:flutter/services.dart';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/tts/models/tts_sentence.dart';
import 'package:modu_reader/service/tts/online_tts.dart';
import 'package:modu_reader/service/tts/readany_compatible_tts_backend.dart';
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

class NativePitchPlayer extends RatePlayer {
  @override
  String get playerId => 'mimo-pitch-test';
}

/// Windows' MediaEngine resets playback rate when the source changes. Every
/// TTS sentence calls play() with a new source, so a rate set before play()
/// would silently fall back to 1.0 on the next sentence.
class SourceResettingPlayer extends NativePlayer {
  double currentRate = 1.0;

  @override
  Future<void> setPlaybackRate(double value) async => currentRate = value;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    currentRate = 1.0;
  }
}

class CompletingSourceResettingPlayer extends SourceResettingPlayer {
  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    currentRate = 1.0;
    await Future<void>.delayed(Duration.zero);
    completed.add(null);
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
    tts.rate = 3;
    await until(() => player.rates.last == 3);
    tts.rate = 4;
    await until(() => player.rates.last == 4);
    expect(Prefs().ttsRate, 4);
    expect(requests.length, 2); // No new synthesis for 3x/4x playback.
    await tts.pause();
    final before = player.rates.length;
    tts.rate = 0.1;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(player.rates.length, before);
    expect(player.resumes, 0);
    await tts.resume();
    expect(player.rates.last, 0.1);
    expect(player.resumes, 1);
    player.completed.add(null);
    await until(() => player.playedRates.length == 2);
    expect(player.playedRates, [1.2, 0.1]);
    expect(requests.length, 2);
    for (final request in requests) {
      expect(request.toString(), isNot(contains('语速约为')));
    }
    player.completed.add(null);
    await reading;
    expect(tts.playbackError, isNull);
  });

  for (final engine in ['MiMo', 'OpenAI', 'compatible OpenAI']) {
    final customOpenAi = engine != 'MiMo';
    test('local pitch preserves buffered audio and pause state ($engine)',
        () async {
      const channel = MethodChannel('xyz.luan/audioplayers');
      final native = NativePitchPlayer();
      final pitches = <double>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'setPitch');
        expect(call.arguments['playerId'], native.playerId);
        pitches.add(call.arguments['pitch'] as double);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      await Prefs().saveOnlineTtsConfig('openai', {
        'key': 'test-only',
        'url': engine == 'OpenAI'
            ? 'https://api.openai.com/v1/audio/speech'
            : 'https://tts.example/v1/audio/speech',
        'model': engine == 'OpenAI' ? 'gpt-4o-mini-tts' : 'tts-1',
      });
      final openai =
          OpenAiTtsProvider.forTesting(client: MockClient((request) async {
        requests.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response.bytes([73, 68, 51, 0], 200);
      }));
      var cursor = 0;
      final tts = OnlineTts.forTesting(
        backend: customOpenAi ? openai : provider,
        localPitch: true,
        createPlayer: () => native,
        collect: (_) async =>
            const [TtsSentence(text: '音调第一段'), TtsSentence(text: '音调第二段')],
      );
      addTearDown(tts.stop);
      await tts.init(() async => '音调第一段',
          () async => ++cursor < 2 ? '音调第二段' : '', () async => '');
      final reading = tts.speak();
      await until(() => native.playedRates.length == 1 && requests.length == 2);
      expect(pitches, [1.0]);
      for (final value in [0.5, 0.8, 1.1, 1.6, 2.0]) {
        tts.pitch = value;
        await until(() => pitches.last == value);
      }
      final changes = pitches.length;
      for (final invalid in [2.0, 0.4, 2.1, double.nan, double.infinity]) {
        tts.pitch = invalid;
      }
      await Future<void>.delayed(Duration.zero);
      expect(pitches.length, changes);
      expect(Prefs().ttsPitch, 2);
      expect(requests.length, 2);
      await tts.pause();
      tts.pitch = 1.3;
      await until(() => pitches.last == 1.3);
      expect(tts.isPlaying, isFalse);
      expect(native.resumes, 0);
      await tts.resume();
      expect(native.resumes, 1);
      tts.rate = 1.7;
      await until(() => native.rates.last == 1.7);
      expect(pitches.last, 1.3);
      native.completed.add(null);
      await until(() => native.playedRates.length == 2);
      expect(pitches.last, 1.3);
      expect(requests.length, 2,
          reason: 'pitch and speed reuse already synthesized passages');
      for (final request in requests) {
        expect(request.toString(), isNot(contains('默认的')));
        if (customOpenAi) {
          expect(request.containsKey('speed'), isFalse);
          if (engine == 'OpenAI') {
            expect(request['instructions'], isNot(contains('pitch')));
          } else {
            expect(request.containsKey('instructions'), isFalse);
          }
        }
      }
      native.completed.add(null);
      await reading;
      expect(tts.playbackError, isNull);
    });
  }

  test('preview uses saved local speed and clamps legacy zero speed', () async {
    Prefs().ttsRate = 0;
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => player,
      collect: (_) async => [],
    );
    addTearDown(tts.stop);
    await tts.speakWithVoice('试听正文', 'mimo_default');
    expect(player.playedRates, [0.1]);
    tts.rate = 1.6;
    await tts.speakWithVoice('再次试听', 'mimo_default');
    expect(player.playedRates.last, 1.6);
    expect(requests.length, 2);
  });

  test('rate survives a source reset (the path used by every sentence)',
      () async {
    Prefs().ttsRate = 1.5;
    final resetting = SourceResettingPlayer();
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => resetting,
      collect: (_) async => const [
        TtsSentence(text: '第一句'),
        TtsSentence(text: '第二句'),
      ],
    );
    addTearDown(tts.stop);
    await tts.init(
      () async => '第一句',
      () async => ++cursor < 2 ? '第二句' : '',
      () async => '',
    );
    // Preview path uses play() with a fresh source, exactly like each
    // synthesized sentence. The native player resets its rate on that source
    // change, so the rate must be applied after play() returns.
    await tts.speakWithVoice('试听正文', 'mimo_default');
    expect(resetting.currentRate, 1.5);
  });

  test('the following sentence keeps the rate after its source reset',
      () async {
    Prefs().ttsRate = 1.5;
    final resetting = CompletingSourceResettingPlayer();
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => resetting,
      collect: (_) async => const [
        TtsSentence(text: '第一句'),
        TtsSentence(text: '第二句'),
      ],
    );
    addTearDown(tts.stop);
    await tts.init(
      () async => '第一句',
      () async => ++cursor < 2 ? '第二句' : '',
      () async => '',
    );
    await tts.speak();
    expect(resetting.currentRate, 1.5);
  });

  test('saved 4x is used for preview and restored playback', () async {
    Prefs().ttsRate = 4;
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => player,
      collect: (_) async => [],
    );
    addTearDown(tts.stop);
    await tts.speakWithVoice('四倍速试听', 'mimo_default');
    expect(player.playedRates, [4]);
    for (final value in [0.0, 0.09, 4.1, -1.0, double.infinity, double.nan]) {
      tts.rate = value;
      expect(Prefs().ttsRate, 4);
    }
  });
}
