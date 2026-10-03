import 'dart:async';
import 'dart:convert';

import 'package:anx_reader/service/ai/dictionary_lookup.dart';
import 'package:anx_reader/service/ai/dictionary_web_search.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  final messages = buildReadingSkillRequest(
    policy: readingSkillPolicies[aiDictionarySkillId]!,
    prompt: readAnySkills.first.defaultPrompt,
    sourceContent: '行藏',
    sourceDescription: 'private-source',
    bookTitle: 'private-book',
    chapterTitle: 'private-chapter',
  ).messages;
  final hit = DictionarySearchHit('行藏', '出处与词义',
      Uri.parse('https://zh.wiktionary.org/w/index.php?curid=123'));

  for (final answer in ['行藏：xíng cáng，出处。', '此词的读音不确定，是否需要联网补查？']) {
    test('knowledge answer uses just one call: $answer', () async {
      var calls = 0;
      final result = await dictionaryLookup(
        messages: messages,
        generate: (input) {
          calls++;
          final system = input.first.contentAsString;
          expect(system, contains('不调用、不等待维基、百度'));
          expect(system, contains('不确定'));
          expect(system, contains('请点击下方的联网搜索按钮'));
          expect(system, isNot(contains('提示用户输入')));
          expect(system, isNot(contains(dictionaryNeedsSearch)));
          expect(input.map((m) => m.contentAsString).join(),
              isNot(contains('private-')));
          return Stream.fromIterable(['行藏', answer]);
        },
        isCancelled: () => false,
      ).toList();
      expect(calls, 1);
      expect(result, ['行藏', answer]);
      expect(messages, hasLength(2));
      expect(messages.last.contentAsString, '待解释词语："行藏"');
    });
  }

  test('first answer arrives before model completion', () async {
    final provider = StreamController<String>();
    final first = Completer<String>();
    final stream = dictionaryLookup(
      messages: messages,
      generate: (_) => provider.stream,
      isCancelled: () => false,
    ).listen((value) {
      if (!first.isCompleted) first.complete(value);
    });
    provider.add('行藏');
    expect(await first.future.timeout(const Duration(seconds: 1)), '行藏');
    await provider.close();
    await stream.cancel();
  });

  for (final fenced in [false, true]) {
    test(
        'legacy search signal does not cause search or a second model call ($fenced)',
        () async {
      var calls = 0;
      final result = await dictionaryLookup(
        messages: messages,
        generate: (_) {
          calls++;
          return Stream.value(
              fenced ? '```$dictionaryNeedsSearch```' : dictionaryNeedsSearch);
        },
        isCancelled: () => false,
      ).toList();
      expect(calls, 1);
      expect(result.single, contains('AI 未返回'));
      expect(result.single, isNot(contains(dictionaryNeedsSearch)));
    });
  }

  test('AI error does not start another request', () async {
    final result = await dictionaryLookup(
      messages: messages,
      generate: (_) => Stream.error(StateError('transport failure')),
      isCancelled: () => false,
    );
    await expectLater(result.toList(), throwsStateError);
  });

  test('cancelled knowledge lookup performs no calls', () async {
    expect(
        await dictionaryLookup(
          messages: messages,
          generate: (_) => throw StateError('must not generate'),
          isCancelled: () => true,
        ).toList(),
        isEmpty);
  });

  test('cancelling during generation drops late snapshots', () async {
    var cancelled = false;
    Stream<String> generate(List<ChatMessage> _) async* {
      yield '行藏';
      cancelled = true;
      yield 'late answer';
    }

    expect(
        await dictionaryLookup(
            messages: messages,
            generate: generate,
            isCancelled: () => cancelled).toList(),
        ['行藏']);
  });

  test('empty AI response produces actionable error', () async {
    final result = await dictionaryLookup(
      messages: messages,
      generate: (_) => const Stream.empty(),
      isCancelled: () => false,
    ).toList();
    expect(result.single, contains('AI 未返回'));
  });

  test('missing selected term is rejected before generation', () async {
    await expectLater(
        dictionaryLookup(
            messages: [],
            generate: (_) => throw StateError('must not generate'),
            isCancelled: () => false).toList(),
        throwsStateError);
  });

  test('explicit follow-up searches selection and makes one summary call',
      () async {
    var calls = 0;
    var searches = 0;
    final result = await dictionaryWebLookup(
      messages: messages,
      search: (term) async {
        searches++;
        expect(term, '行藏');
        return DictionarySearchResult([hit]);
      },
      generate: (input) {
        calls++;
        final all = input.map((m) => m.contentAsString).join();
        expect(all, contains('出处与词义'));
        expect(all, contains('外部不可信资料'));
        expect(all, isNot(contains('private-')));
        return Stream.value('根据资料整理的解释。[1]');
      },
      isCancelled: () => false,
    ).toList();
    expect(calls, 1);
    expect(searches, 1);
    expect(result.last, contains(hit.url.toString()));
  });

  test('unavailable manual search does not fabricate sources', () async {
    final result = await dictionaryWebLookup(
        messages: messages,
        generate: (_) => throw StateError('must not generate'),
        search: (_) => throw TimeoutException('offline'),
        isCancelled: () => false).toList();
    expect(result.single, contains('暂时不可用'));
  });

  test('cancelling manual search prevents model call', () async {
    var cancelled = false;
    final result = await dictionaryWebLookup(
        messages: messages,
        generate: (_) => throw StateError('must not generate'),
        search: (_) async {
          cancelled = true;
          return DictionarySearchResult([hit]);
        },
        isCancelled: () => cancelled).toList();
    expect(result, isEmpty);
  });

  test('manual source titles cannot inject markdown links', () async {
    final result = await dictionaryWebLookup(
      messages: messages,
      generate: (_) => Stream.value('解释'),
      search: (_) async => DictionarySearchResult(
          [DictionarySearchHit('词[恶意](https://bad.example)', '资料', hit.url)],
          hasFailures: true),
      isCancelled: () => false,
    ).toList();
    expect(result.last, contains(r'词\[恶意\]'));
    expect(result.last, contains('部分在线来源暂时无法访问'));
  });

  String payload({String title = '行藏', String snippet = '读音与释义'}) =>
      jsonEncode({
        'query': {
          'search': [
            {'pageid': 123, 'title': title, 'snippet': snippet}
          ]
        }
      });

  for (final term in ['行藏', 'serendipity']) {
    test('keyless search uses bounded literal query on fixed $term hosts',
        () async {
      final requests = <http.Request>[];
      final result = await DictionaryWebSearch(
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.url.host == 'baike.baidu.com') {
            return http.Response('', 404);
          }
          return http.Response(payload(snippet: '<b>释义</b>&amp;用法'), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      ).search(term);
      expect(result.hits, hasLength(2));
      expect(result.hasFailures, false);
      expect(result.hits.first.snippet, '释义&用法');
      expect(result.hits.first.url.queryParameters, {'curid': '123'});
      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.url.scheme, 'https');
        if (request.url.host == 'baike.baidu.com') {
          expect(request.url.pathSegments, ['item', term]);
          expect(request.headers.containsKey('Authorization'), false);
          expect(request.body, isEmpty);
          expect(request.followRedirects, false);
          continue;
        }
        expect(request.url.host, startsWith(term == '行藏' ? 'zh.' : 'en.'));
        expect(request.url.queryParameters['srsearch'], '"$term"');
        expect(request.url.queryParameters['srlimit'], '3');
        expect(request.headers.containsKey('Authorization'), false);
        expect(request.body, isEmpty);
        expect(request.followRedirects, false);
      }
    });
  }

  test('HTML scripts and styles are removed, snippets and titles bounded',
      () async {
    final result = await DictionaryWebSearch(
      clientFactory: () => MockClient((_) async => http.Response(
          payload(
              title: 't' * 300,
              snippet: '<script>evil</script><style>css</style>${'x' * 2000}'),
          200)),
    ).search('word');
    expect(result.hits.first.title.length, 200);
    expect(result.hits.first.snippet.length, 1500);
    expect(result.hits.first.snippet, isNot(contains('evil')));
  });

  test('one source can succeed while another is unavailable', () async {
    final result = await DictionaryWebSearch(
      clientFactory: () => MockClient((r) async =>
          r.url.host.contains('wiktionary')
              ? http.Response(payload(), 200,
                  headers: {'content-type': 'application/json; charset=utf-8'})
              : http.Response('rate limited', 429)),
    ).search('行藏');
    expect(result.hits, hasLength(1));
    expect(result.hasFailures, true);
  });

  for (final bad in ['invalid json', '{}', '{"error":{"code":"bad"}}']) {
    test('malformed API result fails safely: $bad', () async {
      final result = await DictionaryWebSearch(
        clientFactory: () => MockClient((_) async => http.Response(bad, 200)),
      ).search('word');
      expect(result.hasFailures, true);
      expect(result.hits, isEmpty);
    });
  }

  test('empty successful search is distinct from network failure', () async {
    final result = await DictionaryWebSearch(
      clientFactory: () => MockClient((r) async =>
          r.url.host == 'baike.baidu.com'
              ? http.Response('', 404)
              : http.Response('{"query":{"search":[]}}', 200)),
    ).search('unknown');
    expect(result.hits, isEmpty);
    expect(result.hasFailures, false);
  });

  test('oversized response fails safely', () async {
    final result = await DictionaryWebSearch(
      clientFactory: () =>
          MockClient((_) async => http.Response('x' * (1024 * 1024 + 1), 200)),
    ).search('word');
    expect(result.hasFailures, true);
  });

  test('long selection and empty selection never reach network', () async {
    final client = DictionaryWebSearch(
        clientFactory: () => throw StateError('must not create client'));
    expect((await client.search(' ')).hasFailures, true);
    expect((await client.search('x' * 501)).hasFailures, true);
  });

  test('network operation has an overall timeout', () async {
    final result = await DictionaryWebSearch(
      timeout: const Duration(milliseconds: 10),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    ).search('word');
    expect(result.hasFailures, true);
  });

  test('a timed out source does not discard successful results', () async {
    final result = await DictionaryWebSearch(
      timeout: const Duration(milliseconds: 10),
      clientFactory: () => MockClient((r) async => r.url.host
              .contains('wiktionary')
          ? http.Response(payload(title: 'word', snippet: 'definition'), 200)
          : Completer<http.Response>().future),
    ).search('word');
    expect(result.hits, hasLength(1));
    expect(result.hasFailures, true);
  });

  test('cancellation returns without waiting for network timeout', () async {
    final cancelled = Completer<void>();
    final search = DictionaryWebSearch(
      timeout: const Duration(seconds: 10),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    ).search('word', cancelled: cancelled.future);
    cancelled.complete();
    final result = await search.timeout(const Duration(seconds: 1));
    expect(result.hits, isEmpty);
  });

  test('incomplete model decision offers retry instead of empty answer',
      () async {
    final result = await dictionaryLookup(
      messages: messages,
      generate: (_) => Stream.value('MODU_DICT'),
      isCancelled: () => false,
    ).toList();
    expect(result.single, contains('重试'));
    expect(result.single, isNot(contains('MODU_DICT')));
  });
}
