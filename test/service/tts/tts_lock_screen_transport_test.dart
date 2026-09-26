import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/tts_media_state.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audioplayers/audioplayers.dart';
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

class UnfinishedSourcePlayer extends DelayedControlPlayer {
  final started = Completer<void>();
  int plays = 0;
  @override
  Future<void> play(Source source,
      {double? volume,
      double? balance,
      AudioContext? ctx,
      Duration? position,
      PlayerMode? mode}) async {
    plays++;
    started.complete();
    // The test sends the native completion event after pause/resume.
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

  test('stop cancels a locked-screen chapter before waiting for the audio loop',
      () async {
    final chapter = Completer<String>();
    final waiting = Completer<void>();
    final spoken = <String>[];
    var cancellations = 0;
    final backend = OnlineTts.forTesting(
      collect: (_) async => [const TtsSentence(text: '本章末句')],
      synthesize: (_) async => Uint8List.fromList([1]),
      play: (segment) async => spoken.add(segment.sentence.text),
    );
    final control = TtsHandler.forTesting(
      factory: TtsFactory.forTesting(() => backend),
      activateSession: () async => true,
      deactivateSession: () async {},
      stopReader: () async {
        cancellations++;
        chapter.complete('');
      },
    );
    await control.init(() async => '本章末句', () {
      waiting.complete();
      return chapter.future;
    }, () async => '');
    final playing = backend.speak();
    try {
      await waiting.future.timeout(const Duration(seconds: 2));
      await control.stop().timeout(const Duration(seconds: 2));
      await playing;
      expect(cancellations, 1);
      expect(spoken, ['本章末句']);
      expect(control.playbackState.value.playing, false);
      expect(control.mediaItem.value, isNull);
      expect(backend.ttsStateNotifier.value, TtsStateEnum.stopped);
    } finally {
      if (!chapter.isCompleted) chapter.complete('');
      await backend.stop();
    }
  });

  test('resume while awaiting a chapter never restarts the completed source',
      () async {
    final chapter = Completer<String>();
    final waiting = Completer<void>();
    final player = DelayedControlPlayer();
    var cursor = 0;
    const text = ['本章末句', '下一章首句'];
    final backend = OnlineTts.forTesting(
      createPlayer: () => player,
      collect: (_) async =>
          cursor < text.length ? [TtsSentence(text: text[cursor])] : [],
      synthesize: (_) async => Uint8List.fromList([1]),
    );
    await backend.init(() async => text.first, () async {
      if (cursor == 0) {
        waiting.complete();
        final next = await chapter.future;
        cursor++;
        return next;
      }
      cursor++;
      return '';
    }, () async => '');
    final playing = backend.speak();
    try {
      await waiting.future.timeout(const Duration(seconds: 2));
      // Models notification controls or a temporary audio-focus interruption
      // in the gap after native completion and before chapter navigation.
      for (var i = 0; i < 2; i++) {
        await backend.pause();
        await backend.resume();
      }
      expect(player.resumes, 0);
      expect(cursor, 0);
      expect(backend.isPlaying, true);
      chapter.complete(text[1]);
      await playing.timeout(const Duration(seconds: 2));
      expect(cursor, 2);
      expect(backend.ttsStateNotifier.value, TtsStateEnum.stopped);
    } finally {
      if (!chapter.isCompleted) chapter.complete('');
      await backend.stop();
    }
  });

  test('resume during an unfinished sentence still resumes that native source',
      () async {
    final player = UnfinishedSourcePlayer();
    final backend = OnlineTts.forTesting(
      createPlayer: () => player,
      collect: (_) async => [const TtsSentence(text: '尚未读完的句子')],
      synthesize: (_) async => Uint8List.fromList([1]),
    );
    await backend.init(() async => '尚未读完的句子', () async => '', () async => '');
    final playing = backend.speak();
    try {
      await player.started.future.timeout(const Duration(seconds: 2));
      await backend.pause();
      await backend.resume();
      expect(player.resumes, 1);
      expect(player.plays, 1);
      expect(backend.isPlaying, true);
      player.completed.add(null);
      await playing.timeout(const Duration(seconds: 2));
    } finally {
      await backend.stop();
    }
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
