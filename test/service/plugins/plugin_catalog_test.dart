import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:modu_reader/service/plugins/plugin_catalog.dart';
import 'package:modu_reader/service/plugins/plugin_catalog_signature.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';

Map<String, dynamic> catalogItem({String version = '1.1.0', String? digest}) =>
    {
      'id': 'com.example.prompt-pack',
      'version': version,
      'name': {'en': 'Example prompt pack'},
      'minAppVersion': '1.3.1',
      'hostApi': 1,
      'capabilities': ['ai:prompt-pack', 'ui:selection-action'],
      'status': 'reviewed',
      'sourcePath': 'packages/prompt-pack',
      'package': {
        'path': 'dist/com.example.prompt-pack-$version.moduplugin',
        'sha256': digest ?? 'a' * 64
      },
      'files': Map<String, String>.from(
          PluginTrust.approved['com.example.prompt-pack@1.1.0']!),
      'review': {
        'kind': 'agent-technical',
        'reviewer': 'Codex',
        'reviewedAt': '2026-11-14T13:27:25Z'
      },
    };

String catalogJson(List<Map<String, dynamic>> plugins) => jsonEncode({
      'schemaVersion': 1,
      'repository': PluginTrust.projectSource,
      'plugins': plugins,
    });

class CatalogClient extends http.BaseClient {
  CatalogClient(this.respond);
  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
  @override
  void close() {
    closed = true;
  }
}

class _Signer {
  _Signer(this.keyPair, this.verifier);
  final SimpleKeyPair keyPair;
  final PluginCatalogSignature verifier;
  static Future<_Signer> create() async {
    final pair = await Ed25519().newKeyPairFromSeed(List.filled(32, 7));
    final public = await pair.extractPublicKey();
    return _Signer(
        pair,
        PluginCatalogSignature(publicKeys: {
          PluginCatalogSignature.keyId: public.bytes,
        }));
  }

  Future<String> sign(String text) async {
    final payload = utf8.encode(text);
    final signature = await Ed25519().sign(payload, keyPair: keyPair);
    return jsonEncode({
      'schemaVersion': 1,
      'algorithm': 'Ed25519',
      'keyId': PluginCatalogSignature.keyId,
      'payload': base64Encode(payload),
      'signature': base64Encode(signature.bytes)
    });
  }
}

void main() {
  late _Signer signer;
  setUp(() async => signer = await _Signer.create());
  Matcher failure(String code) =>
      throwsA(isA<PluginCatalogFailure>().having((e) => e.code, 'code', code));

  test(
      'new reviewed versions use supported API and capabilities without an app hash update',
      () {
    final listed = catalogItem(), future = catalogItem(version: '2.0.0');
    final draft = {'status': 'submitted'};
    final entries = PluginCatalog.parse(catalogJson([listed, future, draft]));
    expect(entries, hasLength(2));
    expect(entries.first.supported, isTrue);
    expect(entries.first.requiresAppUpdate('1.3.10+10178'), isFalse);
    expect(entries.first.requiresAppUpdate('1.3.0'), isTrue);
    expect(entries.first.requiresAppUpdate(''), isTrue);
    expect(entries.last.requiresAppUpdate('1.3.10'), isFalse);
    for (final change in <void Function(Map<String, dynamic>)>[
      (item) => item['hostApi'] = 2,
      (item) => item['capabilities'] = ['future:capability'],
    ]) {
      final item = catalogItem(version: '2.0.0');
      change(item);
      expect(
          PluginCatalog.parse(catalogJson([item]))
              .single
              .requiresAppUpdate('99.0.0'),
          isTrue);
    }
  });

  test(
      'network catalogs require a valid signature and retain its exact envelope',
      () async {
    final payload = catalogJson([catalogItem(version: '2.0.0')]);
    var response = await signer.sign(payload);
    final catalog = PluginCatalog(
        signatureVerifier: signer.verifier,
        clientFactory: () => CatalogClient((_) async =>
            http.StreamedResponse(Stream.value(utf8.encode(response)), 200)));
    addTearDown(catalog.dispose);
    expect((await catalog.load()).single.requiresAppUpdate('1.3.10'), isFalse);
    expect(catalog.signedCatalog, response);
    response = payload;
    await expectLater(catalog.load(), failure('catalog'));
    final altered =
        jsonDecode(await signer.sign(payload)) as Map<String, dynamic>;
    altered['payload'] = base64Encode(utf8.encode(catalogJson([])));
    response = jsonEncode(altered);
    await expectLater(catalog.load(), failure('catalog'));
  });

  test('catalog cannot replace or expand an app-approved file inventory', () {
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (item) => (item['files'] as Map)['manifest.json'] = 'b' * 64,
      (item) => (item['files'] as Map)['extra.js'] = 'b' * 64,
      (item) => (item['files'] as Map).remove('README.md'),
      (item) => (item['package'] as Map)['path'] = 'dist/../evil.moduplugin',
      (item) =>
          (item['package'] as Map)['path'] = 'https://example.com/plugin.zip',
      (item) => item['minAppVersion'] = 'latest',
      (item) => item['review'] = {},
    ]) {
      final item = catalogItem();
      mutate(item);
      expect(
          () => PluginCatalog.parse(catalogJson([item])), failure('catalog'));
    }
  });

  test('published signed catalog interoperates with the production verifier',
      () async {
    final signed =
        await File('test/fixtures/plugins/catalog.signed.json').readAsString();
    final catalog = PluginCatalog(
        clientFactory: () => CatalogClient((_) async =>
            http.StreamedResponse(Stream.value(utf8.encode(signed)), 200)));
    addTearDown(catalog.dispose);
    final entries = await catalog.load();
    expect(
        entries.map((entry) => entry.id).toSet(),
        containsAll({
          'com.modu.private-books',
          'com.modu.text-tools',
          'com.example.prompt-pack',
        }));
    expect(entries.every((entry) => entry.supported), isTrue);
    expect(catalog.signedCatalog, signed);
  });

  test('requests use only the official source and refuse redirects', () async {
    for (final source in PluginCatalog.sources.entries) {
      final requests = <Uri>[];
      final client = CatalogClient((request) async {
        requests.add(request.url);
        expect(request.followRedirects, isFalse);
        return http.StreamedResponse(const Stream.empty(), 302,
            headers: {'location': 'https://example.com/elsewhere'});
      });
      final catalog =
          PluginCatalog(sourceId: source.key, clientFactory: () => client);
      addTearDown(catalog.dispose);
      await expectLater(catalog.load(), failure('network'));
      expect(requests.first.toString(), '${source.value}catalog.json');
      expect(requests.length, source.key == 'gitee' ? 2 : 1);
      if (source.key == 'gitee') {
        expect(requests.last.toString(),
            'https://gitee.com/api/v5/repos/sobranie2406/modu-plugin/contents/catalog.json?ref=main');
      }
      expect(client.closed, isTrue);
    }
  });

  test('source changes cancel old requests and clear old verified selections',
      () async {
    final oldSigned = await signer.sign(catalogJson([catalogItem()]));
    final newItem = catalogItem()..['name'] = {'en': 'Gitee mirror'};
    final newSigned = await signer.sign(catalogJson([newItem]));
    final lateResponse = Completer<http.StreamedResponse>();
    var githubLoads = 0;
    final catalog = PluginCatalog(
        signatureVerifier: signer.verifier,
        clientFactory: () => CatalogClient((request) async {
              if (request.url.toString() ==
                  '${PluginCatalog.sources['github']}catalog.json') {
                if (++githubLoads > 1) return lateResponse.future;
                return http.StreamedResponse(
                    Stream.value(utf8.encode(oldSigned)), 200);
              }
              expect(request.url.toString(),
                  '${PluginCatalog.sources['gitee']}catalog.json');
              return http.StreamedResponse(
                  Stream.value(utf8.encode(newSigned)), 200);
            }));
    addTearDown(catalog.dispose);
    final oldEntry = (await catalog.load()).single;
    final pending = expectLater(catalog.load(), failure('cancelled'));
    await catalog.changeSource('gitee');
    await pending;
    expect(() => catalog.signedCatalog, throwsA(isA<PluginCatalogFailure>()));
    await expectLater(catalog.download(oldEntry), failure('unapproved'));
    expect((await catalog.load()).single.name.resolve('en'), 'Gitee mirror');
    lateResponse.complete(
        http.StreamedResponse(Stream.value(utf8.encode(oldSigned)), 200));
    await Future<void>.delayed(Duration.zero);
    expect(catalog.signedCatalog, newSigned);
    expect(() => catalog.changeSource('https://example.com/'),
        throwsArgumentError);
    expect(() => PluginCatalog(sourceId: 'custom'), throwsArgumentError);
  });

  test('Gitee permits one official same-path CDN redirect', () async {
    final signed = await signer.sign(catalogJson([catalogItem()]));
    final origin = Uri.parse('${PluginCatalog.sources['gitee']}catalog.json');
    final target = Uri.https('raw.giteeusercontent.com', origin.path,
        {'signature': 'temporary-token'});
    final requests = <Uri>[];
    final catalog = PluginCatalog(
        sourceId: 'gitee',
        signatureVerifier: signer.verifier,
        clientFactory: () => CatalogClient((request) async {
              requests.add(request.url);
              expect(request.followRedirects, isFalse);
              if (requests.length == 1) {
                return http.StreamedResponse(const Stream.empty(), 302,
                    headers: {'location': target.toString()});
              }
              expect(request.url, target);
              return http.StreamedResponse(
                  Stream.value(utf8.encode(signed)), 200);
            }));
    addTearDown(catalog.dispose);
    expect((await catalog.load()).single.supported, isTrue);
    expect(requests, [origin, target]);
    expect(catalog.signedCatalog, signed);
  });

  test('Gitee rejects foreign paths, malformed CDN grants and second redirects',
      () async {
    final path =
        Uri.parse('${PluginCatalog.sources['gitee']}catalog.json').path;
    for (final destination in [
      'https://example.com$path?signature=token',
      'https://raw.giteeusercontent.com/other?signature=token',
      'http://raw.giteeusercontent.com$path?signature=token',
      'https://raw.giteeusercontent.com:444$path?signature=token',
      'https://user@raw.giteeusercontent.com$path?signature=token',
      'https://raw.giteeusercontent.com$path?signature=token#fragment',
      'https://raw.giteeusercontent.com$path?signature=',
      'https://raw.giteeusercontent.com$path?signature=one&signature=two',
      'https://raw.giteeusercontent.com$path?signature=token&other=1',
      'https://raw.giteeusercontent.com$path',
    ]) {
      var calls = 0;
      final catalog = PluginCatalog(
          sourceId: 'gitee',
          clientFactory: () => CatalogClient((_) async {
                calls++;
                return http.StreamedResponse(const Stream.empty(), 302,
                    headers: {'location': destination});
              }));
      await expectLater(catalog.load(), failure('network'));
      expect(calls, 2);
      await catalog.dispose();
    }
    var calls = 0;
    final catalog = PluginCatalog(
        sourceId: 'gitee',
        clientFactory: () => CatalogClient((_) async {
              calls++;
              return http.StreamedResponse(const Stream.empty(), 302, headers: {
                'location':
                    'https://raw.giteeusercontent.com$path?signature=token',
              });
            }));
    addTearDown(catalog.dispose);
    await expectLater(catalog.load(), failure('network'));
    expect(calls, 3);
  });

  test('Gitee contents fallback verifies catalogue and every artifact',
      () async {
    final payload = await PluginCatalogSignature().decode(
        await File('test/fixtures/plugins/catalog.signed.json').readAsString());
    final artifacts = <String, List<int>>{};
    for (final item in payload['plugins'] as List) {
      final package = item['package'] as Map;
      final data = utf8.encode('fixture artifact ${item['id']}');
      package['sha256'] = sha256.convert(data).toString();
      artifacts[package['path'] as String] = data;
    }
    artifacts['catalog.json'] =
        utf8.encode(await signer.sign(jsonEncode(payload)));
    final temporary = await Directory.systemTemp.createTemp('plugin-api-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final apiPaths = <String>[];
    final catalog = PluginCatalog(
        sourceId: 'gitee',
        signatureVerifier: signer.verifier,
        cacheDirectory: () async => temporary,
        clientFactory: () => CatalogClient((request) async {
              expect(request.followRedirects, isFalse);
              expect(request.headers.containsKey('authorization'), isFalse);
              if (request.url.path.contains('/raw/main/')) {
                return http.StreamedResponse(const Stream.empty(), 503);
              }
              const prefix = '/api/v5/repos/sobranie2406/modu-plugin/contents/';
              expect(request.url.host, 'gitee.com');
              expect(request.url.path.startsWith(prefix), isTrue);
              expect(request.url.queryParameters, {'ref': 'main'});
              final path = request.url.path.substring(prefix.length);
              apiPaths.add(path);
              final data = artifacts[path]!;
              return http.StreamedResponse(
                  Stream.value(utf8.encode(jsonEncode({
                    'path': path,
                    'encoding': 'base64',
                    'size': data.length,
                    'content': base64Encode(data),
                    'download_url': 'https://example.com/ignored',
                  }))),
                  200);
            }));
    addTearDown(catalog.dispose);
    final entries = await catalog.load();
    for (final entry in entries) {
      final download = await catalog.download(entry);
      expect(await download.file.readAsBytes(), artifacts[entry.packagePath]);
      await download.dispose();
    }
    expect(
        apiPaths, ['catalog.json', ...entries.map((item) => item.packagePath)]);
  });

  test('Gitee API wrappers require exact paths, base64 and decoded sizes',
      () async {
    final data = utf8.encode(await signer.sign(catalogJson([catalogItem()])));
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (wrapper) => wrapper['path'] = 'other.json',
      (wrapper) => wrapper['encoding'] = 'plain',
      (wrapper) => wrapper['size'] = data.length + 1,
      (wrapper) => wrapper['content'] = '%not-base64',
    ]) {
      final wrapper = <String, dynamic>{
        'path': 'catalog.json',
        'encoding': 'base64',
        'size': data.length,
        'content': base64Encode(data)
      };
      mutate(wrapper);
      final catalog = PluginCatalog(
          sourceId: 'gitee',
          signatureVerifier: signer.verifier,
          clientFactory: () => CatalogClient((request) async =>
              request.url.path.contains('/raw/main/')
                  ? http.StreamedResponse(const Stream.empty(), 503)
                  : http.StreamedResponse(
                      Stream.value(utf8.encode(jsonEncode(wrapper))), 200)));
      await expectLater(catalog.load(), failure('catalog'));
      await catalog.dispose();
    }
  });

  test('Gitee never falls back for signature or checksum failures', () async {
    var requests = 0;
    var response = catalogJson([catalogItem()]);
    final bytes = utf8.encode('actual bytes');
    final catalog = PluginCatalog(
        sourceId: 'gitee',
        signatureVerifier: signer.verifier,
        clientFactory: () => CatalogClient((request) async {
              requests++;
              expect(request.url.path.contains('/api/'), isFalse);
              final data = request.url.path.endsWith('catalog.json')
                  ? utf8.encode(response)
                  : bytes;
              return http.StreamedResponse(Stream.value(data), 200);
            }));
    addTearDown(catalog.dispose);
    await expectLater(catalog.load(), failure('catalog'));
    expect(requests, 1);
    response = await signer.sign(catalogJson([catalogItem(digest: 'b' * 64)]));
    final entry = (await catalog.load()).single;
    await expectLater(catalog.download(entry), failure('checksum'));
    expect(requests, 3);
  });

  test('Gitee fallback shares the raw request deadline and cancellation',
      () async {
    var calls = 0;
    final stalled = PluginCatalog(
        sourceId: 'gitee',
        timeout: const Duration(milliseconds: 5),
        clientFactory: () => CatalogClient((_) {
              calls++;
              return Completer<http.StreamedResponse>().future;
            }));
    addTearDown(stalled.dispose);
    await expectLater(stalled.load(), failure('network'));
    expect(calls, 1);
    final enteredApi = Completer<void>();
    final catalog = PluginCatalog(
        sourceId: 'gitee',
        clientFactory: () => CatalogClient((request) async {
              if (request.url.path.contains('/raw/main/')) {
                return http.StreamedResponse(const Stream.empty(), 503);
              }
              enteredApi.complete();
              return Completer<http.StreamedResponse>().future;
            }));
    addTearDown(catalog.dispose);
    final pending = expectLater(catalog.load(), failure('cancelled'));
    await enteredApi.future;
    await catalog.cancel();
    await pending;
  });

  test(
      'Gitee uses canonical GitHub identity and the same signature verification',
      () async {
    final mirrorIdentity =
        jsonDecode(catalogJson([catalogItem()])) as Map<String, dynamic>;
    mirrorIdentity['repository'] = 'https://gitee.com/sobranie2406/modu-plugin';
    var response = await signer.sign(jsonEncode(mirrorIdentity));
    final catalog = PluginCatalog(
        sourceId: 'gitee',
        signatureVerifier: signer.verifier,
        clientFactory: () => CatalogClient((_) async =>
            http.StreamedResponse(Stream.value(utf8.encode(response)), 200)));
    addTearDown(catalog.dispose);
    await expectLater(catalog.load(), failure('catalog'));
    response = catalogJson([catalogItem()]);
    await expectLater(catalog.load(), failure('catalog'));
    response = await signer.sign(catalogJson([catalogItem()]));
    expect((await catalog.load()).single.supported, isTrue);
  });

  test('actual streamed bytes and total elapsed time are bounded', () async {
    final oversized = PluginCatalog(
        clientFactory: () => CatalogClient((_) async => http.StreamedResponse(
            Stream.value(List.filled(PluginCatalog.maxCatalogBytes + 1, 1)),
            200)));
    addTearDown(oversized.dispose);
    await expectLater(oversized.load(), failure('size'));
    final stalled = PluginCatalog(
        timeout: const Duration(milliseconds: 5),
        clientFactory: () =>
            CatalogClient((_) => Completer<http.StreamedResponse>().future));
    addTearDown(stalled.dispose);
    await expectLater(stalled.load(), failure('network'));
  });

  test('cancel aborts a pending load without waiting for the HTTP response',
      () async {
    final catalog = PluginCatalog(
        clientFactory: () =>
            CatalogClient((_) => Completer<http.StreamedResponse>().future));
    addTearDown(catalog.dispose);
    final pending = expectLater(catalog.load(), failure('cancelled'));
    await catalog.cancel();
    await pending;
  });

  test(
      'downloads verify SHA before creating a file and clean app-cache artifacts',
      () async {
    final temporary =
        await Directory.systemTemp.createTemp('plugin-catalog-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final data = utf8.encode('test package bytes');
    final item = catalogItem(digest: sha256.convert(data).toString());
    var envelope = await signer.sign(catalogJson([item]));
    var directoryCalls = 0;
    final catalog = PluginCatalog(
      signatureVerifier: signer.verifier,
      cacheDirectory: () async {
        directoryCalls++;
        return temporary;
      },
      clientFactory: () => CatalogClient((request) async {
        if (request.url.toString() == '${PluginCatalog.source}catalog.json') {
          return http.StreamedResponse(
              Stream.value(utf8.encode(envelope)), 200);
        }
        expect(request.url.toString(),
            '${PluginCatalog.source}${item['package']['path']}');
        return http.StreamedResponse(Stream.value(data), 200);
      }),
    );
    addTearDown(catalog.dispose);
    final entry = (await catalog.load()).single;
    final download = await catalog.download(entry);
    expect(await download.file.readAsBytes(), data);
    expect(directoryCalls, 1);
    await download.dispose();
    expect(await download.file.exists(), isFalse);
    item['package']['sha256'] = 'b' * 64;
    envelope = await signer.sign(catalogJson([item]));
    final wrongChecksum = (await catalog.load()).single;
    await expectLater(catalog.download(wrongChecksum), failure('checksum'));
    expect(directoryCalls, 1);
    await expectLater(
        catalog.download(
            PluginCatalog.parse(catalogJson([catalogItem(version: '2.0.0')]))
                .single),
        failure('unapproved'));
    item['package']['sha256'] = sha256.convert(data).toString();
    envelope = await signer.sign(catalogJson([item]));
    final another = await catalog.download((await catalog.load()).single);
    await catalog.cancel();
    expect(await another.file.exists(), isFalse);
  });
}
