import 'dart:convert';

import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/models/plugin_network.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _base({
  List<String> capabilities = const ['net:http'],
  Map<String, dynamic>? network,
  List<Map<String, dynamic>>? contributes,
  List<Map<String, dynamic>>? settings,
}) =>
    {
      'schemaVersion': 1,
      'id': 'com.example.dict',
      'version': '1.0.0',
      'name': {'en': 'Example'},
      'description': {'en': 'Example'},
      'author': {'name': 'Example'},
      'license': 'MIT',
      'capabilities': capabilities,
      'hostApi': 1,
      if (network != null) 'network': network,
      'contributes': contributes ?? [_source()],
      if (settings != null) 'settings': settings,
    };

Map<String, dynamic> _network({
  List<String> domains = const ['api.example.com'],
  Object? timeoutMs,
  Object? maxResponseBytes,
  Object? requestsPerLookup,
}) =>
    {
      'domains': domains,
      if (timeoutMs != null) 'timeoutMs': timeoutMs,
      if (maxResponseBytes != null) 'maxResponseBytes': maxResponseBytes,
      if (requestsPerLookup != null) 'requestsPerLookup': requestsPerLookup,
    };

Map<String, dynamic> _source({
  String id = 'example',
  Object? license = 'CC-BY-4.0',
  Object? attribution = 'Example contributors',
  Map<String, dynamic>? request,
  Map<String, dynamic>? response,
  Object? licenseUri,
  Object? sourceUrl,
}) =>
    {
      'kind': 'dictionarySource',
      'schema': 1,
      'id': id,
      'name': {'en': 'Example dictionary'},
      'license': license,
      'attribution': attribution,
      if (licenseUri != null) 'licenseUri': licenseUri,
      if (sourceUrl != null) 'sourceUrl': sourceUrl,
      'request': request ??
          {
            'method': 'GET',
            'url': '/api/lookup',
            'query': {'q': '{word}'},
          },
      'response': response ??
          {
            'format': 'json',
            'fields': {'definition': 'definition'},
          },
    };

PluginManifest _parse(Map<String, dynamic> json) =>
    PluginManifest.fromJson(json);

Matcher _rejects(PluginErrorCode code) =>
    throwsA(isA<PluginInstallError>().having((e) => e.code, 'code', code));

void main() {
  group('capability and network block pairing', () {
    test('a valid net:http package with a dictionary source installs', () {
      final manifest = _parse(_base(network: _network()));
      expect(manifest.network, isNotNull);
      expect(manifest.network!.domains, ['api.example.com']);
      expect(manifest.network!.timeoutMs, PluginNetwork.defaultTimeoutMs);
      expect(manifest.contributions.single, isA<DictionarySourceContribution>());
    });

    test('net:http without a network block is rejected', () {
      expect(() => _parse(_base()), throwsA(isA<PluginInstallError>()));
    });

    test('a network block without net:http is rejected', () {
      expect(
        () => _parse(_base(capabilities: const [], network: _network())),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('a dictionary source without a network block is rejected', () {
      expect(
        () => _parse(_base(capabilities: const [])),
        throwsA(isA<PluginInstallError>()),
      );
    });

    test('script:run is still refused', () {
      expect(
        () => _parse(_base(capabilities: const ['net:http', 'script:run'],
            network: _network())),
        throwsA(isA<PluginInstallError>()),
      );
    });
  });

  group('allowlisted domains', () {
    for (final host in [
      '127.0.0.1',
      '0.0.0.0',
      '10.0.0.1',
      '192.168.1.1',
      '169.254.169.254',
      '2130706433',
      '0x7f000001',
      '017700000001',
      '[::1]',
      '::1',
      'fe80::1',
      'localhost',
      'api.localhost',
      'printer.local',
      'svc.internal',
      'router.home.arpa',
    ]) {
      test('rejects $host', () {
        expect(
          () => _parse(_base(network: _network(domains: [host]))),
          _rejects(PluginErrorCode.invalidManifest),
        );
      });
    }

    for (final host in [
      'API.Example.com',
      'api.example.com.',
      'api.example.com/path',
      'user@api.example.com',
      'api.example.com:443',
      '*.example.com',
      'exa mple.com',
      'api.example.com\\evil',
    ]) {
      test('rejects ${jsonEncode(host)}', () {
        expect(
          () => _parse(_base(network: _network(domains: [host]))),
          _rejects(PluginErrorCode.invalidManifest),
        );
      });
    }

    test('accepts up to eight distinct hosts', () {
      final manifest = _parse(_base(
          network: _network(domains: [
        'a.example.com',
        'b.example.com',
        'c.example.com',
        'd.example.com',
        'e.example.com',
        'f.example.com',
        'g.example.com',
        'h.example.com',
      ])));
      expect(manifest.network!.domains, hasLength(8));
    });

    test('rejects nine hosts', () {
      expect(
        () => _parse(_base(network: _network(domains: [
              for (var i = 0; i < 9; i++) '$i.example.com',
            ]))),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects duplicates', () {
      expect(
        () => _parse(_base(
            network: _network(domains: ['a.example.com', 'a.example.com']))),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });
  });

  group('network limits', () {
    test('rejects a timeout below the floor', () {
      expect(() => _parse(_base(network: _network(timeoutMs: 999))),
          _rejects(PluginErrorCode.invalidManifest));
    });

    test('rejects a timeout above the ceiling', () {
      expect(() => _parse(_base(network: _network(timeoutMs: 15001))),
          _rejects(PluginErrorCode.invalidManifest));
    });

    test('rejects a response cap above 1 MiB', () {
      expect(
          () => _parse(_base(
              network: _network(maxResponseBytes: 1024 * 1024 + 1))),
          _rejects(PluginErrorCode.invalidManifest));
    });

    test('rejects requestsPerLookup other than 1', () {
      expect(() => _parse(_base(network: _network(requestsPerLookup: 2))),
          _rejects(PluginErrorCode.invalidManifest));
    });
  });

  group('request templates', () {
    test('rejects a non-GET method', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'POST',
                'url': '/x',
                'query': {'q': '{word}'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects a URL with a query string', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {'method': 'GET', 'url': '/x?q=1'})
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects an absolute URL', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': 'https://evil.example.com/x'
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects a secret in the query', () {
      expect(
        () => _parse(_base(
            network: _network(),
            settings: [
              {'key': 'k', 'type': 'secret'}
            ],
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{word}', 'key': '{secret.k}'},
              })
            ])),
        // The template parser refuses a secret outside Authorization before the
        // reference checker runs, which is the stricter of the two.
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects an unknown placeholder', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{term}'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects an undeclared {setting.<key>}', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{word}', 'lang': '{setting.missing}'}
              })
            ])),
        _rejects(PluginErrorCode.invalidContribution),
      );
    });

    test('accepts a declared {setting.<key>}', () {
      final manifest = _parse(_base(
        network: _network(),
        settings: [
          {'key': 'lang', 'type': 'text', 'defaultValue': 'en'}
        ],
        contributes: [
          _source(request: {
            'method': 'GET',
            'url': '/x',
            'query': {'q': '{word}', 'lang': '{setting.lang}'}
          })
        ],
      ));
      expect(manifest.settings.single.key, 'lang');
    });

    test('rejects a non-allowlisted header', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{word}'},
                'headers': {'Cookie': 'a=b'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects a User-Agent override', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{word}'},
                'headers': {'User-Agent': 'x'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects concatenation around a secret in Authorization', () {
      expect(
        () => _parse(_base(
            network: _network(),
            settings: [
              {'key': 'k', 'type': 'secret'}
            ],
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{word}'},
                'headers': {'Authorization': 'Bearer {secret.k} extra'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects a newline in a header value', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{word}'},
                'headers': {'Accept': 'a\r\nX: y'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('accepts a single secret in Authorization', () {
      final manifest = _parse(_base(
        network: _network(),
        settings: [
          {'key': 'k', 'type': 'secret', 'required': true}
        ],
        contributes: [
          _source(request: {
            'method': 'GET',
            'url': '/x',
            'query': {'q': '{word}'},
            'headers': {'Authorization': 'Bearer {secret.k}', 'Accept': 'application/json'}
          })
        ],
      ));
      expect(manifest.settings.single.required, isTrue);
    });

    test('rejects {word} in a header', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(request: {
                'method': 'GET',
                'url': '/x',
                'query': {'q': '{word}'},
                'headers': {'Accept': '{word}'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });
  });

  group('secret settings', () {
    test('a secret outside net:http is rejected', () {
      expect(
        () => _parse(_base(
            capabilities: const [],
            contributes: const [],
            settings: [
              {'key': 'k', 'type': 'secret'}
            ])),
        throwsA(isA<PluginInstallError>()),
      );
    });

    test('a secret with a default value is rejected', () {
      expect(
        () => _parse(_base(
            network: _network(),
            settings: [
              {'key': 'k', 'type': 'secret', 'defaultValue': 'abc'}
            ])),
        _rejects(PluginErrorCode.invalidSetting),
      );
    });

    test('required on a non-secret is rejected', () {
      expect(
        () => _parse(_base(
            network: _network(),
            settings: [
              {'key': 'k', 'type': 'text', 'required': true}
            ])),
        _rejects(PluginErrorCode.invalidSetting),
      );
    });
  });

  group('response mapping', () {
    test('requires a definition field', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(response: {
                'format': 'json',
                'fields': {'word': 'w'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects HTML', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(response: {
                'format': 'html',
                'fields': {'definition': 'd'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });

    test('rejects an unknown field name', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(response: {
                'format': 'json',
                'fields': {'definition': 'd', 'html': 'h'}
              })
            ])),
        _rejects(PluginErrorCode.invalidManifest),
      );
    });
  });

  group('JSON path grammar', () {
    test('parses keys, indexes and wildcards', () {
      final path = JsonPath.parse('data.entries[*].senses[0].definition', 'p');
      expect(path.segments, hasLength(6));
      expect(path.toString(), 'data.entries[*].senses[0].definition');
    });

    test('rejects an unclosed bracket', () {
      expect(() => JsonPath.parse('a[0', 'p'),
          _rejects(PluginErrorCode.invalidManifest));
    });

    test('rejects a filter expression', () {
      expect(() => JsonPath.parse('a[?(@.b)]', 'p'),
          _rejects(PluginErrorCode.invalidManifest));
    });

    test('rejects a function call', () {
      expect(() => JsonPath.parse('a.b()', 'p'),
          _rejects(PluginErrorCode.invalidManifest));
    });

    test('rejects recursive descent', () {
      expect(() => JsonPath.parse('a..b', 'p'),
          _rejects(PluginErrorCode.invalidManifest));
    });

    test('rejects an empty segment', () {
      expect(() => JsonPath.parse('a..b', 'p'),
          throwsA(isA<PluginInstallError>()));
    });
  });

  group('licence and attribution', () {
    test('a source without a licence is rejected', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [_source(license: null)])),
        _rejects(PluginErrorCode.invalidContribution),
      );
    });

    test('a source without attribution is rejected', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [_source(attribution: null)])),
        throwsA(isA<PluginInstallError>()),
      );
    });

    test('an http licenceUri is rejected', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              _source(licenseUri: 'http://example.com/licence')
            ])),
        _rejects(PluginErrorCode.invalidContribution),
      );
    });

    test('an https licenseUri is accepted', () {
      final manifest = _parse(_base(
          network: _network(),
          contributes: [
            _source(licenseUri: 'https://example.com/licence')
          ]));
      expect(
          (manifest.contributions.single as DictionarySourceContribution)
              .licenseUri,
          'https://example.com/licence');
    });
  });

  group('limits', () {
    test('rejects more than eight dictionary sources', () {
      expect(
        () => _parse(_base(
            network: _network(),
            contributes: [
              for (var i = 0; i < 9; i++) _source(id: 'source$i'),
            ])),
        _rejects(PluginErrorCode.tooManyContributions),
      );
    });
  });
}