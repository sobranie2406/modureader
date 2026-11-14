import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/models/plugin_network.dart';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/service/plugins/plugin_http_budget.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_json_mapping.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';
import 'package:flutter_test/flutter_test.dart';

JsonPath _path(String raw) => JsonPath.parse(raw, 'test');

Matcher _fails(String code) =>
    throwsA(isA<DictionaryFailure>().having((e) => e.code, 'code', code));

void main() {
  group('JSON path evaluation', () {
    const document = {
      'data': {
        'entries': [
          {
            'senses': [
              {'definition': 'first'},
              {'definition': 'second'},
            ]
          },
          {
            'senses': [
              {'definition': 'third'},
            ]
          },
        ]
      }
    };

    test('walks keys, wildcards and indexes', () {
      expect(
        PluginJsonMapping.evaluate(
            _path('data.entries[*].senses[*].definition'), document),
        ['first', 'second', 'third'],
      );
    });

    test('a missing key yields nothing rather than throwing', () {
      expect(
          PluginJsonMapping.evaluate(_path('data.missing'), document), isEmpty);
    });

    test('an out-of-range index yields nothing', () {
      expect(PluginJsonMapping.evaluate(_path('data.entries[9]'), document),
          isEmpty);
    });

    test('a key against an array yields nothing', () {
      expect(
          PluginJsonMapping.evaluate(
              _path('data.entries.definition'), document),
          isEmpty);
    });

    test('an index against an object yields nothing', () {
      expect(PluginJsonMapping.evaluate(_path('data[0]'), document), isEmpty);
    });
  });

  group('structural limits', () {
    test('rejects excessive depth', () {
      Object? nested = 'leaf';
      for (var i = 0; i < 40; i++) {
        nested = {'a': nested};
      }
      expect(() => PluginJsonMapping.checkStructure(nested),
          _fails('invalidResponse'));
    });

    test('accepts a document within the limits', () {
      expect(
          () => PluginJsonMapping.checkStructure({
                'a': [
                  1,
                  2,
                  {'b': 'c'}
                ]
              }),
          returnsNormally);
    });

    test('rejects an oversized total string length', () {
      final big = 'x' * (PluginJsonMapping.maxTotalStringLength + 1);
      expect(() => PluginJsonMapping.checkStructure({'a': big}),
          _fails('invalidResponse'));
    });
  });

  group('response mapping', () {
    PluginResponseMapping mapping(Map<String, String> fields,
            {String? root, int maxEntries = 5, int maxChars = 4000}) =>
        PluginResponseMapping.parse({
          'format': 'json',
          if (root != null) 'root': root,
          'fields': fields,
          'maxEntries': maxEntries,
          'maxDefinitionChars': maxChars,
        });

    List<DictionaryEntry> map(Object? document, PluginResponseMapping spec) =>
        PluginJsonMapping.map(
          document: document,
          mapping: spec,
          sourceId: 'example',
          sourceLabel: 'Example',
          license: 'CC-BY-4.0',
          attribution: 'Example contributors',
          licenseUri: 'https://example.com/l',
          sourceUrl: 'https://example.com/s',
          word: 'apple',
        );

    test('maps a definition list into entries', () {
      final entries = map({
        'd': ['one', 'two']
      }, mapping({'definition': 'd'}));
      expect(entries.map((e) => e.definition), ['one', 'two']);
      expect(entries.first.dictionary, 'Example');
      expect(entries.first.license, 'CC-BY-4.0');
      expect(entries.first.attribution, 'Example contributors');
    });

    test('returns nothing when no definition is present', () {
      expect(map({'d': []}, mapping({'definition': 'd'})), isEmpty);
      expect(map({'x': 1}, mapping({'definition': 'd'})), isEmpty);
    });

    test('truncates past maxDefinitionChars', () {
      final entries = map({
        'd': ['y' * 500]
      }, mapping({'definition': 'd'}, maxChars: 100));
      expect(entries.single.definition.length, 101); // 100 + the ellipsis
      expect(entries.single.definition.endsWith('…'), isTrue);
    });

    test('a short definition is not truncated or marked', () {
      final entries = map({
        'd': ['short']
      }, mapping({'definition': 'd'}, maxChars: 100));
      expect(entries.single.definition, 'short');
    });

    test('honours maxEntries', () {
      final entries = map({
        'd': ['a', 'b', 'c']
      }, mapping({'definition': 'd'}, maxEntries: 2));
      expect(entries, hasLength(2));
    });

    test('prefixes part of speech when present', () {
      final entries = map({
        'd': ['a fruit'],
        'p': 'noun',
      }, mapping({'definition': 'd', 'partOfSpeech': 'p'}));
      expect(entries.single.definition, 'noun. a fruit');
    });

    test('drops a non-https sourceUrl but keeps the entry', () {
      final entries = map({
        'd': ['x'],
        'u': 'http://insecure.example.com/x',
      }, mapping({'definition': 'd', 'sourceUrl': 'u'}));
      expect(entries.single.sourceUri, isNull);
    });

    test('keeps an https sourceUrl', () {
      final entries = map({
        'd': ['x'],
        'u': 'https://example.com/entry',
      }, mapping({'definition': 'd', 'sourceUrl': 'u'}));
      expect(entries.single.sourceUri.toString(), 'https://example.com/entry');
    });

    test('strips control characters', () {
      final entries = map({
        'd': ['bad\u0000text\u0007!']
      }, mapping({'definition': 'd'}));
      expect(entries.single.definition, 'badtext!');
    });

    test('applies a root path before fields', () {
      final entries = map({
        'payload': {
          'd': ['rooted']
        }
      }, mapping({'definition': 'd'}, root: 'payload'));
      expect(entries.single.definition, 'rooted');
    });
  });

  group('address classification', () {
    bool public(String address) =>
        PluginNetworkGuard.isPublicAddress(InternetAddress(address));

    for (final address in [
      '127.0.0.1',
      '10.1.2.3',
      '172.16.0.1',
      '192.168.1.1',
      '169.254.169.254',
      '0.0.0.0',
      '100.64.0.1',
      '224.0.0.1',
      '::1',
      '::',
      '::7f00:1',
      'fe80::1',
      'fc00::1',
      'fec0::1',
      'ff02::1',
      '100::1',
      '100:0:0:1::1',
      '64:ff9b::a9fe:a9fe',
      '64:ff9b:1::a9fe:a9fe',
      '2002:a9fe:a9fe::1',
      '2001::1',
      '2001:0:4136:e378:8000:63bf:3fff:fdd2',
      '2001:db8::1',
      '3fff::1',
      '3fff:fff:ffff::1',
      '4000::1',
      '5f00::1',
      '::ffff:127.0.0.1',
      '::ffff:169.254.169.254',
    ]) {
      test('rejects $address', () {
        expect(public(address), isFalse);
      });
    }

    for (final address in [
      '8.8.8.8',
      '1.1.1.1',
      '2606:4700::1111',
      '2001:4860:4860::8888',
      '::ffff:8.8.8.8',
      '3fff:1000::1'
    ]) {
      test('accepts $address', () {
        expect(public(address), isTrue);
      });
    }
  });

  group('guard', () {
    PluginNetwork network = PluginNetwork.parse({
      'domains': ['api.example.com'],
    });

    PluginNetworkGuard guardReturning(List<String> addresses) =>
        PluginNetworkGuard(
            resolver: (host) async =>
                addresses.map(InternetAddress.new).toList());

    test('accepts an allowlisted https host resolving publicly', () async {
      final result = await guardReturning(['8.8.8.8']).validate(
        network: network,
        uri: Uri.parse('https://api.example.com/x'),
        headers: const {},
      );
      expect(result.addresses.single.address, '8.8.8.8');
    });

    test('accepts an allowlisted host resolving to native public IPv6',
        () async {
      final result = await guardReturning(['2001:4860:4860::8888']).validate(
        network: network,
        uri: Uri.parse('https://api.example.com/x'),
        headers: const {},
      );
      expect(result.addresses.single.address, '2001:4860:4860::8888');
    });

    for (final address in [
      'fec0::1',
      '100::1',
      '2002:a9fe:a9fe::1',
      '2001::1',
      '2001:db8::1',
      '3fff::1'
    ]) {
      test('rejects a mixed DNS answer containing $address', () async {
        await expectLater(
          guardReturning(['2001:4860:4860::8888', address]).validate(
            network: network,
            uri: Uri.parse('https://api.example.com/x'),
            headers: const {},
          ),
          _fails('configuration'),
        );
      });
    }

    test('rejects a host outside the allowlist', () async {
      expect(
        guardReturning(['8.8.8.8']).validate(
          network: network,
          uri: Uri.parse('https://evil.example.com/x'),
          headers: const {},
        ),
        _fails('configuration'),
      );
    });

    test('rejects http', () async {
      expect(
        guardReturning(['8.8.8.8']).validate(
          network: network,
          uri: Uri.parse('http://api.example.com/x'),
          headers: const {},
        ),
        _fails('configuration'),
      );
    });

    test('rejects a non-443 port', () async {
      expect(
        guardReturning(['8.8.8.8']).validate(
          network: network,
          uri: Uri.parse('https://api.example.com:8443/x'),
          headers: const {},
        ),
        _fails('configuration'),
      );
    });

    test('rejects userinfo in the URL', () async {
      expect(
        guardReturning(['8.8.8.8']).validate(
          network: network,
          uri: Uri.parse('https://user:pass@api.example.com/x'),
          headers: const {},
        ),
        _fails('configuration'),
      );
    });

    test('rejects a private address for an allowlisted name', () async {
      expect(
        guardReturning(['127.0.0.1']).validate(
          network: network,
          uri: Uri.parse('https://api.example.com/x'),
          headers: const {},
        ),
        _fails('configuration'),
      );
    });

    test('rejects when any record is private (rebinding shape)', () async {
      expect(
        guardReturning(['8.8.8.8', '10.0.0.5']).validate(
          network: network,
          uri: Uri.parse('https://api.example.com/x'),
          headers: const {},
        ),
        _fails('configuration'),
      );
    });

    test('rejects an empty resolution', () async {
      expect(
        guardReturning([]).validate(
          network: network,
          uri: Uri.parse('https://api.example.com/x'),
          headers: const {},
        ),
        _fails('network'),
      );
    });
  });

  group('budget', () {
    test('rejects a second concurrent request for one plugin', () {
      final budget = PluginHttpBudget();
      budget.acquire('a');
      expect(() => budget.check('a'), _fails('rateLimited'));
      budget.release('a');
      expect(() => budget.check('a'), returnsNormally);
    });

    test('enforces the global concurrency ceiling', () {
      final budget = PluginHttpBudget(globalConcurrency: 1);
      budget.acquire('a');
      expect(() => budget.check('b'), _fails('rateLimited'));
      budget.release('a');
      expect(() => budget.check('b'), returnsNormally);
    });

    test('enforces the per-minute window', () {
      var now = DateTime(2026);
      final budget = PluginHttpBudget(
          perPluginConcurrency: 99, perPluginPerMinute: 2, clock: () => now);
      budget.acquire('a');
      budget.release('a');
      budget.acquire('a');
      budget.release('a');
      expect(() => budget.check('a'), _fails('rateLimited'));
      now = now.add(const Duration(minutes: 2));
      expect(() => budget.check('a'), returnsNormally);
    });

    test('enforces the daily ceiling and resets the next day', () {
      var now = DateTime(2026, 1, 1, 12);
      final budget = PluginHttpBudget(
          perPluginConcurrency: 99,
          perPluginPerMinute: 999,
          perPluginPerDay: 2,
          clock: () => now);
      budget.acquire('a');
      budget.release('a');
      budget.acquire('a');
      budget.release('a');
      expect(() => budget.check('a'), _fails('dailyLimit'));
      now = DateTime(2026, 1, 2, 1);
      expect(() => budget.check('a'), returnsNormally);
      expect(budget.dailyCountFor('a'), 0);
    });

    test('late refunds do not remove another plugin burst count', () {
      var now = DateTime(2026);
      final budget = PluginHttpBudget(globalPerMinute: 1, clock: () => now);
      budget.acquire('a');
      now = now.add(const Duration(minutes: 2));
      budget.acquire('b');
      budget.refund('a');
      budget.release('b');
      expect(() => budget.check('c'), _fails('rateLimited'));
      budget.refund('a');
      expect(budget.globalInFlight, 0);
    });

    test('a refund does not count against the daily allowance', () {
      final budget = PluginHttpBudget();
      budget.acquire('a');
      budget.refund('a');
      expect(budget.dailyCountFor('a'), 0);
      expect(budget.inFlightFor('a'), 0);
    });
  });

  group('cache', () {
    test('expires entries after the ttl', () {
      var now = DateTime(2026);
      final cache = PluginLookupCache(clock: () => now);
      cache.write('k', 'v');
      expect(cache.read<String>('k'), 'v');
      now = now.add(const Duration(minutes: 11));
      expect(cache.read<String>('k'), isNull);
    });

    test('evicts the oldest entry past the cap', () {
      final cache = PluginLookupCache(maxEntries: 2);
      cache.write('a', 1);
      cache.write('b', 2);
      cache.write('c', 3);
      expect(cache.read<int>('a'), isNull);
      expect(cache.read<int>('c'), 3);
    });
  });

  group('http client against a local server', () {
    late HttpServer server;
    late PluginHttpClient client;
    late List<InternetAddress> localhost;

    setUpAll(() {
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
          File('test/fixtures/plugins/tls/localhost-ca.pem').readAsBytesSync());
    });

    setUp(() async {
      final tls = SecurityContext()
        ..useCertificateChain('test/fixtures/plugins/tls/localhost-cert.pem')
        ..usePrivateKey('test/fixtures/plugins/tls/localhost-key.pem');
      server =
          await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, tls);
      localhost = await InternetAddress.lookup('localhost',
          type: InternetAddressType.IPv4);
      client = PluginHttpClient(httpClientFactory: HttpClient.new);
    });

    tearDown(() async {
      await server.close(force: true);
    });

    /// Builds a guard result that points at the local test server. The guard is
    /// bypassed on purpose: this group exercises transport behaviour, not
    /// address policy, which the guard group already covers.
    PluginGuardResult target(String path, {Map<String, String>? headers}) =>
        PluginGuardResult(
          uri: Uri.parse('https://localhost:${server.port}$path'),
          addresses: localhost,
          headers: headers ?? const {},
        );

    test('establishes a trusted TLS socket for the pinned hostname', () async {
      server.listen((request) => request.response.close());
      final task = await connectPluginTls(
          target: target('/tls'),
          timeout: const Duration(seconds: 2),
          isCancelled: () => false);
      final socket = await task.socket;
      expect(socket, isA<SecureSocket>());
      socket.destroy();
    });

    test('rejects a trusted certificate issued for a different hostname',
        () async {
      server.listen((request) => request.response.close());
      final task = await connectPluginTls(
          target: PluginGuardResult(
              uri: Uri.parse('https://127.0.0.1:${server.port}/'),
              addresses: [InternetAddress.loopbackIPv4],
              headers: const {}),
          timeout: const Duration(seconds: 2),
          isCancelled: () => false);
      await expectLater(task.socket, throwsA(isA<HandshakeException>()));
    });

    test('client creation failure releases its concurrency slot', () async {
      final budget = PluginHttpBudget();
      final broken = PluginHttpClient(
          budget: budget,
          httpClientFactory: () => throw StateError('test failure'));
      await expectLater(
          broken.get(
              target: target('/x'),
              timeout: const Duration(seconds: 1),
              maxBytes: 1024,
              pluginId: 'a'),
          _fails('network'));
      expect(budget.globalInFlight, 0);
      expect(budget.inFlightFor('a'), 0);
    });

    test('a cancelled request never creates a client or reserves a slot',
        () async {
      final budget = PluginHttpBudget();
      final token = PluginCancelToken()..cancel();
      var created = false;
      final transport = PluginHttpClient(
          budget: budget,
          httpClientFactory: () {
            created = true;
            return HttpClient();
          });
      await expectLater(
          transport.get(
              target: target('/x'),
              timeout: const Duration(seconds: 1),
              maxBytes: 1024,
              pluginId: 'a',
              cancel: token),
          _fails('cancelled'));
      expect(created, isFalse);
      expect(budget.dailyCountFor('a'), 0);
    });

    test('an unending error body is rejected without draining it', () async {
      server.listen((request) async {
        request.response.statusCode = 429;
        request.response.write('error');
        await request.response.flush();
      });
      await expectLater(
          client.get(
              target: target('/x'),
              timeout: const Duration(milliseconds: 500),
              maxBytes: 1024,
              pluginId: 'a'),
          _fails('rateLimited'));
    });

    test('returns the body of a 200 response', () async {
      server.listen((request) {
        request.response
          ..statusCode = 200
          ..write('{"ok":true}');
        request.response.close();
      });
      final bytes = await client.get(
        target: target('/x'),
        timeout: const Duration(seconds: 5),
        maxBytes: 1024,
        pluginId: 'a',
      );
      expect(utf8.decode(bytes), '{"ok":true}');
    });

    test('rejects a redirect without following it', () async {
      server.listen((request) {
        request.response
          ..statusCode = 302
          ..headers.set('Location', 'https://evil.example.com/');
        request.response.close();
      });
      expect(
        client.get(
          target: target('/x'),
          timeout: const Duration(seconds: 5),
          maxBytes: 1024,
          pluginId: 'a',
        ),
        _fails('network'),
      );
    });

    test('maps 429 to rateLimited', () async {
      server.listen((request) {
        request.response.statusCode = 429;
        request.response.close();
      });
      expect(
        client.get(
          target: target('/x'),
          timeout: const Duration(seconds: 5),
          maxBytes: 1024,
          pluginId: 'a',
        ),
        _fails('rateLimited'),
      );
    });

    test('rejects a body larger than the cap', () async {
      server.listen((request) {
        request.response.statusCode = 200;
        request.response.add(List.filled(4096, 0x41));
        request.response.close();
      });
      expect(
        client.get(
          target: target('/x'),
          timeout: const Duration(seconds: 5),
          maxBytes: 1024,
          pluginId: 'a',
        ),
        _fails('responseTooLarge'),
      );
    });

    test('fails on a server error', () async {
      server.listen((request) {
        request.response.statusCode = 500;
        request.response.close();
      });
      expect(
        client.get(
          target: target('/x'),
          timeout: const Duration(seconds: 5),
          maxBytes: 1024,
          pluginId: 'a',
        ),
        _fails('network'),
      );
    });

    test('cancellation fails fast and does not hang', () async {
      server.listen((request) async {
        await Future<void>.delayed(const Duration(seconds: 3));
        request.response.close();
      });
      final token = PluginCancelToken();
      final future = client.get(
        target: target('/slow'),
        timeout: const Duration(seconds: 30),
        maxBytes: 1024,
        pluginId: 'a',
        cancel: token,
      );
      token.cancel();
      await expectLater(future, _fails('cancelled'));
    });
  });
}
