import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/plugins/article_capture.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';

const _paragraph =
    'This is the article body, with enough useful text to distinguish it from navigation and menus.';
final _url = Uri.parse('https://example.com/news/story?article=1');
Matcher _failure(String code) =>
    throwsA(isA<ArticleCaptureFailure>().having((e) => e.code, 'code', code));

class _Headers extends Fake implements HttpHeaders {
  _Headers({String? mime = 'text/html; charset=utf-8', String? location}) {
    if (mime != null) values['content-type'] = mime;
    if (location != null) values['location'] = location;
  }
  final values = <String, String>{};
  @override
  ContentType? get contentType => values['content-type'] == null
      ? null
      : ContentType.parse(values['content-type']!);
  @override
  String? value(String name) => values[name.toLowerCase()];
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(String body,
      {this.statusCode = 200,
      String? location,
      String? mime = 'text/html; charset=utf-8',
      int? length})
      : _data = [utf8.encode(body)],
        headers = _Headers(mime: mime, location: location),
        contentLength = length ?? utf8.encode(body).length;
  _Response.stream(this._data)
      : statusCode = 200,
        headers = _Headers(),
        contentLength = -1;
  final Iterable<List<int>> _data;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  final int contentLength;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.fromIterable(_data).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  bool followRedirects = true;
  @override
  bool persistentConnection = true;
  @override
  final headers = _Headers(mime: null);
  @override
  final List<Cookie> cookies = [];
  @override
  Future<HttpClientResponse> close() => response;
}

class _Client extends Fake implements HttpClient {
  _Client(this.response);
  final Future<HttpClientResponse> response;
  Uri? requested;
  bool closed = false;
  _Request? request;
  @override
  String Function(Uri)? findProxy;
  @override
  Future<ConnectionTask<Socket>> Function(Uri, String?, int?)?
      connectionFactory;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested = url;
    return request = _Request(response);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

void main() {
  group('offline article extraction', () {
    test(
        'selects semantic article and removes page furniture and executable HTML',
        () {
      final article = extractArticle('''
        <title>Site title</title><meta property="og:title" content="An article">
        <nav><a href="/menu">Navigation</a></nav>
        <article><header><h1>An article</h1></header><p>$_paragraph</p>
        <script>alert('secret')</script><style>.x{}</style>
        <div class="advertisement">ADVERTISEMENT</div><aside>SIDEBAR</aside>
        <div id="comments">COMMENT</div><div class="related">RECOMMENDED</div>
        <div hidden>HIDDEN</div><div style="display:none">INVISIBLE</div></article>
        <footer>FOOTER</footer>''', _url);
      expect(article.title, 'An article');
      expect(article.markdown, contains(_paragraph));
      expect(article.markdown, startsWith('# An article\n'));
      for (final removed in [
        'Navigation',
        'secret',
        'ADVERTISEMENT',
        'SIDEBAR',
        'COMMENT',
        'RECOMMENDED',
        'HIDDEN',
        'INVISIBLE',
        'FOOTER',
        '<script',
        '<style'
      ]) {
        expect(article.markdown, isNot(contains(removed)));
      }
    });

    test('falls back to paragraph density without taking link-heavy menus', () {
      final article = extractArticle(
          '<title>Report</title><div>${List.generate(12, (i) => '<a href="/$i">Long navigation menu number $i</a>').join()}</div><section><p>$_paragraph</p><p>$_paragraph</p></section>',
          _url);
      expect(article.markdown, contains(_paragraph));
      expect(article.markdown, isNot(contains('navigation menu')));
    });

    test('keeps headings, lists, quotes, code and tables', () {
      final article = extractArticle(
          '''<article><h1>Report</h1><p>$_paragraph</p>
      <h2>Section</h2><p><strong>Bold</strong> and <em>emphasis</em> with <code>a`b</code>.</p>
      <ol start="3"><li>First<ul><li>Nested</li></ul></li><li>Second</li></ol>
      <blockquote><p>A quotation.</p></blockquote><pre><code>if (a &lt; b) {\n  print(```);\n}</code></pre>
      <table><tr><th>Name</th><th>Value</th></tr><tr><td>A | B</td><td>2</td></tr></table></article>''',
          _url);
      expect(article.markdown, contains('## Section'));
      expect(article.markdown, contains('**Bold** and *emphasis*'));
      expect(article.markdown, contains('`` a`b ``'));
      expect(article.markdown, contains('3. First\n   - Nested'));
      expect(article.markdown, contains('4. Second'));
      expect(article.markdown, contains('> A quotation.'));
      expect(article.markdown, contains('````\nif (a < b)'));
      expect(article.markdown,
          contains('| Name | Value |\n| --- | --- |\n| A \\| B | 2 |'));
    });

    test(
        'resolves ordinary links and image links without embedding images or HTML',
        () {
      final article = extractArticle('''<article><p>$_paragraph</p><p>
      <a href="../guide?id=2&amp;page=3">Guide</a><a href="javascript:alert(1)">Unsafe</a>
      <a href="https://user:pass@example.com">Credentials</a>
      <img src="/photo.png" alt="A photo"><img src="data:image/png;base64,AAAA" alt="Inline">
      <a href="http://[broken">Malformed</a> &lt;script&gt;plain&lt;/script&gt;
      ![literal](https://example.com/extra.png)</p></article>''', _url);
      expect(article.markdown,
          contains('[Guide](<https://example.com/guide?id=2&page=3>)'));
      expect(article.markdown,
          contains('[A photo](<https://example.com/photo.png>)'));
      expect(article.markdown, isNot(contains('![A photo]')));
      expect(article.markdown, isNot(contains('javascript:')));
      expect(article.markdown, isNot(contains('user:pass')));
      expect(article.markdown, isNot(contains('data:image')));
      expect(article.markdown, contains(r'\<script\>plain\</script\>'));
      expect(article.markdown, contains(r'!\[literal\]'));
    });

    test('supports Chinese text and plain text without executing Markdown', () {
      final article = extractArticle(
          '<article><h1>中文标题</h1><p>${'这是一段用于稍后阅读的中文正文，保留文字内容。' * 4}</p></article>',
          _url);
      expect(article.title, '中文标题');
      expect(article.markdown, contains('用于稍后阅读'));
      final plain = extractArticle(
          '$_paragraph\n<script>raw</script>\n![remote](https://x.invalid/image)',
          _url,
          plainText: true);
      expect(plain.markdown, contains(r'\<script\>raw\</script\>'));
      expect(plain.markdown, contains(r'!\[remote\]'));
    });

    test('rejects empty, link-only, huge and deeply nested documents', () {
      expect(() => extractArticle('<p>Short</p>', _url), _failure('empty'));
      expect(
          () =>
              extractArticle('<main><a href="/">$_paragraph</a></main>', _url),
          _failure('empty'));
      expect(
          () => extractArticle(
              'x' * (ArticleCaptureService.maxBytes * 2 + 1), _url),
          _failure('size'));
      expect(
          () => extractArticle(
              '${'<div>' * 140}$_paragraph${'</div>' * 140}', _url),
          _failure('size'));
      expect(
          () => extractArticle(
              '<article>${'<span>x</span>' * 20001}</article>', _url),
          _failure('size'));
      expect(
          () => extractArticle(
              '<article><p>${'x' * (600 * 1024)}</p></article>', _url),
          _failure('size'));
    });
  });

  group('guarded manual acquisition', () {
    final clients = <_Client>[];
    final resolutions = <String>[];
    late List<_Response> responses;
    late ArticleCaptureService service;
    setUp(() {
      clients.clear();
      resolutions.clear();
      responses = [
        _Response('<article><h1>Test</h1><p>$_paragraph</p></article>')
      ];
      service = ArticleCaptureService(
          guard: PluginNetworkGuard(resolver: (host) async {
        resolutions.add(host);
        return [
          InternetAddress(host == 'private.example' ? '10.0.0.1' : '8.8.8.8')
        ];
      }), clientFactory: () {
        final client = _Client(Future.value(responses.removeAt(0)));
        clients.add(client);
        return client;
      });
    });
    Future<CapturedArticle> fetch(String url) =>
        service.fetch(url, cancel: PluginCancelToken());

    test(
        'fetches text through public DNS, a pinned direct connection and no cookies',
        () async {
      final article = await fetch('https://example.com/news#section');
      expect(article.title, 'Test');
      expect(article.sourceUrl.toString(), 'https://example.com/news');
      expect(resolutions, ['example.com']);
      expect(clients.single.connectionFactory, isNotNull);
      expect(clients.single.findProxy!(_url), 'DIRECT');
      expect(clients.single.request!.cookies, isEmpty);
      expect(clients.single.request!.followRedirects, isFalse);
      expect(clients.single.request!.persistentConnection, isFalse);
      expect(clients.single.closed, isTrue);
    });

    test(
        'rejects HTTP, credentials, custom ports, literal IPs and private DNS before fetching',
        () async {
      for (final url in [
        'http://example.com',
        'https://user:pass@example.com',
        'https://example.com:8080',
        'https://127.0.0.1',
        'https://private.example'
      ]) {
        await expectLater(fetch(url), throwsA(isA<ArticleCaptureFailure>()));
      }
      expect(clients, isEmpty);
    });

    test('revalidates each redirect and preserves semantic query values',
        () async {
      responses = [
        _Response('',
            statusCode: 302, location: 'https://other.example/article?id=1'),
        _Response('', statusCode: 301, location: '../final?document=2'),
        _Response(_paragraph, mime: 'text/plain; charset=utf-8')
      ];
      final article = await fetch('https://example.com/start');
      expect(resolutions, ['example.com', 'other.example', 'other.example']);
      expect(article.sourceUrl.toString(),
          'https://other.example/final?document=2');
      expect(clients.every((client) => client.closed), isTrue);
    });

    test(
        'rejects redirect downgrade and private destinations before the next request',
        () async {
      for (final target in [
        'http://example.com/a',
        'https://private.example/a',
        'https://127.0.0.1/a'
      ]) {
        clients.clear();
        responses = [_Response('', statusCode: 302, location: target)];
        await expectLater(fetch('https://example.com'),
            throwsA(isA<ArticleCaptureFailure>()));
        expect(clients, hasLength(1));
      }
    });

    test('allows three redirect hops, refuses a fourth', () async {
      responses = [
        for (var i = 0; i < 3; i++)
          _Response('', statusCode: 302, location: '/$i'),
        _Response(_paragraph, mime: 'text/plain')
      ];
      expect(
          (await fetch('https://example.com')).markdown, contains(_paragraph));
      clients.clear();
      responses = [
        for (var i = 0; i < 4; i++)
          _Response('', statusCode: 302, location: '/$i')
      ];
      await expectLater(fetch('https://example.com'), _failure('redirect'));
      expect(clients, hasLength(4));
    });

    test('rejects non-text, absent MIME, excessive declared and streamed sizes',
        () async {
      for (final response in [
        _Response('pdf', mime: 'application/pdf'),
        _Response('text', mime: null)
      ]) {
        responses = [response];
        await expectLater(fetch('https://example.com'), _failure('format'));
      }
      responses = [_Response('', length: ArticleCaptureService.maxBytes + 1)];
      await expectLater(fetch('https://example.com'), _failure('size'));
      responses = [
        _Response.stream([
          List.filled(ArticleCaptureService.maxBytes, 65),
          [65]
        ])
      ];
      await expectLater(fetch('https://example.com'), _failure('size'));
    });

    test('cancels while DNS is pending and ignores the late answer', () async {
      final dns = Completer<List<InternetAddress>>();
      var created = false;
      final service = ArticleCaptureService(
          guard: PluginNetworkGuard(resolver: (_) => dns.future),
          clientFactory: () {
            created = true;
            return HttpClient();
          });
      final token = PluginCancelToken();
      final result = service.fetch('https://example.com', cancel: token);
      final check = expectLater(result, _failure('cancelled'));
      token.cancel();
      await check;
      dns.complete([InternetAddress('8.8.8.8')]);
      await Future<void>.delayed(Duration.zero);
      expect(created, isFalse);
    });

    test('has a total deadline and bounded global concurrency', () async {
      final dns = Completer<List<InternetAddress>>();
      final waiting = ArticleCaptureService(
          timeout: const Duration(milliseconds: 40),
          guard: PluginNetworkGuard(resolver: (_) => dns.future));
      final a =
          waiting.fetch('https://example.com', cancel: PluginCancelToken());
      final b =
          waiting.fetch('https://example.com', cancel: PluginCancelToken());
      final aCheck = expectLater(a, _failure('timeout'));
      final bCheck = expectLater(b, _failure('timeout'));
      await expectLater(
          waiting.fetch('https://example.com', cancel: PluginCancelToken()),
          _failure('busy'));
      await Future.wait([aCheck, bCheck]);
      dns.complete([InternetAddress('8.8.8.8')]);
      await Future<void>.delayed(Duration.zero);
      expect((await fetch('https://example.com')).title, 'Test');
    });

    test('failures never include an address or query in their message',
        () async {
      responses = [_Response('failure', statusCode: 403)];
      try {
        await fetch('https://example.com/private?secret=abcd');
        fail('expected a failure');
      } catch (error) {
        expect(error.toString(), 'ArticleCaptureFailure(network)');
      }
    });
  });
}
