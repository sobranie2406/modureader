import 'dart:async';

import 'package:anx_reader/service/ai/dictionary_lookup.dart';
import 'package:anx_reader/service/ai/dictionary_web_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langchain_core/chat_models.dart';

const entry = '''<html><head><title>行藏_百度百科</title>
<meta name="description" content="行藏，汉语词语，拼音为xíng cáng。&amp;用法。">
<link rel="canonical" href="https://baike.baidu.com/item/行藏/123">
</head><body><h1>行藏</h1></body></html>''';

http.Response page(String body, [int status = 200]) =>
    http.Response(body, status,
        headers: {'content-type': 'text/html; charset=utf-8'});

void main() {
  Future<DictionarySearchResult> search(
      Future<http.Response> Function(http.Request) baidu) {
    return DictionaryWebSearch(
      clientFactory: () => MockClient((request) async =>
          request.url.host == 'baike.baidu.com'
              ? baidu(request)
              : http.Response('{"query":{"search":[]}}', 200)),
    ).search('行藏');
  }

  test('public Baike summary is returned with a real source label and URL',
      () async {
    final result = await search((request) async {
      expect(request.url.pathSegments, ['item', '行藏']);
      expect(request.body, isEmpty);
      expect(request.headers.containsKey('authorization'), false);
      expect(request.followRedirects, false);
      return page(entry);
    });
    expect(result.hasFailures, false);
    final hit = result.hits.single;
    expect(hit.title, '行藏');
    expect(hit.snippet, contains('xíng cáng'));
    expect(hit.snippet, contains('&用法'));
    expect(hit.url.host, 'baike.baidu.com');
    expect(hit.url.pathSegments, ['item', '行藏', '123']);
    expect(hit.sourceName, '百度百科');
    expect(hit.toJson()['site'], '百度百科');
  });

  test('same-host HTTPS entry redirect resolves at most two hops', () async {
    var requests = 0;
    final result = await search((request) async {
      requests++;
      return requests == 1
          ? http.Response('', 302, headers: {'location': '/item/行藏/123'})
          : page(entry);
    });
    expect(requests, 2);
    expect(result.hits, hasLength(1));
  });

  for (final location in [
    'https://wappass.baidu.com/verify',
    'https://evil.example/item/行藏',
    'http://baike.baidu.com/item/行藏',
    'https://baike.baidu.com:8443/item/行藏',
    'https://baike.baidu.com/login',
    'https://user@baike.baidu.com/item/行藏',
  ]) {
    test('never follows unsafe/challenge redirect: $location', () async {
      var requests = 0;
      final result = await search((_) async {
        requests++;
        return http.Response('', 302, headers: {'location': location});
      });
      expect(requests, 1);
      expect(result.hasFailures, true);
      expect(result.hits, isEmpty);
    });
  }

  for (final challenge in [
    '<title>百度安全验证</title><meta name="description" content="验证后继续">',
    '$entry<script>window.BIOC_OPTIONS={};</script>',
    '$entry<script src="https://example.com/captcha.js"></script>',
    '<title>百度百科_全球领先的中文百科全书</title>',
    '<title>词语_百度百科</title>',
  ]) {
    test('challenge or incomplete HTML is not sent as encyclopedia evidence',
        () async {
      final result = await search((_) async => page(challenge));
      expect(result.hits, isEmpty);
      expect(result.hasFailures, true);
    });
  }

  test('404 is no entry; 403 and 429 are unavailable', () async {
    expect((await search((_) async => page('', 404))).hasFailures, false);
    for (final code in [403, 429]) {
      final result = await search((_) async => page('', code));
      expect(result.hasFailures, true);
      expect(result.hits, isEmpty);
    }
  });

  test('does not use a foreign canonical URL', () async {
    final result = await search((_) async => page(entry.replaceAll(
        'https://baike.baidu.com/item/行藏/123', 'https://evil.example/stolen')));
    expect(result.hits.single.url.host, 'baike.baidu.com');
  });

  test('redirect loop is bounded', () async {
    var requests = 0;
    final result = await search((_) async {
      requests++;
      return http.Response('', 302, headers: {'location': '/item/行藏/123'});
    });
    expect(requests, 3);
    expect(result.hasFailures, true);
  });

  test('slow Baike does not discard Wikimedia results', () async {
    final result = await DictionaryWebSearch(
      timeout: const Duration(milliseconds: 10),
      clientFactory: () => MockClient((r) async =>
          r.url.host == 'baike.baidu.com'
              ? Completer<http.Response>().future
              : http.Response('''{"query":{"search":[
                  {"pageid":123,"title":"word","snippet":"meaning"}]}}''',
                  200)),
    ).search('word');
    expect(result.hits, hasLength(2));
    expect(result.hasFailures, true);
  });

  test('Baidu evidence goes to current model; only fetched sources are listed',
      () async {
    final evidence = await search((_) async => page(entry));
    var calls = 0;
    final result = await dictionaryWebLookup(
      messages: [
        ChatMessage.system('解释词语'),
        ChatMessage.humanText('待解释词语："行藏"')
      ],
      generate: (messages) {
        calls++;
        expect(messages.last.contentAsString, contains('百度百科'));
        expect(messages.last.contentAsString, contains('xíng cáng'));
        return Stream.value('整理后的解释。[1]');
      },
      search: (term) async => evidence,
      isCancelled: () => false,
    ).toList();
    expect(calls, 1);
    expect(result.last, contains('（百度百科）'));
    expect(result.last, contains('https://baike.baidu.com/item/'));
    expect(result.last, isNot(contains('维基词典')));
  });
}
