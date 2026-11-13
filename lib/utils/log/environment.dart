import 'dart:io';

import 'package:modu_reader/service/feedback/crash_diagnostics.dart';
import 'package:modu_reader/utils/app_version.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Uses the existing device-field allowlist, never the full device-info map.
class LogEnvironment {
  static Future<String> collect({
    @visibleForTesting bool? android,
    @visibleForTesting Future<String> Function()? appVersion,
    @visibleForTesting Future<String> Function()? deviceEnvironment,
    @visibleForTesting Future<WebViewPackageInfo?> Function()? webViewPackage,
    @visibleForTesting Duration timeout = const Duration(seconds: 2),
  }) async {
    Future<String> read(String label, Future<String> Function() load) async {
      try {
        final value = await Future.sync(load).timeout(timeout);
        return '$label: ${value.trim().isEmpty ? 'unavailable' : value}';
      } catch (_) {
        // Native diagnostics must not block startup/export or leak raw errors.
        return '$label: unavailable';
      }
    }

    String field(String? value) {
      final text =
          (value ?? '').replaceAll(RegExp(r'[^a-zA-Z0-9 ._,()+-]'), '').trim();
      return text.isEmpty
          ? 'unavailable'
          : text.substring(0, text.length.clamp(0, 100));
    }

    final isAndroid = android ?? Platform.isAndroid;
    final fields = await Future.wait([
      read('Modu version',
          () async => field(await (appVersion ?? getAppVersion)())),
      read('Device environment',
          deviceEnvironment ?? CrashDiagnostics.loadEnvironment),
      if (isAndroid)
        read('Android WebView provider', () async {
          final info = await (webViewPackage ??
              InAppWebViewController.getCurrentWebViewPackage)();
          return '${field(info?.packageName)}; version=${field(info?.versionName)}';
        }),
    ]);
    return 'Platform: ${isAndroid ? 'android' : Platform.operatingSystem}\n${fields.join('\n')}';
  }
}
