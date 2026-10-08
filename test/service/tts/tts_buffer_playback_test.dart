import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/tts_buffer_settings.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_reader_sequence_test.dart' show until;
import 'edge_reading_pipeline_test.dart' show StubEdge;

class FirstRequestHangs extends StubEdge {
  int calls = 0;
  @override
  Duration get synthesisTimeout => const Duration(milliseconds: 20);
  @override
  Future<Uint8List> speak(
      String text, String? voice, double rate, double pitch) {
    if (++calls == 1) return Completer<Uint8List>().future;
    return super.speak(text, voice, rate, pitch);
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

  test('a timed-out cached request does not poison synthesis retries',
      () async {
    final backend = FirstRequestHangs();
    final played = <String>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '超时后重新合成。')],
      backend: backend,
      play: (segment) async => played.add(segment.sentence.text),
    );
    addTearDown(tts.stop);
    await tts.init(() async => '超时后重新合成。', () async => '', () async => '');
    await tts.speak().timeout(const Duration(seconds: 5));
    expect(backend.calls, 2);
    expect(played, ['超时后重新合成。']);
    expect(tts.playbackError, isNull);
  });

  for (final minutes in [0, 10]) {
    test('cache retention $minutes is respected at natural end and stop',
        () async {
      Prefs().ttsBufferSettings = TtsBufferSettings(cacheMinutes: minutes);
      final backend = StubEdge();
      final tts = OnlineTts.forTesting(
        collect: (_) async => [const TtsSentence(text: '缓存生命周期测试。')],
        backend: backend,
        play: (_) async {},
      );
      addTearDown(tts.stop);
      await tts.init(() async => '缓存生命周期测试。', () async => '', () async => '');
      await tts.speak();
      expect(OnlineTts.cachedAudioEntries, minutes == 0 ? 0 : 1);
      await tts.stop();
      await tts.speak();
      expect(backend.requests.length, minutes == 0 ? 2 : 1);
      await tts.stop();
      expect(OnlineTts.cachedAudioEntries, minutes == 0 ? 0 : 1);
    });
  }

  test('pause during paragraph gap neither advances nor replays the passage',
      () async {
    Prefs().ttsBufferSettings = const TtsBufferSettings(paragraphPauseMs: 200);
    const passages = [TtsSentence(text: '第一段'), TtsSentence(text: '第二段')];
    final played = <String>[];
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      collect: (n) async => passages.skip(cursor).take(n).toList(),
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (segment) async => played.add(segment.sentence.text),
    );
    addTearDown(tts.stop);
    await tts.init(
        () async => passages.first.text,
        () async => ++cursor < passages.length ? passages[cursor].text : '',
        () async => '');
    final reading = tts.speak();
    await until(() => played.isNotEmpty);
    await tts.pause();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cursor, 0);
    expect(played, ['第一段']);
    await tts.resume();
    await reading;
    expect(played, ['第一段', '第二段']);
  });

  for (final ahead in [0, 1, 8]) {
    test('lookahead $ahead and concurrency are honored and frozen for the run',
        () async {
      Prefs().ttsBufferSettings =
          TtsBufferSettings(ahead: ahead, concurrency: 3);
      final passages = List.generate(14, (i) => TtsSentence(text: '段$i'));
      final first = Completer<void>();
      final requests = <String>[];
      final played = <String>[];
      var cursor = 0, active = 0, maxActive = 0;
      final tts = OnlineTts.forTesting(
        collect: (n) async => passages.skip(cursor).take(n).toList(),
        synthesize: (text) async {
          requests.add(text);
          active++;
          if (active > maxActive) maxActive = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return Uint8List.fromList([1]);
        },
        play: (segment) async {
          played.add(segment.sentence.text);
          if (played.length == 1) await first.future;
        },
      );
      addTearDown(() async {
        if (!first.isCompleted) first.complete();
        await tts.stop();
      });
      await tts.init(
          () async => passages.first.text,
          () async => ++cursor < passages.length ? passages[cursor].text : '',
          () async => '');
      final reading = tts.speak();
      await until(() => requests.length == ahead + 1 && played.isNotEmpty);
      expect(cursor, 0);
      expect(maxActive, lessThanOrEqualTo(3));
      if (ahead == 8) expect(maxActive, 3);
      Prefs().ttsBufferSettings =
          const TtsBufferSettings(ahead: 12, concurrency: 4);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(requests.length, ahead + 1);
      first.complete();
      await reading;
      expect(played, passages.map((p) => p.text));
      expect(requests, passages.map((p) => p.text));
      expect(maxActive, lessThanOrEqualTo(3));
    });
  }

  test('only real paragraph ends pause; stop interrupts a long gap promptly',
      () async {
    Prefs().ttsBufferSettings = const TtsBufferSettings(paragraphPauseMs: 3000);
    const passages = [
      TtsSentence(text: '长段前半', endsParagraph: false),
      TtsSentence(text: '长段末尾', endsParagraph: true),
      TtsSentence(text: '下一段'),
    ];
    final played = <String>[];
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      collect: (n) async => passages.skip(cursor).take(n).toList(),
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (segment) async => played.add(segment.sentence.text),
    );
    addTearDown(tts.stop);
    await tts.init(
        () async => passages.first.text,
        () async => ++cursor < passages.length ? passages[cursor].text : '',
        () async => '');
    final reading = tts.speak();
    await until(
        () => played.length == 2); // no 3s wait within the same paragraph
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(cursor, 1);
    expect(played, ['长段前半', '长段末尾']);
    final watch = Stopwatch()..start();
    await tts.stop();
    await reading;
    expect(watch.elapsedMilliseconds, lessThan(500));
    expect(played, ['长段前半', '长段末尾']);
  });
}
