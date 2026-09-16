import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:anx_reader/service/update/app_update.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class Adapter implements HttpClientAdapter {
  Adapter(this.handler);
  final FutureOr<ResponseBody> Function(RequestOptions) handler;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

final payload = utf8.encode('synthetic installer bytes — not executable');
UpdateAsset get asset => UpdateAsset(
    'Modu-1.0.9-android-arm64.apk',
    '$moduReleasePage/download/v1.0.9/Modu-1.0.9-android-arm64.apk',
    payload.length,
    sha256.convert(payload).toString());

Map<String, dynamic> releaseJson() => {
      'tag_name': 'v1.0.9',
      'draft': false,
      'prerelease': false,
      'body': 'Release notes',
      'assets': [
        <String, dynamic>{
          'name': asset.name,
          'browser_download_url': asset.url,
          'state': 'uploaded',
          'size': asset.size,
          'digest': 'sha256:${asset.digest}',
        }
      ],
    };
Map<String, dynamic> mirrorJson() =>
    {...releaseJson(), 'modu_update_schema': 1};
UpdateRelease parse(Map<String, dynamic> json) =>
    UpdateRelease.parse(json, platform: 'android', abi: 'android_arm64');

class ControlledTransport extends UpdateTransport {
  Future<UpdateRelease> Function()? response;
  int checks = 0, downloads = 0;
  @override
  Future<UpdateRelease> latest(String platform, String abi) async {
    checks++;
    return response != null ? await response!() : parse(releaseJson());
  }

  @override
  Future<File> download(UpdateAsset a, Directory d, CancelToken c,
      void Function(int, int) progress) async {
    downloads++;
    await d.create(recursive: true);
    return File('${d.path}/${a.name}').writeAsBytes(payload);
  }
}

void main() {
  test('semantic version ordering, prerelease upgrade, no build-only downgrade',
      () {
    expect(isNewerRelease('1.0.10', '1.0.9+10026'), isTrue);
    expect(isNewerRelease('1.0.9', '1.0.9-beta.1+10026'), isTrue);
    expect(isNewerRelease('1.0.9', '1.0.9+10026'), isFalse);
    expect(isNewerRelease('1.0.9', '1.1.0'), isFalse);
    expect(() => isNewerRelease('v1.0.9', '1.0.8'), throwsFormatException);
    expect(
        () => isNewerRelease('1.0.9', 'not-a-version'), throwsFormatException);
  });

  test(
      'all nine release assets match process ABI; unsupported ABIs are refused',
      () {
    for (final platform in ['android', 'windows', 'macos', 'linux']) {
      for (final arch in ['arm64', 'x64']) {
        expect(updateAssetName('1.0.9', platform, '${platform}_$arch'),
            startsWith('Modu-1.0.9-$platform-$arch'));
      }
    }
    expect(updateAssetName('1.0.9', 'ios', 'ios_arm64'),
        'Modu-1.0.9-ios-arm64.ipa');
    expect(updateAssetName('1.0.9', 'ios', 'ios_x64'), isNull);
    expect(updateAssetName('1.0.9', 'android', 'android_arm'), isNull);
    expect(updateAssetName('1.0.9', 'linux', 'linux_riscv64'), isNull);
  });

  test(
      'release parser accepts only stable releases and verified matching assets',
      () {
    expect(parse(releaseJson()).asset?.digest, asset.digest);
    for (final mutation in [
      {'draft': true},
      {'prerelease': true},
      {'tag_name': 'v1.0.9-beta.1'},
      {'tag_name': '../../evil'},
    ]) {
      expect(
          () => parse({...releaseJson(), ...mutation}), throwsFormatException);
    }
    for (final mutation in [
      {'digest': null},
      {'digest': 'sha1:abc'},
      {'size': 0},
      {'state': 'uploading'},
      {'browser_download_url': 'https://example.com/installer.apk'},
      {'browser_download_url': '${asset.url}?replacement=true'},
    ]) {
      final json = releaseJson();
      (json['assets'] as List).first.addAll(mutation);
      expect(parse(json).asset, isNull);
    }
    final duplicate = releaseJson();
    (duplicate['assets'] as List).add((duplicate['assets'] as List).first);
    expect(parse(duplicate).asset, isNull);
  });

  test('redirect allowlist rejects HTTP, credentials and unrelated origins',
      () {
    for (final url in [
      'http://github.com/a',
      'https://github.com.evil.test/a',
      'https://user:secret@github.com/a',
      'https://127.0.0.1/a',
      'https://github.com:444/a'
    ]) {
      expect(UpdateTransport.trustedUrl(Uri.parse(url)), isFalse);
    }
    expect(
        UpdateTransport.trustedUrl(
            Uri.parse('https://release-assets.githubusercontent.com/a')),
        isTrue);
  });

  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-update-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  UpdateTransport transport(Adapter adapter) =>
      UpdateTransport(dio: Dio()..httpClientAdapter = adapter);

  test('fetches fixed official endpoint with bounded metadata', () async {
    final adapter = Adapter((o) => o.uri.host == 'gitee.com'
        ? ResponseBody.fromString('Not deployed', 404)
        : ResponseBody.fromString(jsonEncode(releaseJson()), 200));
    final release = await transport(adapter).latest('android', 'android_arm64');
    expect(release.version, '1.0.9');
    expect(adapter.requests.map((r) => r.uri.toString()),
        [moduMirrorManifest, moduReleaseApi]);
    expect(adapter.requests.every((r) => !r.followRedirects), isTrue);
    final oversized = Adapter(
        (o) => ResponseBody.fromBytes(List.filled(1024 * 1024 + 1, 32), 200));
    await expectLater(transport(oversized).latest('android', 'android_arm64'),
        throwsFormatException);
  });

  test('checks mirror first and uses it when GitHub is unavailable', () async {
    final adapter = Adapter((o) => o.uri.host == 'gitee.com'
        ? ResponseBody.fromString(jsonEncode(mirrorJson()), 200)
        : ResponseBody.fromString('unavailable', 503));
    final r = await transport(adapter).latest('android', 'android_arm64');
    expect(r.fromMirror, isTrue);
    expect(r.url, '$moduMirrorReleasePage/tag/v1.0.9');
    expect(r.asset!.mirrorUrl,
        '$moduMirrorReleasePage/download/v1.0.9/${asset.name}');
    expect(r.asset!.digest, asset.digest);
    expect(adapter.requests.first.uri.toString(), moduMirrorManifest);
  });

  test('Gitee raw CDN serves the exact official manifest without GitHub', () async {
    final adapter = Adapter((o) {
      if (o.uri.host == 'gitee.com') {
        return ResponseBody.fromString('', 302, headers: {
          'location': [
            'https://raw.giteeusercontent.com/sobranie2406/modureader/raw/master/updates/latest.json?signature=public-link'
          ]
        });
      }
      if (o.uri.host == 'raw.giteeusercontent.com') {
        return ResponseBody.fromString(jsonEncode(mirrorJson()), 200);
      }
      return ResponseBody.fromString('unavailable', 503);
    });
    final r = await transport(adapter).latest('android', 'android_arm64');
    expect(r.fromMirror, isTrue);
    expect(r.asset!.digest, asset.digest);
    expect(adapter.requests.map((r) => r.uri.host),
        ['gitee.com', 'raw.giteeusercontent.com', 'api.github.com']);
  });

  test('raw CDN rejects other repositories, paths, ports and lookalikes', () async {
    for (final url in [
      'https://raw.giteeusercontent.com/other/modureader/raw/master/updates/latest.json',
      'https://raw.giteeusercontent.com/sobranie2406/modureader/raw/master/evil.json',
      'https://raw.giteeusercontent.com.evil.test/sobranie2406/modureader/raw/master/updates/latest.json',
      'http://raw.giteeusercontent.com/sobranie2406/modureader/raw/master/updates/latest.json',
      'https://raw.giteeusercontent.com:444/sobranie2406/modureader/raw/master/updates/latest.json',
    ]) {
      final adapter = Adapter((o) => o.uri.host == 'gitee.com'
          ? ResponseBody.fromString('', 302, headers: {'location': [url]})
          : ResponseBody.fromString(jsonEncode(releaseJson()), 200));
      final r = await transport(adapter).latest('android', 'android_arm64');
      expect(r.fromMirror, isFalse);
      expect(adapter.requests.map((r) => r.uri.host),
          ['gitee.com', 'api.github.com']);
    }
  });

  test('healthy mirror has priority when both release records agree', () async {
    final adapter = Adapter((o) => ResponseBody.fromString(
        jsonEncode(o.uri.host == 'gitee.com' ? mirrorJson() : releaseJson()),
        200));
    final r = await transport(adapter).latest('android', 'android_arm64');
    expect(r.fromMirror, isTrue);
    expect(adapter.requests.length, 2);
  });

  test('stale mirror does not hide a newer upstream release', () async {
    final old =
        jsonDecode(jsonEncode(mirrorJson()).replaceAll('1.0.9', '1.0.8'));
    final adapter = Adapter((o) => ResponseBody.fromString(
        jsonEncode(o.uri.host == 'gitee.com' ? old : releaseJson()), 200));
    final r = await transport(adapter).latest('android', 'android_arm64');
    expect(r.version, '1.0.9');
    expect(r.fromMirror, isFalse);
  });

  test('same-version mirror digest disagreement uses upstream digest',
      () async {
    final mirror = mirrorJson();
    (mirror['assets'] as List).first['digest'] = 'sha256:${'a' * 64}';
    final adapter = Adapter((o) => ResponseBody.fromString(
        jsonEncode(o.uri.host == 'gitee.com' ? mirror : releaseJson()), 200));
    final r = await transport(adapter).latest('android', 'android_arm64');
    expect(r.fromMirror, isFalse);
    expect(r.asset!.digest, asset.digest);
  });

  test('malformed, missing or incomplete mirror metadata falls back', () async {
    for (final body in [
      '<html>Login required</html>',
      '[]',
      jsonEncode(releaseJson()), // Missing manifest schema.
      jsonEncode({...mirrorJson(), 'assets': []}),
      jsonEncode({...mirrorJson(), 'assets': {}}),
      jsonEncode({...mirrorJson(), 'draft': true}),
    ]) {
      final adapter = Adapter((o) => ResponseBody.fromString(
          o.uri.host == 'gitee.com' ? body : jsonEncode(releaseJson()), 200));
      final r = await transport(adapter).latest('android', 'android_arm64');
      expect(r.fromMirror, isFalse);
      expect(r.asset!.digest, asset.digest);
    }
  });

  test('slow mirror check is cancelled before checking GitHub', () async {
    final never = Completer<ResponseBody>();
    final adapter = Adapter((o) => o.uri.host == 'gitee.com'
        ? never.future
        : ResponseBody.fromString(jsonEncode(releaseJson()), 200));
    final t = UpdateTransport(
        dio: Dio()..httpClientAdapter = adapter,
        mirrorCheckTimeout: const Duration(milliseconds: 20));
    final r = await t.latest('android', 'android_arm64');
    expect(r.fromMirror, isFalse);
    expect(adapter.requests.length, 2);
  });

  test('mirror package is preferred without contacting GitHub', () async {
    final adapter = Adapter((o) => ResponseBody.fromBytes(payload, 200));
    final a = parse(releaseJson()).asset!;
    final file = await transport(adapter)
        .download(a, directory, CancelToken(), (_, __) {});
    expect(await file.readAsBytes(), payload);
    expect(adapter.requests.single.uri.toString(), a.mirrorUrl);
  });

  test('missing or corrupted mirror retries the same verified upstream asset',
      () async {
    for (final response in [
      ResponseBody.fromString('Not found', 404),
      ResponseBody.fromString('Unavailable', 503),
      ResponseBody.fromBytes(payload.sublist(1), 200),
      ResponseBody.fromBytes([...payload, 0], 200),
      ResponseBody.fromBytes(List.filled(payload.length, 42), 200),
    ]) {
      final a = parse(releaseJson()).asset!;
      final adapter = Adapter((o) => o.uri.host == 'gitee.com'
          ? response
          : ResponseBody.fromBytes(payload, 200));
      final progress = <int>[];
      final file = await transport(adapter)
          .download(a, directory, CancelToken(), (n, _) => progress.add(n));
      expect(await file.readAsBytes(), payload);
      expect(
          adapter.requests.map((r) => r.uri.toString()), [a.mirrorUrl, a.url]);
      expect(progress, contains(0));
      expect(await File('${file.path}.part').exists(), isFalse);
      await file.delete();
    }
  });

  test('cancelling mirror download never starts fallback', () async {
    final a = parse(releaseJson()).asset!;
    final adapter = Adapter((o) => ResponseBody.fromBytes(payload, 200));
    final cancel = CancelToken();
    await expectLater(
        transport(adapter)
            .download(a, directory, cancel, (_, __) => cancel.cancel()),
        throwsA(isA<DioException>()));
    expect(adapter.requests.length, 1);
    expect(await directory.list().toList(), isEmpty);
  });

  test('mirror redirect cannot escape repository or leak to unrelated hosts',
      () async {
    final a = parse(releaseJson()).asset!;
    for (final url in [
      'http://gitee.com/sobranie2406/modureader/attach_files/1/download',
      'https://gitee.com/another-owner/modureader/attach_files/1/download',
      'https://gitee.com/sobranie2406/modureader-evil/file',
      'https://evil.test/installer',
      'https://foruda.gitee.com/unrelated/installer',
      'https://foruda.gitee.com.evil.test/attach_file/installer',
      'https://github.com/someone/other-project',
    ]) {
      final adapter = Adapter((o) => o.uri.host == 'gitee.com'
          ? ResponseBody.fromString('', 302, headers: {
              'location': [url]
            })
          : ResponseBody.fromBytes(payload, 200));
      final file = await transport(adapter)
          .download(a, directory, CancelToken(), (_, __) {});
      expect(
          adapter.requests.map((r) => r.uri.toString()), [a.mirrorUrl, a.url]);
      await file.delete();
    }
  });

  test('supports same-repository Gitee attachment redirect', () async {
    final a = parse(releaseJson()).asset!;
    final adapter = Adapter((o) => o.uri.path.contains('/releases/download/')
        ? ResponseBody.fromString('', 302, headers: {
            'location': ['/sobranie2406/modureader/attach_files/123/download']
          })
        : ResponseBody.fromBytes(payload, 200));
    await transport(adapter).download(a, directory, CancelToken(), (_, __) {});
    expect(adapter.requests.length, 2);
    expect(adapter.requests.every((o) => o.uri.host == 'gitee.com'), isTrue);
  });

  test('both corrupt sources leave no installable file', () async {
    final a = parse(releaseJson()).asset!;
    final adapter =
        Adapter((o) => ResponseBody.fromBytes(payload.sublist(1), 200));
    await expectLater(
        transport(adapter).download(a, directory, CancelToken(), (_, __) {}),
        throwsFormatException);
    expect(adapter.requests.length, 2);
    expect(await directory.list().toList(), isEmpty);
  });

  test('Gitee attachment CDN verifies the same SHA without upstream download',
      () async {
    final a = parse(releaseJson()).asset!;
    final adapter = Adapter((o) {
      if (o.uri.path.contains('/releases/download/')) {
        return ResponseBody.fromString('', 302, headers: {
          'location': ['/sobranie2406/modureader/attach_files/123/download']
        });
      }
      if (o.uri.host == 'gitee.com') {
        return ResponseBody.fromString('', 302, headers: {
          'location': [
            'https://foruda.gitee.com/attach_file/123/${a.name}?token=public-link'
          ]
        });
      }
      return ResponseBody.fromBytes(payload, 200);
    });
    final t = transport(adapter);
    final file = await t.download(a, directory, CancelToken(), (_, __) {});
    expect(await t.verify(file, a), isTrue);
    expect(adapter.requests.map((r) => r.uri.host),
        ['gitee.com', 'gitee.com', 'foruda.gitee.com']);
  });

  test('verifies download size and SHA-256 before exposing the installer',
      () async {
    final adapter = Adapter((o) => ResponseBody.fromBytes(payload, 200));
    final received = <int>[];
    final t = transport(adapter);
    final file = await t.download(asset, directory, CancelToken(), (n, total) {
      received.add(n);
    });
    expect(await file.readAsBytes(), payload);
    expect(received.last, payload.length);
    expect(await File('${file.path}.part').exists(), isFalse);
    await t.download(asset, directory, CancelToken(), (_, __) {});
    expect(adapter.requests.length, 1,
        reason: 'Reuse only a verified cache file');
    await file.writeAsString('tampered');
    await t.download(asset, directory, CancelToken(), (_, __) {});
    expect(adapter.requests.length, 2);
    expect(await t.verify(file, asset), isTrue);
  });

  test('redirects to untrusted host fail without contacting that host',
      () async {
    final adapter = Adapter((o) => ResponseBody.fromString('', 302, headers: {
          'location': ['https://evil.test/update.apk']
        }));
    await expectLater(
        transport(adapter)
            .download(asset, directory, CancelToken(), (_, __) {}),
        throwsFormatException);
    expect(adapter.requests.length, 1);
    expect(await directory.list().toList(), isEmpty);
  });

  test('allows official GitHub asset CDN redirects', () async {
    final adapter = Adapter((o) => o.uri.host == 'github.com'
        ? ResponseBody.fromString('', 302, headers: {
            'location': ['https://release-assets.githubusercontent.com/blob']
          })
        : ResponseBody.fromBytes(payload, 200));
    await transport(adapter)
        .download(asset, directory, CancelToken(), (_, __) {});
    expect(adapter.requests.length, 2);
  });

  test('truncated, oversized and corrupted packages never become installable',
      () async {
    for (final bytes in [
      payload.sublist(1),
      [...payload, 0],
      List.filled(payload.length, 42)
    ]) {
      final adapter = Adapter((o) => ResponseBody.fromBytes(bytes, 200));
      await expectLater(
          transport(adapter)
              .download(asset, directory, CancelToken(), (_, __) {}),
          throwsFormatException);
      expect(await directory.list().toList(), isEmpty);
    }
  });

  test('cancel removes partial file and never renames it into an installer',
      () async {
    final cancel = CancelToken();
    final adapter = Adapter((o) => ResponseBody.fromBytes(payload, 200));
    await expectLater(
        transport(adapter)
            .download(asset, directory, cancel, (_, __) => cancel.cancel()),
        throwsA(isA<DioException>()));
    expect(await directory.list().toList(), isEmpty);
  });

  test('checking is single-flight and never downloads without consent',
      () async {
    final gate = Completer<UpdateRelease>();
    final t = ControlledTransport()..response = () => gate.future;
    final c = AppUpdateController(
        transport: t, installedVersion: () async => '1.0.8+10026');
    final first = c.check();
    await c.check();
    await Future<void>.delayed(Duration.zero);
    expect(t.checks, 1);
    expect(c.phase, UpdatePhase.checking);
    gate.complete(parse(releaseJson()));
    await first;
    expect(c.phase, UpdatePhase.available);
    expect(t.downloads, 0);
  });

  test('offline and rate limits are errors, never reported as up-to-date',
      () async {
    final t = ControlledTransport()
      ..response = () async => throw const SocketException('offline');
    final c = AppUpdateController(
        transport: t, installedVersion: () async => '1.0.8');
    await c.check();
    expect(c.phase, UpdatePhase.error);
    expect(c.error, 'network');
    t.response = () async => throw DioException(
        requestOptions: RequestOptions(),
        response: Response(requestOptions: RequestOptions(), statusCode: 403));
    await c.check();
    expect(c.error, 'rate_limit');
    t.response = () async => parse({...releaseJson(), 'tag_name': 'v1.0.7'});
    await c.check();
    expect(c.phase, UpdatePhase.current);
  });

  test(
      'install revalidates cache; opening installer is not installation success',
      () async {
    final t = ControlledTransport();
    final c = AppUpdateController(
        transport: t,
        installedVersion: () async => '1.0.8',
        directory: () async => directory);
    await c.check();
    await c.download();
    expect(c.phase, UpdatePhase.ready);
    var opened = 0;
    await c.install((_) async {
      opened++;
      return 'permission_required';
    });
    expect(opened, 1);
    expect(c.error, 'permission_required');
    expect(c.phase, UpdatePhase.ready);
    await c.downloaded!.writeAsString('tampered');
    await c.install((_) async {
      opened++;
      return 'opened';
    });
    expect(opened, 1);
    expect(c.phase, UpdatePhase.error);
    expect(c.error, 'integrity');
    expect(c.downloaded, isNull);
  });
}
