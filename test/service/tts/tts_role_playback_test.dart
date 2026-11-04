import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/tts_role_config.dart';
import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/edge_tts_backend.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mimo_playback_rate_test.dart' show RatePlayer;
import 'tts_reader_sequence_test.dart' show until;

class RecordingEdgeProvider extends RecordingTtsProvider
    implements EdgeTtsProvider {}

/// Records the voice each synthesis request actually used.
class RecordingTtsProvider extends TtsServiceProvider {
  RecordingTtsProvider({this.selected = 'narrator'});

  final String selected;
  final List<(String text, String voice, double rate)> calls = [];

  @override
  TtsService get service => TtsService.edge;

  @override
  String getLabel(BuildContext context) => 'recording';

  @override
  String getSelectedVoice() => selected;

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) async {
    calls.add((text, voice ?? '', rate));
    return Uint8List.fromList([1]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    OnlineTts.clearCachedAudio();
  });
  tearDown(OnlineTts.clearCachedAudio);

  test('narration and quoted dialogue use their configured voices', () async {
    var advances = 0;
    var collected = false;
    final provider = RecordingTtsProvider();
    final played = <TtsSegment>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async {
        if (collected) return const [];
        collected = true;
        return const [TtsSentence(text: '他说：“走吧。”', cfi: 'cfi-1')];
      },
      backend: provider,
      play: (segment) async => played.add(segment),
    )..roleConfigResolver = () => const TtsRoleConfig(
          enabled: true,
          narrationVoice: 'narrator',
          dialogueVoice: 'dialogue',
        );

    await tts.init(() async => '他说：“走吧。”', () async {
      advances++;
      return '';
    }, () async => '');
    await tts.speak().timeout(const Duration(seconds: 5));

    expect(provider.calls.map((call) => call.$2).toList(),
        ['narrator', 'dialogue']);
    expect(provider.calls.map((call) => call.$1).toList(), ['他说：', '“走吧。”']);
    expect(played.map((segment) => segment.sentence.text).toList(),
        ['他说：', '“走吧。”']);
    // Two runs, one cursor step: the passage must not be skipped twice.
    expect(advances, 1);
  });

  test('a disabled configuration uses the selected voice once', () async {
    var advances = 0;
    var collected = false;
    final provider = RecordingTtsProvider();
    final tts = OnlineTts.forTesting(
      collect: (_) async {
        if (collected) return const [];
        collected = true;
        return const [TtsSentence(text: '他说：“走吧。”', cfi: 'cfi-1')];
      },
      backend: provider,
      play: (_) async {},
    )..roleConfigResolver = () => TtsRoleConfig.disabled;

    await tts.init(() async => '他说：“走吧。”', () async {
      advances++;
      return '';
    }, () async => '');
    await tts.speak().timeout(const Duration(seconds: 5));

    expect(provider.calls, hasLength(1));
    expect(provider.calls.single.$1, '他说：“走吧。”');
    expect(provider.calls.single.$2, 'narrator');
    expect(advances, 1);
  });

  test('each role keeps its own speed multiplier on top of the global rate',
      () async {
    Prefs().ttsRate = 1.5;
    final provider = RecordingTtsProvider();
    final tts = OnlineTts.forTesting(
      collect: (_) async => const [TtsSentence(text: '他说：“走吧。”', cfi: 'cfi-1')],
      backend: provider,
      play: (_) async {},
    )..roleConfigResolver = () => const TtsRoleConfig(
          enabled: true,
          narrationVoice: 'narrator',
          dialogueVoice: 'dialogue',
          narrationRate: 0.9,
          dialogueRate: 1.2,
        );

    await tts.init(() async => 'x', () async => '', () async => '');
    await tts.speak().timeout(const Duration(seconds: 5));

    expect(provider.calls, hasLength(2));
    expect(provider.calls[0].$2, 'narrator');
    expect(provider.calls[0].$3, closeTo(1.35, 0.0001));
    expect(provider.calls[1].$2, 'dialogue');
    expect(provider.calls[1].$3, closeTo(1.8, 0.0001));
  });

  test('playback stays inside the engine range after the role multiplier', () {
    Prefs().ttsRate = 3.0;
    final tts = OnlineTts.forTesting(
      collect: (_) async => const [],
      synthesize: (_) async => Uint8List.fromList([1]),
      backend: EdgeTtsProvider(),
    )..roleConfigResolver = () => const TtsRoleConfig(
          enabled: true,
          narrationVoice: 'narrator',
          dialogueVoice: 'dialogue',
          narrationRate: 0.9,
          dialogueRate: 1.2,
        );
    // Edge synthesises up to 2x and accelerates locally beyond that.
    expect(
        tts.rolePlaybackRateFor(TtsSpeakerRole.narration), closeTo(1.35, .001));
    expect(
        tts.rolePlaybackRateFor(TtsSpeakerRole.dialogue), closeTo(1.8, .001));
  });

  test('Edge refreshes slower-role audio above 2x and resumes consistently',
      () async {
    Prefs().ttsRate = 2.5;
    final provider = RecordingEdgeProvider();
    final player = RatePlayer();
    var config = const TtsRoleConfig(
        enabled: true, dialogueVoice: 'dialogue', dialogueRate: .5);
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      backend: provider,
      createPlayer: () => player,
      collect: (_) async => const [
        TtsSentence(text: '旁白第一段'),
        TtsSentence(text: '“对话第二段”'),
      ],
    )..roleConfigResolver = () => config;
    addTearDown(tts.stop);
    await tts.init(() async => '旁白第一段',
        () async => ++cursor < 2 ? '“对话第二段”' : '', () async => '');
    final reading = tts.speak();
    await until(
        () => player.playedRates.length == 1 && provider.calls.length == 2);
    expect(provider.calls.last.$3, 1.25);
    tts.rate = 3.5;
    await until(() => provider.calls.length == 3);
    expect(provider.calls.last.$3, 1.75);
    await until(() => player.rates.last == 1.75);

    // Already synthesized audio must retain its role settings until consumed.
    config = config.copyWith(dialogueRate: 2);
    player.completed.add(null);
    await until(() => player.playedRates.length == 2);
    expect(player.playedRates.last, 1);
    await tts.pause();
    tts.rate = 4;
    await tts.resume();
    expect(player.rates.last, 1,
        reason: 'resuming must not speed up audio synthesized at the old rate');
    expect(player.resumes, 1);
    player.completed.add(null);
    await reading;
    expect(cursor, 2);
    expect(tts.playbackError, isNull);
  });

  test('Edge retains the last applied speed while old audio is paused',
      () async {
    Prefs().ttsRate = 2.5;
    final player = RatePlayer();
    final tts = OnlineTts.forTesting(
      backend: RecordingEdgeProvider(),
      createPlayer: () => player,
      collect: (_) async => const [TtsSentence(text: '暂停的当前旁白')],
    );
    addTearDown(tts.stop);
    await tts.init(() async => '暂停的当前旁白', () async => '', () async => '');
    final reading = tts.speak();
    await until(() => player.playedRates.isNotEmpty);
    tts.rate = 3.5;
    await until(() => player.rates.last == 1.75);
    await tts.pause();
    tts.rate = 1.5;
    await tts.resume();
    expect(player.rates.last, 1.75);
    player.completed.add(null);
    await reading;
  });
}
