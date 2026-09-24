import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_reader_sequence_test.dart' show until, FailingCleanupPlayer;

class NativePlayer extends Fake implements AudioPlayer {
  NativePlayer({this.failInit = false, this.failPlay = false});
  final bool failInit, failPlay;
  final completed = StreamController<void>.broadcast(sync: true);
  int disposals = 0;
  AudioContext? context;
  @override
  Future<void> setAudioContext(AudioContext value) async {
    context = value;
  }

  @override
  Stream<void> get onPlayerComplete => completed.stream;
  @override
  Future<void> setReleaseMode(ReleaseMode mode) async {
    if (failInit) throw PlatformException(code: 'native-init');
  }

  @override
  Future<void> setPlayerMode(PlayerMode mode) async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    disposals++;
    await completed.close();
  }

  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    if (failPlay) throw PlatformException(code: 'native-play');
    completed.add(null);
  }
}

class DisposableTts extends Fake implements BaseTts {
  final gate = Completer<void>();
  int disposals = 0;
  bool fail = false;
  @override
  Future<void> dispose() async {
    disposals++;
    await gate.future;
    if (fail) throw PlatformException(code: 'native-dispose');
  }
}

class FailingControlPlayer extends NativePlayer {
  @override
  Future<void> pause() async => throw PlatformException(code: 'native-pause');
  @override
  Future<void> resume() async => throw PlatformException(code: 'native-resume');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final failsAtInit in [true, false]) {
    test(
        'native ${failsAtInit ? "initialization" : "playback"} failure creates a fresh player on retry',
        () async {
      final bad = NativePlayer(failInit: failsAtInit, failPlay: !failsAtInit);
      final good = NativePlayer();
      var created = 0, advances = 0;
      final tts = OnlineTts.forTesting(
        createPlayer: () => ++created == 1 ? bad : good,
        collect: (_) async => [const TtsSentence(text: '同一句')],
        synthesize: (_) async => Uint8List.fromList([1]),
      );
      await tts.init(() async => '同一句', () async {
        advances++;
        return '';
      }, () async => '');
      await tts.speak();
      expect(tts.playbackError, isNotNull);
      expect(advances, 0);
      tts.rate = 1.4;
      await tts.resume();
      expect(created, 2);
      expect(bad.disposals, 1);
      expect(good.context?.android.stayAwake, isTrue);
      expect(good.context?.android.audioFocus, AndroidAudioFocus.none);
      expect(good.context?.android.contentType, AndroidContentType.speech);
      expect(advances, 1);
      expect(tts.playbackError, isNull);
      await tts.stop();
    });
  }

  for (final pausing in [true, false]) {
    test(
        'native ${pausing ? "pause" : "resume"} failure is recoverable without unhandled errors',
        () async {
      final broken = FailingControlPlayer();
      var spoken = 0;
      final tts = OnlineTts.forTesting(
        player: broken,
        collect: (_) async => [const TtsSentence(text: '原句')],
        synthesize: (_) async => Uint8List.fromList([1]),
        play: (_) async {
          spoken++;
        },
      );
      await tts.init(() async => '原句', () async => '', () async => '');
      if (pausing) {
        await tts.pause();
      } else {
        await tts.resume();
      }
      expect(tts.playbackError, isNotNull);
      expect(tts.isPlaying, isFalse);
      await tts.resume();
      expect(broken.disposals, 1);
      expect(spoken, 1);
      expect(tts.playbackError, isNull);
      await tts.stop();
    });
  }

  for (final staleFails in [false, true]) {
    test(
        'rapid rate changes discard stale ${staleFails ? "errors" : "audio"} without poisoning speech',
        () async {
      final stale = Completer<Uint8List>();
      final requestedRates = <double>[];
      final played = <int>[];
      final tts = OnlineTts.forTesting(
        collect: (_) async => [const TtsSentence(text: '语速测试')],
        synthesize: (_) async {
          requestedRates.add(Prefs().ttsRate);
          if (requestedRates.length == 1) return stale.future;
          return Uint8List.fromList([2]);
        },
        play: (segment) async => played.add(segment.audio!.single),
      );
      await tts.init(() async => '语速测试', () async => '', () async => '');
      final speaking = tts.speak();
      await until(() => requestedRates.isNotEmpty);
      tts.rate = 0.8;
      tts.rate = 1.2;
      tts.rate = 1.6;
      if (staleFails) {
        stale.completeError(PlatformException(code: 'old-rate-failed'));
      } else {
        stale.complete(Uint8List.fromList([1]));
      }
      await speaking;
      expect(requestedRates, [0.6, 1.6]);
      expect(played, [2]);
      expect(tts.playbackError, isNull);
      await tts.stop();
    });
  }

  test(
      'rate change lets current sentence finish and uses new rate on next sentence',
      () async {
    final finish = Completer<void>();
    final spoken = <String>[];
    final rates = <String>[];
    final text = ['正在播放', '接下来'];
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      collect: (_) async =>
          text.skip(cursor).map((s) => TtsSentence(text: s)).toList(),
      synthesize: (s) async {
        rates.add('$s:${Prefs().ttsRate}');
        return Uint8List.fromList([1]);
      },
      play: (s) async {
        spoken.add(s.sentence.text);
        if (spoken.length == 1) await finish.future;
      },
    );
    await tts.init(() async => text[cursor],
        () async => ++cursor < text.length ? text[cursor] : '', () async => '');
    final speaking = tts.speak();
    await until(() => spoken.length == 1);
    tts.rate = 1.4;
    await until(() => rates.contains('接下来:1.4'));
    expect(spoken, ['正在播放']);
    finish.complete();
    await speaking;
    expect(spoken, text);
    await tts.stop();
  });

  test('recovered speech can pause and resume again before the sentence ends',
      () async {
    final finish = Completer<void>();
    var attempts = 0, advances = 0;
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '重试后仍可暂停')],
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (_) async {
        if (++attempts == 1) throw PlatformException(code: 'first-play');
        await finish.future;
      },
    );
    await tts.init(() async => '重试后仍可暂停', () async {
      advances++;
      return '';
    }, () async => '');
    await tts.speak();
    final recovered = tts.resume();
    await until(() => attempts == 2);
    await tts.pause();
    expect(tts.isPlaying, isFalse);
    await tts.resume();
    expect(tts.isPlaying, isTrue);
    finish.complete();
    await recovered;
    expect(advances, 1);
    await tts.stop();
  });

  test('next requests share cleanup; stop prevents their late restart',
      () async {
    final player = FailingCleanupPlayer();
    var advances = 0, plays = 0;
    final tts = OnlineTts.forTesting(
      player: player,
      collect: (_) async => [const TtsSentence(text: '下一句')],
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (_) async {
        plays++;
      },
    );
    await tts.init(() async => '下一句', () async {
      advances++;
      return '下一句';
    }, () async => '');
    final first = tts.next(), second = tts.next();
    await until(() => player.stops == 1);
    final stopping = tts.stop();
    player.stopped.complete();
    await Future.wait([first, second, stopping]);
    expect(advances, 0);
    expect(plays, 0);
    expect(player.disposals, 1);
    expect(tts.isPlaying, isFalse);
  });

  test('stop during pending navigation prevents resumed playback', () async {
    final location = Completer<String>();
    var locating = false, plays = 0;
    final tts = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '下一章')],
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (_) async {
        plays++;
      },
    );
    await tts.init(() async => '当前', () {
      locating = true;
      return location.future;
    }, () async => '');
    final next = tts.next();
    await until(() => locating);
    await tts.stop();
    location.complete('下一章');
    await next;
    expect(plays, 0);
  });

  test('rapid service switches serialize even when native disposal fails',
      () async {
    Prefs().ttsService = 'edge';
    final original = DisposableTts()..fail = true;
    final intermediate = DisposableTts()..gate.complete();
    final last = DisposableTts()..gate.complete();
    final instances = [original, intermediate, last];
    var created = 0;
    final factory = TtsFactory.forTesting(() => instances[created++]);
    expect(factory.current, same(original));
    final first = factory.switchTtsType('xiaomi');
    final second = factory.switchTtsType('openai');
    await until(() => original.disposals == 1);
    expect(created, 1);
    original.gate.complete();
    await Future.wait([first, second]);
    expect(Prefs().ttsService, 'openai');
    expect(factory.current, same(last));
    expect(original.disposals, 1);
    expect(intermediate.disposals, 1);
    await factory.dispose();
  });
}
