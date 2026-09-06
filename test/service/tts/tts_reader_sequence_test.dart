import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> until(bool Function() ready) async {
  for (var n = 0; n < 300; n++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Playback did not reach expected state');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final channel = const MethodChannel('flutter_tts');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
      'system reads initialized title and each following sentence exactly once',
      () async {
    final spoken = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments is String
            ? call.arguments as String
            : (call.arguments as Map)['text'] as String);
      }
      return 1;
    });
    final tts = SystemTts.forTesting(supported: true);
    final sentences = ['第一章', '正文。', '第二章', '下一章正文。'];
    var cursor = 0;
    await tts.init(() async => sentences[cursor], () async {
      cursor++;
      return cursor < sentences.length ? sentences[cursor] : '';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    await tts.speak();
    expect(spoken, sentences);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
    await tts.dispose();
  });

  test('stop rejects a late native completion without advancing the reader',
      () async {
    final completed = Completer<int>();
    var started = false;
    var advances = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') {
        started = true;
        return completed.future;
      }
      return 1;
    });
    final tts = SystemTts.forTesting(supported: true);
    await tts.init(() async => '标题', () async {
      advances++;
      return '正文';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    final playing = tts.speak();
    await until(() => started);
    await tts.stop();
    completed.complete(1);
    await playing;
    expect(advances, 0);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
  });

  test('system pause/resume repeats interrupted sentence, not the next one',
      () async {
    final first = Completer<int>();
    final spoken = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments is String
            ? call.arguments as String
            : (call.arguments as Map)['text'] as String);
        if (spoken.length == 1) return first.future;
      }
      return 1;
    });
    final tts = SystemTts.forTesting(supported: true);
    var advances = 0;
    await tts.init(() async => '标题', () async {
      advances++;
      return advances == 1 ? '正文' : '';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    final old = tts.speak();
    await until(() => spoken.isNotEmpty);
    await tts.pause();
    final resumed = tts.resume();
    first.complete(1);
    await Future.wait([old, resumed]);
    expect(spoken, ['标题', '标题', '正文']);
    expect(advances, 2);
  });

  test(
      'pause during chapter load resumes at the new title without consuming it',
      () async {
    final loaded = Completer<String>();
    final spoken = <String>[];
    var advances = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments is String
            ? call.arguments as String
            : (call.arguments as Map)['text'] as String);
      }
      return 1;
    });
    final tts = SystemTts.forTesting(supported: true);
    await tts.init(() async => '前章末句', () async {
      advances++;
      return advances == 1 ? loaded.future : '';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    final old = tts.speak();
    await until(() => advances == 1);
    await tts.pause();
    final resumed = tts.resume();
    loaded.complete('第二章标题');
    await Future.wait([old, resumed]);
    expect(spoken, ['前章末句', '第二章标题']);
    expect(advances, 2);
  });

  test('system synthesis failure pauses at the title instead of advancing',
      () async {
    var failed = true;
    var advances = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'speak' && failed) {
        throw PlatformException(code: 'synthesis');
      }
      return 1;
    });
    final tts = SystemTts.forTesting(supported: true);
    await tts.init(() async => '标题', () async {
      advances++;
      return '';
    }, () async => '');
    tts.updateTtsState(TtsStateEnum.playing);
    await tts.speak();
    expect(advances, 0);
    expect(tts.currentVoiceText, '标题');
    expect(tts.playbackError, isNotNull);
    failed = false;
    await tts.resume();
    expect(advances, 1);
    expect(tts.playbackError, isNull);
  });

  test(
      'online prefetch preserves new chapter titles and repeated text without CFIs',
      () async {
    final chapters = [
      ['第一章', '相同句。', '相同句。'],
      ['第二章'],
      ['第三章', '末句。']
    ];
    var chapter = 0, cursor = 0;
    final played = <String>[];
    final tts = OnlineTts.forTesting(
      collect: (count) async {
        // Delay across scheduling ticks to exercise producer/consumer ordering.
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return chapters[chapter]
            .skip(cursor)
            .take(count)
            .map((s) => TtsSentence(text: s))
            .toList();
      },
      synthesize: (_) async => Uint8List.fromList([1, 2, 3]),
      play: (segment) async {
        played.add(segment.sentence.text);
      },
    );
    await tts.init(() async => chapters[chapter][cursor], () async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      cursor++;
      if (cursor == chapters[chapter].length) {
        chapter++;
        cursor = 0;
      }
      return chapter == chapters.length ? '' : chapters[chapter][cursor];
    }, () async => '');
    await tts.speak();
    expect(played, chapters.expand((c) => c).toList());
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
    await tts.stop();
  });

  test('online pause at completion prevents advancement until resume',
      () async {
    final finished = Completer<void>();
    var started = false;
    var advances = 0;
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '标题')],
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (_) async {
        started = true;
        await finished.future;
      },
    );
    await tts.init(() async => '标题', () async {
      advances++;
      return '';
    }, () async => '');
    final playing = tts.speak();
    await until(() => started);
    await tts.pause();
    finished.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(advances, 0);
    await tts.resume();
    await playing;
    expect(advances, 1);
    await tts.stop();
  });

  test('online late initialization cannot restart a stopped session', () async {
    final here = Completer<String>();
    var played = 0;
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '标题')],
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (_) async {
        played++;
      },
    );
    await tts.init(() => here.future, () async => '', () async => '');
    final old = tts.speak();
    await tts.stop();
    here.complete('旧标题');
    await old;
    expect(played, 0);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
  });

  test('online synthesis failure retries the same sentence on resume',
      () async {
    var failAudio = true;
    var advances = 0;
    final played = <String>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '不能漏读的标题')],
      synthesize: (_) async {
        if (failAudio) throw StateError('offline');
        return Uint8List.fromList([1]);
      },
      play: (segment) async => played.add(segment.sentence.text),
    );
    await tts.init(() async => '不能漏读的标题', () async {
      advances++;
      return '';
    }, () async => '');
    await tts.speak();
    expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
    expect(tts.playbackError, isNotNull);
    expect(advances, 0);
    expect(played, isEmpty);
    failAudio = false;
    await tts.resume();
    expect(played, ['不能漏读的标题']);
    expect(advances, 1);
    await tts.stop();
  });

  test('online playback failure does not consume the sentence', () async {
    var failed = true, advances = 0;
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '标题')],
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (_) async {
        if (failed) throw StateError('audio device');
      },
    );
    await tts.init(() async => '标题', () async {
      advances++;
      return '';
    }, () async => '');
    await tts.speak();
    expect(advances, 0);
    expect(tts.playbackError, isNotNull);
    failed = false;
    await tts.resume();
    expect(advances, 1);
    await tts.stop();
  });
}
