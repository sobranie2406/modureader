import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_synthesis_error.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    OnlineTts.clearCachedAudio();
  });
  tearDown(OnlineTts.clearCachedAudio);

  test('failure classification and server cooldowns are safe and bounded', () {
    for (final status in [408, 429, 500, 502, 503, 504]) {
      expect(
          TtsSynthesisError(TtsFailureReason.http, '', statusCode: status)
              .retryable,
          true);
    }
    for (final status in [400, 401, 403, 404, 422]) {
      expect(
          TtsSynthesisError(TtsFailureReason.http, '', statusCode: status)
              .retryable,
          false);
    }
    expect(TtsSynthesisError.classify(const SocketException('SECRET')).reason,
        TtsFailureReason.network);
    expect(TtsSynthesisError.classify(TimeoutException('SECRET')).reason,
        TtsFailureReason.timeout);
    expect(
        TtsSynthesisError.classify(const FormatException('SECRET')).retryable,
        false);
    expect(TtsSynthesisError.parseRetryAfter('5'), const Duration(seconds: 5));
    expect(TtsSynthesisError.parseRetryAfter('-1'), isNull);
    expect(TtsSynthesisError.parseRetryAfter('SECRET'), isNull);
    final now = DateTime.utc(2026, 10, 10);
    expect(
        TtsSynthesisError.parseRetryAfter(
            HttpDate.format(now.add(const Duration(seconds: 9))),
            now: now),
        const Duration(seconds: 9));
  });

  test(
      'transient retries wait 1s then 2s and recover without skipping or logging content',
      () async {
    var calls = 0, advances = 0;
    final times = <DateTime>[];
    final played = <String>[];
    final logs = <String>[];
    final sub = AnxLog.log.onRecord.listen((r) => logs.add(r.message));
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: 'PRIVATE_BOOK')],
      synthesize: (_) async {
        times.add(DateTime.now());
        if (++calls < 3) throw const SocketException('KEY URL PRIVATE_BOOK');
        return Uint8List.fromList([1]);
      },
      play: (s) async => played.add(s.sentence.text),
    );
    await tts.init(() async => 'PRIVATE_BOOK', () async {
      advances++;
      return '';
    }, () async => '');
    final reading = tts.speak();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(calls, 1);
    expect(advances, 0);
    await reading.timeout(const Duration(seconds: 6));
    expect(calls, 3);
    expect(times[1].difference(times[0]),
        greaterThanOrEqualTo(const Duration(seconds: 1)));
    expect(times[2].difference(times[1]),
        greaterThanOrEqualTo(const Duration(seconds: 2)));
    expect(played, ['PRIVATE_BOOK']);
    expect(advances, 1);
    expect(logs.join(), contains('reason=network'));
    expect(logs.join(), contains('TTS fetch recovered'));
    expect(logs.join(), isNot(contains('PRIVATE_BOOK')));
    expect(logs.join(), isNot(contains('KEY URL')));
    await tts.stop();
    await sub.cancel();
  });

  for (final status in [401, 429, 503]) {
    test('HTTP $status retains cursor; manual resume retries same passage',
        () async {
      var calls = 0, advances = 0, fail = true;
      final played = <String>[];
      final tts = OnlineTts.forTesting(
        collect: (_) async => [const TtsSentence(text: '正文')],
        synthesize: (_) async {
          calls++;
          if (fail) {
            throw TtsSynthesisError(TtsFailureReason.http, 'safe',
                statusCode: status);
          }
          return Uint8List.fromList([1]);
        },
        play: (s) async => played.add(s.sentence.text),
      );
      await tts.init(() async => '正文', () async {
        advances++;
        return '';
      }, () async => '');
      final reading = tts.speak();
      await reading.timeout(const Duration(seconds: 6));
      expect(calls, status == 401 ? 1 : 3);
      expect(advances, 0);
      expect(played, isEmpty);
      expect(tts.playbackError, isNotNull);
      fail = false;
      final resume = tts.resume();
      await resume.timeout(const Duration(seconds: 2));
      expect(played, ['正文']);
      expect(advances, 1);
      await tts.stop();
    });
  }

  for (final cooldown in [5, 120]) {
    test('Retry-After $cooldown is respected and stop cancels waiting',
        () async {
      var calls = 0, advances = 0;
      final tts = OnlineTts.forTesting(
        collect: (_) async => [const TtsSentence(text: '正文')],
        synthesize: (_) async {
          calls++;
          throw TtsSynthesisError(TtsFailureReason.http, 'safe',
              statusCode: 429, retryAfter: Duration(seconds: cooldown));
        },
        play: (_) async => fail('must not play failed audio'),
      );
      await tts.init(() async => '正文', () async {
        advances++;
        return '';
      }, () async => '');
      final reading = tts.speak();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(calls, 1);
      expect(advances, 0);
      if (cooldown > 60) expect(tts.playbackError, isNotNull);
      final stopping = tts.stop();
      await stopping.timeout(const Duration(milliseconds: 500));
      await reading;
      expect(calls, 1);
    });
  }

  test('server cooldown overrides shorter client backoff before recovery',
      () async {
    final times = <DateTime>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '正文')],
      synthesize: (_) async {
        times.add(DateTime.now());
        if (times.length == 1) {
          throw TtsSynthesisError(TtsFailureReason.http, 'safe',
              statusCode: 429, retryAfter: const Duration(seconds: 2));
        }
        return Uint8List.fromList([1]);
      },
      play: (_) async {},
    );
    addTearDown(tts.stop);
    await tts.init(() async => '正文', () async => '', () async => '');
    await tts.speak().timeout(const Duration(seconds: 5));
    expect(times.length, 2);
    expect(times[1].difference(times[0]),
        greaterThanOrEqualTo(const Duration(seconds: 2)));
  });

  test(
      'next passage cancels old backoff without replaying or retrying old text',
      () async {
    var current = '第一段';
    final calls = <String>[];
    final played = <String>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async => [TtsSentence(text: current)],
      synthesize: (text) async {
        calls.add(text);
        if (text == '第一段') throw const SocketException('offline');
        return Uint8List.fromList([1]);
      },
      play: (segment) async => played.add(segment.sentence.text),
    );
    addTearDown(tts.stop);
    await tts.init(() async => current, () async => '', () async => '');
    final reading = tts.speak();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tts
        .next(locate: () async => current = '第二段')
        .timeout(const Duration(seconds: 2));
    await reading;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, ['第一段', '第二段']);
    expect(played, ['第二段']);
  });
}
