import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/tts_media_state.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_rate_recovery_test.dart' show NativePlayer;

class PausableBackend extends Fake implements BaseTts {
  @override
  final ttsStateNotifier = ValueNotifier(TtsStateEnum.paused);
  final reading = Completer<void>();
  Completer<void>? pauseGate;
  int resumes = 0;
  bool audible = false;
  @override
  bool get isPlaying => ttsStateNotifier.value == TtsStateEnum.playing;
  @override
  void updateTtsState(TtsStateEnum state) => ttsStateNotifier.value = state;
  @override
  Future<void> init(Function a, Function b, Function c) async {}
  @override
  Future<void> pause() async {
    updateTtsState(TtsStateEnum.paused);
    await pauseGate?.future;
    audible = false;
  }

  @override
  Future<void> resume() async {
    resumes++;
    audible = true;
    await reading.future;
  }

  @override
  Future<void> stop() async {
    audible = false;
    updateTtsState(TtsStateEnum.stopped);
  }
}

class DelayedControlPlayer extends NativePlayer {
  Completer<void>? pauseGate;
  Completer<void>? resumeGate;
  bool audible = false;
  int resumes = 0, pauses = 0;
  @override
  Future<void> pause() async {
    pauses++;
    await pauseGate?.future;
    audible = false;
  }

  @override
  Future<void> resume() async {
    resumes++;
    await resumeGate?.future;
    audible = true;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  });
  tearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  Future<TtsHandler> handler(PausableBackend backend,
      {Future<bool> Function()? focus}) async {
    final result = TtsHandler.forTesting(
        factory: TtsFactory.forTesting(() => backend),
        activateSession: focus ?? () async => true,
        deactivateSession: () async {});
    await result.init(() => '', () => '', () => '');
    final item = ttsMediaItem(
        bookId: 'test-book',
        title: 'Test',
        author: '',
        chapter: 'Chapter 2',
        coverPath: '',
        state: TtsStateEnum.paused);
    result.queue.add([item]);
    result.mediaItem.add(item);
    result.playbackState
        .add(ttsMediaState(PlaybackState(), TtsStateEnum.paused));
    addTearDown(() {
      if (!backend.reading.isCompleted) backend.reading.complete();
    });
    return result;
  }

  test(
      'paused notification resumes retained audio without a mounted reader or frame',
      () async {
    final backend = PausableBackend();
    final control = await handler(backend);
    for (var i = 0; i < 3; i++) {
      await control.play().timeout(const Duration(seconds: 1));
      expect(backend.resumes, i + 1);
      expect(backend.audible, true);
      expect(control.playbackState.value.playing, true);
      expect(control.mediaItem.value?.displaySubtitle, 'Chapter 2');
      await control.pause();
      expect(backend.audible, false);
      expect(control.playbackState.value.controls[1].action, MediaAction.play);
    }
  });

  test('Play waits for native pause to complete, not for the reading lifetime',
      () async {
    final backend = PausableBackend();
    final control = await handler(backend);
    await control.play();
    backend.pauseGate = Completer<void>();
    final pausing = control.pause();
    final resuming = control.play();
    await Future<void>.delayed(Duration.zero);
    expect(backend.resumes, 1);
    backend.pauseGate!.complete();
    await pausing;
    await resuming.timeout(const Duration(seconds: 1));
    expect(backend.resumes, 2);
    expect(backend.audible, true);
  });

  test('focus denial keeps the play button and permits retry', () async {
    final backend = PausableBackend();
    var allowed = false;
    final control = await handler(backend, focus: () async => allowed);
    await control.play();
    expect(backend.resumes, 0);
    expect(control.playbackState.value.playing, false);
    allowed = true;
    await control.play();
    expect(backend.resumes, 1);
  });

  test('later stop cancels resume awaiting audio focus', () async {
    final backend = PausableBackend();
    final focus = Completer<bool>();
    final control = await handler(backend, focus: () => focus.future);
    final resuming = control.play();
    await Future<void>.delayed(Duration.zero);
    await control.stop();
    focus.complete(true);
    await resuming;
    expect(backend.resumes, 0);
    expect(control.mediaItem.value, isNull);
    expect(control.playbackState.value.playing, false);
  });

  for (final lastPlaying in [false, true]) {
    test('native resume racing pause: last requested playing=$lastPlaying wins',
        () async {
      final player = DelayedControlPlayer()..resumeGate = Completer<void>();
      final tts = OnlineTts.forTesting(
          player: player,
          collect: (_) async => [],
          synthesize: (_) async => Uint8List(1));
      final resuming = tts.resume();
      await Future<void>.delayed(Duration.zero);
      expect(player.resumes, 1);
      final pausing = tts.pause();
      final latest = lastPlaying ? tts.resume() : Future<void>.value();
      player.resumeGate!.complete();
      await Future.wait([resuming, pausing, latest]);
      expect(tts.isPlaying, lastPlaying);
      expect(player.audible, lastPlaying);
      await tts.stop();
    });
  }
}
