import 'dart:async';

import 'package:modu_reader/service/feedback/crash_diagnostics.dart';
import 'package:modu_reader/utils/log/environment.dart';
import 'package:modu_reader/utils/webView/webview_console_message.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'Android environment includes actual app/provider and allowlisted device fields',
      () async {
    final result = await LogEnvironment.collect(
      android: true,
      appVersion: () async => '1.3.3-beta.1+10158',
      deviceEnvironment: () async => CrashDiagnostics.formatEnvironment({
        'android': '8.1',
        'sdk': 27,
        'manufacturer': 'Xiaomi',
        'model': 'Test Phone',
        'version': '1.3.3-beta.1',
        'build': 10158,
        'abis': ['arm64-v8a'],
        'serial': 'PRIVATE-SERIAL',
        'androidId': 'PRIVATE-ID',
        'account': 'PRIVATE-ACCOUNT',
      }),
      webViewPackage: () async => WebViewPackageInfo(
          packageName: 'com.android.chrome', versionName: '70.0.3538.110'),
    );
    expect(result, contains('1.3.3-beta.1+10158'));
    expect(result, contains('Android: 8.1 (API 27)'));
    expect(result, contains('Xiaomi Test Phone'));
    expect(result, contains('com.android.chrome; version=70.0.3538.110'));
    expect(result, isNot(contains('PRIVATE')));
  });

  test('failed and hanging lookups retain other fields without raw errors',
      () async {
    final result = await LogEnvironment.collect(
      android: true,
      timeout: const Duration(milliseconds: 10),
      appVersion: () async => '1.3.3+10158',
      deviceEnvironment: () => throw StateError('PRIVATE-TOKEN'),
      webViewPackage: () => Completer<WebViewPackageInfo?>().future,
    );
    expect(result, contains('Modu version: 1.3.3+10158'));
    expect(result, contains('Device environment: unavailable'));
    expect(result, contains('Android WebView provider: unavailable'));
    expect(result, isNot(contains('PRIVATE')));
  });

  test('other platforms never invoke the Android WebView API', () async {
    final result = await LogEnvironment.collect(
      android: false,
      appVersion: () async => '1.3.3+10158',
      deviceEnvironment: () async => 'systemVersion: 18.0',
      webViewPackage: () => throw StateError('Android API must not run'),
    );
    expect(result, contains('systemVersion: 18.0'));
    expect(result, isNot(contains('Android WebView')));
  });

  test('version detector accepts new/old prefixes and missing UA safely', () {
    for (final prefix in ['ModuUA', 'AnxUA']) {
      expect(
          unsupportedWebviewVersion('$prefix Chrome/60.0', isApple: false), 60);
      expect(unsupportedWebviewVersion('$prefix Chrome/70.0', isApple: false),
          isNull);
      expect(
          unsupportedWebviewVersion('$prefix AppleWebKit/604.1', isApple: true),
          604);
      expect(
          unsupportedWebviewVersion('$prefix AppleWebKit/605.1', isApple: true),
          isNull);
    }
    for (final message in [
      'ModuUA',
      'ModuUA Unknown',
      'Book text Chrome/40.0'
    ]) {
      expect(unsupportedWebviewVersion(message, isApple: false), isNull);
    }
  });
}
