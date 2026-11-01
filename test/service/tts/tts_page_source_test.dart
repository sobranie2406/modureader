import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/models/narration_position.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/system_tts.dart';
import 'package:anx_reader/service/tts/tts_factory.dart';
import 'package:anx_reader/service/tts/tts_handler.dart';
import 'package:anx_reader/service/tts/tts_media_state.dart';
import 'package:anx_reader/service/tts/tts_page_source.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_lock_screen_transport_test.dart' show PausableBackend;
import 'tts_reader_sequence_test.dart' show until;

class PageNavigationBackend extends PausableBackend {
  @override
  Future<void> dispose() => stop();
  @override
  String? get playbackError => null;
  @override
  Future<void> next({FutureOr<dynamic> Function()? locate}) async {
    await locate?.call();
  }

  @override
  Future<void> prev({FutureOr<dynamic> Function()? locate}) async {
    await locate?.call();
  }
}

class DocumentPlayerWithoutDatabase extends EpubPlayerState {
  @override
  bool get mounted => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    OnlineTts.clearCachedAudio();
  });

  test('selection seeks to its sentence and stops at the same page end', () {
    const text = '第一句。\n\n𠀀第二句！第三句？';
    final page = TtsPageSource(text, chapter: 'Page 4');
    page.seekToOffset(text.indexOf('第二'));
    expect(page.currentText(), '𠀀第二句！');
    expect(page.collect(10).map((s) => s.text), ['𠀀第二句！', '第三句？']);
    expect(page.nextText(), '第三句？');
    expect(page.nextText(), isEmpty);
    page.seekToOffset(4); // Whitespace before the next sentence.
    expect(page.currentText(), '𠀀第二句！');
    page.seekToOffset(0);
    expect(page.currentText(), '第一句。');
    page.invalidate();
    page.seekToOffset(text.indexOf('第三'));
    expect(page.currentText(), isEmpty);
  });

  test('page cursor bounds, prefetch snapshots, replay and invalidation', () {
    final positions = <int>[];
    final page = TtsPageSource('第一句。第二句！\n\n第三句？',
        chapter: 'Page 4', onPosition: positions.add);
    expect(page.previousText(), '第一句。');
    expect(page.collect(100).map((s) => s.text), ['第一句。', '第二句！', '第三句？']);
    expect(positions, [0]); // Prefetch never moves the visual/speech cursor.
    expect(page.collect(3).map((s) => s.endsParagraph), [false, true, true]);
    expect(page.nextText(), '第二句！');
    expect(page.nextText(), '第三句？');
    expect(page.nextText(), '');
    expect(page.nextText(), '');
    expect(page.collect(5), isEmpty);
    expect(page.previousText(), '第三句？');
    page.nextText();
    expect(page.currentText(), '第一句。');
    page.invalidate();
    expect(page.currentText(), '');
    expect(page.previousText(), '');
    expect(page.nextText(), '');
    expect(page.collect(5), isEmpty);
    page.rewind();
    expect(page.valid, isFalse);
  });

  test('highlight uses exact UTF-16 ranges and prefetch never moves it', () {
    const text = '  𠀀第一句。\n\n𠀀第一句。末句！';
    final ranges = <TextRange?>[];
    final source = TtsPageSource(text, chapter: '', onHighlight: ranges.add);
    source.currentText();
    expect(ranges.single, const TextRange(start: 2, end: 8));
    source.collect(5);
    expect(ranges.length, 1);
    source.nextText();
    expect(ranges.last, const TextRange(start: 10, end: 16));
    source.previousText();
    expect(ranges.last!.textInside(text), '𠀀第一句。');
    source.nextText();
    source.nextText();
    source.nextText();
    expect(ranges.last, isNull);
    source.currentText();
    expect(ranges.last, isNotNull);
    source.invalidate();
    expect(ranges.last, isNull);
    final count = ranges.length;
    source.showCurrent();
    expect(ranges.length, count);
  });

  for (final mode in [DocumentReadingMode.pdf, DocumentReadingMode.imageEpub]) {
    test('$mode neither persists nor restores narration state', () async {
      // No progress database/WebView is initialized: either access must fail.
      final reader = DocumentPlayerWithoutDatabase();
      reader.documentReadingMode.value = mode;
      for (final state in TtsStateEnum.values) {
        await reader.recordNarrationState(state);
      }
      await reader.restoreNarration(
          const NarrationPosition('epubcfi(/6/2!/4/2)', 'paused'));
      await reader.restoreNarration(null);
    });
  }

  test('changing provider retains the page-local source and invalidation',
      () async {
    final backends = <PageNavigationBackend>[];
    final factory = TtsFactory.forTesting(() {
      final backend = PageNavigationBackend();
      backends.add(backend);
      return backend;
    });
    final handler = TtsHandler.forTesting(
        factory: factory,
        activateSession: () async => true,
        deactivateSession: () async {});
    final source = TtsPageSource('本页。', chapter: 'Page 3');
    await handler.init(source.currentText, source.nextText, source.previousText,
        pageSource: source);
    final previous = handler.tts;
    await handler
        .switchTtsType(Prefs().ttsService == 'edge' ? 'system' : 'edge');
    expect(handler.tts, isNot(same(previous)));
    expect(handler.tts.pageSource, same(source));
    source.invalidate();
    await handler.play();
    expect(backends.last.resumes, 0);
    await handler.stop();
  });

  test('empty text and long OCR runs are safe, including non-BMP characters',
      () {
    expect(TtsPageSource(' \n ', chapter: '').valid, isFalse);
    final text = List.filled(1201, '𠀀').join();
    final source = TtsPageSource(text, chapter: '');
    final parts = source.collect(100);
    expect(parts.map((s) => s.text).join(), text);
    expect(parts.map((s) => s.text.runes.length), [500, 500, 201]);
    expect(parts.map((s) => s.endsParagraph), [false, false, true]);
  });

  test('online prefetch and presentation never consult the original reader',
      () async {
    const text = '校对第一句。第二句。';
    TextRange? highlighted;
    final page = TtsPageSource(text,
        chapter: 'Page 3', onHighlight: (range) => highlighted = range);
    final played = <String>[];
    final requested = <String>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async => throw StateError('original reader collection'),
      highlight: (_) async => fail('original reader highlight'),
      followProgress: (_, fraction) async => fail('original reader follow'),
      synthesize: (text) async {
        requested.add(text);
        return Uint8List.fromList([1]);
      },
      play: (segment) async {
        expect(highlighted?.textInside(text), segment.sentence.text);
        played.add(segment.sentence.text);
      },
    )..pageSource = page;
    addTearDown(tts.stop);
    await tts.init(page.currentText, page.nextText, page.previousText);
    await tts.speak().timeout(const Duration(seconds: 5));
    expect(played, ['校对第一句。', '第二句。']);
    expect(requested, played);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
    expect(page.collect(10), isEmpty);
    expect(highlighted, isNull);
    await tts.speak().timeout(const Duration(seconds: 5));
    expect(played, ['校对第一句。', '第二句。', '校对第一句。', '第二句。']);
  });

  test('online playback continues through new page text without restarting',
      () async {
    var pageNumber = 0;
    final source = TtsPageSource('第一页。', chapter: '1',
        onNextPage: (source, current) async {
      if (pageNumber == 1) return false;
      pageNumber++;
      source.replacePage('第二页。末句。', chapter: '2');
      return true;
    });
    final played = <String>[];
    final tts = OnlineTts.forTesting(
        collect: (_) async => throw StateError('original reader'),
        synthesize: (_) async => Uint8List.fromList([1]),
        play: (segment) async => played.add(segment.sentence.text))
      ..pageSource = source;
    addTearDown(tts.stop);
    await tts.init(
        source.currentText, source.nextTextContinuous, source.previousText);
    await tts.speak().timeout(const Duration(seconds: 5));
    expect(played, ['第一页。', '第二页。', '末句。']);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
  });

  for (final stop in [false, true]) {
    test('page loading respects ${stop ? "stop" : "pause and resume"}',
        () async {
      final gate = Completer<void>();
      var loading = false, loaded = false;
      final source = TtsPageSource('第一页。', chapter: '1',
          onNextPage: (source, current) async {
        if (loaded) return false;
        loading = true;
        await gate.future;
        if (!current()) return false;
        loaded = true;
        source.replacePage('第二页。', chapter: '2');
        return true;
      });
      final played = <String>[];
      final tts = OnlineTts.forTesting(
          collect: (_) async => throw StateError('original reader'),
          synthesize: (_) async => Uint8List.fromList([1]),
          play: (segment) async => played.add(segment.sentence.text))
        ..pageSource = source;
      addTearDown(tts.stop);
      await tts.init(
          source.currentText, source.nextTextContinuous, source.previousText);
      final speaking = tts.speak();
      await until(() => loading);
      if (stop) {
        // Stop must complete even when extraction never resolves.
        await tts.stop().timeout(const Duration(seconds: 2));
        gate.complete();
        await speaking;
        expect(loaded, isFalse);
        expect(played, ['第一页。']);
      } else {
        await tts.pause();
        gate.complete();
        await until(() => loaded);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
        expect(played, ['第一页。']);
        await tts.resume();
        await speaking.timeout(const Duration(seconds: 5));
        expect(played, ['第一页。', '第二页。']);
      }
    });
  }

  test('system narration automatically reads the next original page', () async {
    final spoken = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments is String
            ? call.arguments as String
            : call.arguments['text'] as String);
      }
      return 1;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null));
    var loaded = false;
    final source = TtsPageSource('第一页。', chapter: '1',
        onNextPage: (source, current) async {
      if (loaded) return false;
      loaded = true;
      source.replacePage('第二页。', chapter: '2');
      return true;
    });
    final tts = SystemTts.forTesting(supported: true)..pageSource = source;
    await tts.init(
        source.currentText, source.nextTextContinuous, source.previousText);
    tts.updateTtsState(TtsStateEnum.playing);
    await tts.speak();
    expect(spoken, ['第一页。', '第二页。']);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
    await tts.stop();
  });

  test('leaving page during online synthesis cancels late audio', () async {
    final page = TtsPageSource('尚在生成的本页。', chapter: '');
    final gate = Completer<Uint8List>();
    var started = false, played = false;
    final tts = OnlineTts.forTesting(
        collect: (_) async => throw StateError('original reader'),
        synthesize: (_) {
          started = true;
          return gate.future;
        },
        play: (_) async => played = true)
      ..pageSource = page;
    await tts.init(page.currentText, page.nextText, page.previousText);
    final speaking = tts.speak();
    await until(() => started);
    page.invalidate();
    await tts.stop();
    gate.complete(Uint8List.fromList([1]));
    await speaking;
    expect(played, isFalse);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
  });

  test('system speech ends at the same page boundary', () async {
    final spoken = <String>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'speak') {
        spoken.add(call.arguments is String
            ? call.arguments as String
            : call.arguments['text'] as String);
      }
      return 1;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), null));
    final page = TtsPageSource('本页开头。本页结尾。', chapter: '');
    final tts = SystemTts.forTesting(supported: true)..pageSource = page;
    await tts.init(page.currentText, page.nextText, page.previousText);
    tts.updateTtsState(TtsStateEnum.playing);
    await tts.speak();
    expect(spoken, ['本页开头。', '本页结尾。']);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
    await tts.stop();
  });

  test(
      'page session reuses media pause/resume and never stops the original cursor',
      () async {
    final backend = PausableBackend();
    var originalStops = 0, activations = 0;
    final handler = TtsHandler.forTesting(
        factory: TtsFactory.forTesting(() => backend),
        activateSession: () async {
          activations++;
          return true;
        },
        deactivateSession: () async {},
        stopReader: () async => originalStops++);
    TextRange? highlighted;
    final page = TtsPageSource('本页。',
        chapter: 'Original page 3',
        onHighlight: (range) => highlighted = range);
    await handler.init(page.currentText, page.nextText, page.previousText,
        pageSource: page);
    handler.mediaItem.add(ttsMediaItem(
        bookId: '1',
        title: 'Book',
        author: '',
        chapter: page.chapter,
        coverPath: '',
        state: TtsStateEnum.paused));
    await handler.play();
    page.showCurrent();
    expect(highlighted, isNotNull);
    expect(backend.resumes, 1);
    expect(handler.playbackState.value.controls.map((c) => c.action),
        contains(MediaAction.pause));
    handler.updateChapter(bookId: 1, chapter: 'Underlying original chapter');
    expect(handler.mediaItem.value?.extras?['ttsChapter'], page.chapter);
    await handler.pause();
    expect(highlighted, isNotNull);
    expect(handler.playbackState.value.controls.map((c) => c.action),
        contains(MediaAction.play));
    await handler.play();
    expect(backend.resumes, 2);
    await handler.stop();
    expect(highlighted, isNull);
    page.invalidate();
    await handler.play();
    expect(activations, 2);
    expect(originalStops, 0);
    backend.reading.complete();
    await handler.init(() => 'ebook', () => '', () => '');
    expect(backend.pageSource, isNull);
    await handler.stop();
    expect(originalStops, 1);
  });

  test(
      'notification next/previous stay in page and return without awaiting speech',
      () async {
    final backend = PageNavigationBackend();
    final handler = TtsHandler.forTesting(
        factory: TtsFactory.forTesting(() => backend),
        activateSession: () async => true,
        deactivateSession: () async {},
        stopReader: () async => fail('must not change original page'));
    final source = TtsPageSource('第一句。末句。', chapter: 'Page 1');
    await handler.init(source.currentText, source.nextText, source.previousText,
        pageSource: source);
    handler.mediaItem.add(ttsMediaItem(
        bookId: '1',
        title: 'Book',
        author: '',
        chapter: source.chapter,
        coverPath: '',
        state: TtsStateEnum.paused));
    await handler.play();
    await handler.skipToNext().timeout(const Duration(seconds: 1));
    expect(source.collect(1).single.text, '末句。');
    expect(backend.isPlaying, isTrue);
    await handler.skipToPrevious().timeout(const Duration(seconds: 1));
    expect(source.collect(1).single.text, '第一句。');
    expect(backend.isPlaying, isTrue);
    await handler.pause();
    await handler.skipToNext();
    expect(backend.ttsStateNotifier.value, TtsStateEnum.paused);
    await handler.skipToNext();
    expect(backend.ttsStateNotifier.value, TtsStateEnum.stopped);
    expect(source.atEnd, isTrue);
    expect(handler.mediaItem.value, isNull);
    backend.reading.complete();
  });
}
