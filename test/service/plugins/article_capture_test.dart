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
  _Response.bytes(List<int> bytes, {String mime = 'text/html'})
      : _data = [bytes],
        statusCode = 200,
        headers = _Headers(mime: mime),
        contentLength = bytes.length;
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
    Future<ArticleCaptureDocument> fetch(String url) =>
        service.fetchDocument(url, cancel: PluginCancelToken());

    test(
        'fetches text through public DNS, a pinned direct connection and no cookies',
        () async {
      final article = await fetch('https://example.com/news#section');
      expect(article.content, contains('<h1>Test</h1>'));
      expect(article.plainText, false);
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
          (await fetch('https://example.com')).content, contains(_paragraph));
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

    test('returns raw HTML without native extraction or executing page code',
        () async {
      const raw =
          '<title>Raw page</title><header>Site header</header><script>throw new Error("PAGE_CODE")</script><article><p>$_paragraph</p></article>';
      responses = [_Response(raw)];
      final document = await fetch('https://example.com');
      expect(document.content, raw);
      expect(document.plainText, false);
    });

    test('plain text preserves literal markup for the plugin to process',
        () async {
      const raw =
          '# original\n<script>literal</script>\n![literal](https://example.com/image)';
      responses = [_Response(raw, mime: 'text/plain; charset=utf-8')];
      final document = await fetch('https://example.com');
      expect(document.content, raw);
      expect(document.plainText, true);
    });

    test('decodes declared and meta charsets before enforcing UTF8 input size',
        () async {
      final raw = latin1.encode('<meta charset="iso-8859-1"><p>café</p>');
      responses = [_Response.bytes(raw)];
      expect((await fetch('https://example.com')).content, contains('café'));
      responses = [
        _Response.bytes(List.filled(ArticleCaptureService.maxBytes, 0xff),
            mime: 'text/plain; charset=iso-8859-1')
      ];
      await expectLater(fetch('https://example.com'), _failure('size'));
      responses = [
        _Response.bytes([0xff, 0xff], mime: 'text/plain; charset=utf-8')
      ];
      await expectLater(fetch('https://example.com'), _failure('format'));
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
      final result =
          service.fetchDocument('https://example.com', cancel: token);
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
      final a = waiting.fetchDocument('https://example.com',
          cancel: PluginCancelToken());
      final b = waiting.fetchDocument('https://example.com',
          cancel: PluginCancelToken());
      final aCheck = expectLater(a, _failure('timeout'));
      final bCheck = expectLater(b, _failure('timeout'));
      await expectLater(
          waiting.fetchDocument('https://example.com',
              cancel: PluginCancelToken()),
          _failure('busy'));
      await Future.wait([aCheck, bCheck]);
      dns.complete([InternetAddress('8.8.8.8')]);
      await Future<void>.delayed(Duration.zero);
      expect((await fetch('https://example.com')).content,
          contains('<h1>Test</h1>'));
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
