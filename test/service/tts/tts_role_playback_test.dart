import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/tts_role_config.dart';
import 'package:anx_reader/service/tts/models/tts_segment.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/models/tts_voice.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_service.dart';
import 'package:anx_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records the voice each synthesis request actually used.
class RecordingTtsProvider extends TtsServiceProvider {
  RecordingTtsProvider({this.selected = 'narrator'});

  final String selected;
  final List<(String text, String voice)> calls = [];

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
    calls.add((text, voice ?? ''));
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
}
