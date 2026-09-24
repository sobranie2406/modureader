import 'dart:async';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/tts/base_tts.dart';
import 'package:anx_reader/service/tts/models/tts_sentence.dart';
import 'package:anx_reader/service/tts/online_tts.dart';
import 'package:anx_reader/service/tts/tts_text_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('only punctuation, whitespace and control separators are silent', () {
    for (final text in [
      '',
      '……',
      '...',
      '⋯⋯',
      '——',
      '！？「」',
      ' \n\t\u3000',
      '\u200b…\ufeff'
    ]) {
      expect(isTtsSeparator(text), isTrue, reason: text);
    }
    for (final text in [
      '等等……',
      '…hello',
      '123',
      '١٢٣',
      'é',
      'Привет',
      'مرحبا',
      'हिन्दी',
      '𠀀',
      'x + y',
      '+',
      '=',
      '🙂'
    ]) {
      expect(isTtsSeparator(text), isFalse, reason: text);
    }
  });

  test('separators advance in order across batches and chapter boundaries',
      () async {
    final chapters = [
      ['……', '正文第一句', '...', '——', '正文第二句', '……'],
      ['……', '……'],
      ['下一章标题', '后续正文', '……'],
    ];
    var chapter = 0, cursor = 0, advances = 0;
    final fetched = <String>[], played = <String>[];
    final tts = OnlineTts.forTesting(
      collect: (_) async => chapters[chapter]
          .skip(cursor)
          .take(2)
          .map((text) => TtsSentence(text: text))
          .toList(),
      synthesize: (text) async {
        fetched.add(text);
        return Uint8List.fromList([1]);
      },
      play: (segment) async => played.add(segment.sentence.text),
    );
    addTearDown(tts.stop);
    await tts.init(() async => chapters[chapter][cursor], () async {
      advances++;
      if (++cursor == chapters[chapter].length) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        chapter++;
        cursor = 0;
      }
      return chapter == chapters.length ? '' : chapters[chapter][cursor];
    }, () async => '');
    await tts.speak().timeout(const Duration(seconds: 5));
    final expected = ['正文第一句', '正文第二句', '下一章标题', '后续正文'];
    expect(fetched, expected);
    expect(played, expected);
    expect(advances, chapters.expand((c) => c).length);
    expect(tts.playbackError, isNull);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
  });

  test('a punctuation-only book ends without audio requests or errors',
      () async {
    final sentences = ['……', '...', '——'];
    var cursor = 0;
    final tts = OnlineTts.forTesting(
      collect: (_) async => sentences
          .skip(cursor)
          .map((text) => TtsSentence(text: text))
          .toList(),
      synthesize: (_) async => throw StateError('Must not request audio'),
      play: (_) async => fail('Must not play audio'),
    );
    addTearDown(tts.stop);
    await tts.init(() async => sentences[cursor], () async {
      cursor++;
      return cursor == sentences.length ? '' : sentences[cursor];
    }, () async => '');
    await tts.speak().timeout(const Duration(seconds: 5));
    expect(cursor, sentences.length);
    expect(tts.playbackError, isNull);
    expect(tts.ttsStateNotifier.value, TtsStateEnum.stopped);
  });

  for (final emptyAudio in [true, false]) {
    test('real text failure after a separator is retained (empty=$emptyAudio)',
        () async {
      final sentences = ['……', '不能跳过的正文', '下一句'];
      var cursor = 0, attempts = 0;
      final tts = OnlineTts.forTesting(
        collect: (_) async => [TtsSentence(text: sentences[cursor])],
        synthesize: (_) async {
          attempts++;
          if (emptyAudio) return Uint8List(0);
          throw StateError('Network unavailable');
        },
        play: (_) async => fail('No valid audio'),
      );
      addTearDown(tts.stop);
      await tts.init(() async => sentences[cursor],
          () async => sentences[++cursor], () async => '');
      await tts.speak().timeout(const Duration(seconds: 5));
      expect(cursor, 1);
      expect(attempts, 3);
      expect(tts.playbackError, isNotNull);
      expect(tts.ttsStateNotifier.value, TtsStateEnum.paused);
    });
  }
}
