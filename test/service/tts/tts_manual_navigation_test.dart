import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final system in [false, true]) {
    test(
        '${system ? "system" : "online"}: playing navigation never publishes a stopped state',
        () async {
      final finish = Completer<void>();
      final began = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async {
        if (call.method == 'speak') {
          began.complete();
          await finish.future;
        }
        return 1;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_tts'), null));
      final BaseTts tts = system
          ? SystemTts.forTesting(supported: true)
          : OnlineTts.forTesting(
              collect: (_) async => [const TtsSentence(text: '前一句')],
              synthesize: (_) async => Uint8List.fromList([1]),
              play: (_) async {
                began.complete();
                await finish.future;
              },
            );
      await tts.init(() async => '当前位置', () async => '', () async => '前一句');
      tts.updateTtsState(TtsStateEnum.playing);
      final states = <TtsStateEnum>[];
      tts.ttsStateNotifier
          .addListener(() => states.add(tts.ttsStateNotifier.value));
      final navigation = tts.prev();
      await began.future.timeout(const Duration(seconds: 5));
      expect(tts.isPlaying, isTrue);
      expect(states, isNot(contains(TtsStateEnum.stopped)));
      final stopping = tts.stop();
      finish.complete();
      await stopping;
      await navigation;
      expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
    });

    test(
        '${system ? "system" : "online"}: repeated paused navigation preserves controls and resumes selected sentence',
        () async {
      final played = <String>[];
      const sentences = ['第一句', '第二句', '第三句'];
      var cursor = 0, hereCalls = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async {
        if (call.method == 'speak') {
          played.add(call.arguments is String
              ? call.arguments as String
              : call.arguments['text'] as String);
        }
        return 1;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_tts'), null));
      final BaseTts tts = system
          ? SystemTts.forTesting(supported: true)
          : OnlineTts.forTesting(
              collect: (_) async => [TtsSentence(text: sentences[cursor])],
              synthesize: (_) async => Uint8List.fromList([1]),
              play: (segment) async => played.add(segment.sentence.text),
            );
      addTearDown(tts.stop);
      await tts.init(() async {
        hereCalls++;
        return sentences[cursor];
      }, () async => ++cursor < sentences.length ? sentences[cursor] : '',
          () async => cursor > 0 ? sentences[--cursor] : '');
      tts.updateTtsState(TtsStateEnum.paused);
      final states = <TtsStateEnum>[];
      tts.ttsStateNotifier
          .addListener(() => states.add(tts.ttsStateNotifier.value));
      await tts.next();
      await tts.next();
      await tts.prev();
      expect(cursor, 1);
      expect(tts.currentVoiceText, '第二句');
      expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
      expect(states, isNot(contains(TtsStateEnum.stopped)));
      expect(played, isEmpty);
      await tts.resume().timeout(const Duration(seconds: 5));
      expect(played, ['第二句', '第三句']);
      expect(hereCalls, 0,
          reason: 'resume must not reset to the viewport/start selection');
    });
  }

  test(
      'real synthesis failure does not prevent Previous or force retry of the failing sentence',
      () async {
    var cursor = 1;
    final played = <String>[];
    const sentences = ['前一句', '失败的正文', '后一句'];
    final tts = OnlineTts.forTesting(
      collect: (_) async => [TtsSentence(text: sentences[cursor])],
      synthesize: (text) async {
        if (text == '失败的正文') throw StateError('bad audio');
        return Uint8List.fromList([1]);
      },
      play: (segment) async => played.add(segment.sentence.text),
    );
    addTearDown(tts.stop);
    await tts.init(() async => sentences[cursor], () async => '',
        () async => sentences[--cursor]);
    await tts.speak();
    expect(tts.playbackError, isNotNull);
    await tts.prev();
    expect(cursor, 0);
    expect(tts.playbackError, isNull);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
    await tts.resume();
    expect(played, ['前一句']);
  });
}
