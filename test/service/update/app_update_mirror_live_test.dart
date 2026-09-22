import 'dart:io';

import 'package:anx_reader/service/update/app_update.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit network opt-in for release operations. Uses no account or API keys,
// downloads metadata only, and never installs anything.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('public Gitee update manifest works without GitHub availability',
      () async {
    final original = HttpOverrides.current;
    HttpOverrides.global = null;
    final transport = UpdateTransport();
    final hosts = <String>[];
    transport.dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      hosts.add(r.uri.host);
      if (r.uri.host == 'api.github.com') {
        h.reject(DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
            error: 'Simulated unavailable upstream'));
      } else {
        h.next(r);
      }
    }));
    try {
      final release = await transport.latest('android', 'android_arm64');
      expect(release.fromMirror, isTrue);
      expect(release.asset, isNotNull);
      expect(release.asset!.mirrorUrl, startsWith(moduMirrorReleasePage));
      expect(hosts.first, 'api.github.com');
      expect(hosts, contains('gitee.com'));
      expect(hosts, contains('raw.giteeusercontent.com'));
    } finally {
      transport.dio.close(force: true);
      HttpOverrides.global = original;
    }
  },
      skip: !const bool.fromEnvironment('MODU_VERIFY_UPDATE_MIRROR'),
      timeout: const Timeout(Duration(minutes: 1)));
}
