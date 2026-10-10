import 'dart:convert';
import 'dart:typed_data';

import 'package:anx_reader/service/dictionary/online_dictionary.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> wikiFixture() => {
      'parse': {
        'title': 'hello',
        'revid': 123,
        'text': '<div class="mw-parser-output"><h2>English</h2><h3>Noun</h3>'
            '<ol><li>A <b>greeting</b>.<dl><dd>Copyrighted example.</dd></dl>'
            '<script>evil()</script><sup>1</sup></li></ol>'
            '<h2>Other language</h2><h3>Verb</h3><ol><li>To greet.</li></ol>'
            '<ol class="references"><li>Reference, not a definition.</li></ol></div>'
      }
    };

class DictionaryAdapter implements HttpClientAdapter {
  DictionaryAdapter(this.data, {this.status = 200});
  Object data;
  int status;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('Wiktionary excerpts remove markup, quotations and preserve attribution',
      () {
    final entry =
        parseWiktionary(wikiFixture(), OnlineDictionary.wiktionaryEn).single;
    expect(entry.definition, contains('English · Noun'));
    expect(entry.definition, contains('A greeting.'));
    expect(entry.definition, contains('Other language · Verb'));
    for (final removed in ['Copyrighted', 'evil', 'Reference', '<b>']) {
      expect(entry.definition, isNot(contains(removed)));
    }
    expect(entry.sourceUri!.queryParameters['oldid'], '123');
    expect(entry.license, 'CC BY-SA 4.0');
    expect(entry.attribution, 'Wiktionary contributors');
  });
  test('missing Wiktionary entry is not an outage; malformed responses fail',
      () {
    expect(
        parseWiktionary({
          'error': {'code': 'missingtitle'}
        }, OnlineDictionary.wiktionaryZh),
        isEmpty);
    expect(
        () => parseWiktionary({
              'error': {'code': 'maxlag'}
            }, OnlineDictionary.wiktionaryZh),
        throwsFormatException);
  });
  test('API encodes query, identifies app, caches and does not request media',
      () async {
    final adapter = DictionaryAdapter(wikiFixture());
    final service =
        OnlineDictionaryService(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(service.close);
    await service.lookup(OnlineDictionary.wiktionaryZh, '苹果 & 梨');
    await service.lookup(OnlineDictionary.wiktionaryZh, '苹果 & 梨');
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.uri.host, 'zh.wiktionary.org');
    expect(request.uri.queryParameters['page'], '苹果 & 梨');
    expect(request.headers['User-Agent'], contains('ModuReader'));
    expect(request.followRedirects, false);
  });
  test('invalid query sends no request', () async {
    final adapter = DictionaryAdapter(wikiFixture());
    final service =
        OnlineDictionaryService(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(service.close);
    expect(await service.lookup(OnlineDictionary.wiktionaryEn, ''), isEmpty);
    expect(await service.lookup(OnlineDictionary.wiktionaryEn, 'x' * 257),
        isEmpty);
    expect(adapter.requests, isEmpty);
  });
  test('404 is empty; rate limiting fails without retries or cached failures',
      () async {
    final adapter = DictionaryAdapter({}, status: 429);
    final service =
        OnlineDictionaryService(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(service.close);
    await expectLater(service.lookup(OnlineDictionary.wiktionaryEn, 'hello'),
        throwsA(isA<DioException>()));
    expect(adapter.requests, hasLength(1));
    adapter.status = 404;
    expect(
        await service.lookup(OnlineDictionary.wiktionaryEn, 'hello'), isEmpty);
  });
  test('oversized API response is rejected', () async {
    final adapter = DictionaryAdapter('x' * (2 * 1024 * 1024));
    final service =
        OnlineDictionaryService(dio: Dio()..httpClientAdapter = adapter);
    addTearDown(service.close);
    await expectLater(service.lookup(OnlineDictionary.wiktionaryEn, 'hello'),
        throwsFormatException);
  });
}
