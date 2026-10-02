import 'dart:io';

import 'package:anx_reader/service/book_player/reader_word_selection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.modu.reader/word_selection');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  Object? response;
  Map<String, Object?> request(String text, int offset) =>
      {'text': text, 'offset': offset, 'locale': 'zh-CN'};

  setUp(() {
    calls.clear();
    response = [3, 5];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return response;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
      'system bridge receives a bounded paragraph and returns UTF-16 word positions',
      () async {
    expect(await ReaderWordSelection.bounds(request('我喜欢中国文化。', 3)), [3, 5]);
    expect(calls.single.method, 'bounds');
    expect(calls.single.arguments, request('我喜欢中国文化。', 3));
    response = [3, 5];
    expect(await ReaderWordSelection.bounds(request('😀 中国。', 4)), [3, 5]);
    response = [0, 5];
    expect(await ReaderWordSelection.bounds(request('hello', 5)), [0, 5]);
  });

  test('invalid and oversized WebView input never reaches the native channel',
      () async {
    for (final invalid in [
      null,
      [],
      {},
      request('', 0),
      request('中国', -1),
      request('中国', 3),
      request('中' * 65537, 0),
      {'text': '中国', 'offset': 0.5},
      {'text': '中国', 'offset': 0, 'locale': []},
      {'text': '中国', 'offset': 0, 'locale': 'z' * 129}
    ]) {
      expect(await ReaderWordSelection.bounds(invalid), isNull);
    }
    expect(calls, isEmpty);
  });

  test('malformed or unrelated native bounds are ignored', () async {
    for (final value in [
      null,
      {},
      [],
      [3],
      [3, 5, 6],
      [-1, 5],
      [3, 99],
      [3, 3],
      [0, 1],
      [3.0, 5],
      ['3', 5]
    ]) {
      response = value;
      expect(await ReaderWordSelection.bounds(request('我喜欢中国文化。', 3)), isNull);
    }
  });

  test('missing plugin, platform error and timeout do not interrupt reading',
      () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await ReaderWordSelection.bounds(request('中国', 0)), isNull);
    messenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'unavailable'));
    expect(await ReaderWordSelection.bounds(request('中国', 0)), isNull);
    messenger.setMockMethodCallHandler(
        channel,
        (_) => Future<Object?>.delayed(
            const Duration(milliseconds: 500), () => [0, 2]));
    expect(await ReaderWordSelection.bounds(request('中国', 0)), isNull);
  });

  test(
      'Android native fallback uses ICU word boundaries and filters punctuation',
      () {
    final source = File(
            'android/app/src/main/kotlin/com/modu/reader/ReaderWordSelection.java')
        .readAsStringSync();
    expect(source, contains('android.icu.text.BreakIterator'));
    expect(source, contains('BreakIterator.getWordInstance(locale)'));
    expect(source, contains('iterator.following(index)'));
    expect(source,
        contains('iterator.getRuleStatus() < BreakIterator.WORD_NONE_LIMIT'));
    expect(source, contains('iterator.previous()'));
    expect(source, contains('text.length() > 65536'));
    final activity =
        File('android/app/src/main/kotlin/com/modu/reader/MainActivity.kt')
            .readAsStringSync();
    expect(activity, contains('com.modu.reader/word_selection'));
    expect(activity, contains('ReaderWordSelection.bounds('));
    final reader =
        File('lib/page/book_player/epub_player.dart').readAsStringSync();
    expect(reader, contains("handlerName: 'onReaderWordBounds'"));
    expect(
        reader, contains('!mounted || !AnxPlatform.isAndroid || args.isEmpty'));
  });
}
