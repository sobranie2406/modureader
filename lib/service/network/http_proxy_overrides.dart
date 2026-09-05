import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';

class AnxHttpProxyOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) {
      final host = uri.host.toLowerCase();
      if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
        return 'DIRECT';
      }

      if (!Prefs().httpProxyEnabled) {
        return 'DIRECT';
      }

      final proxyHost = Prefs().httpProxyHost.trim();
      final proxyPort = Prefs().httpProxyPort;
      if (!_validProxy(proxyHost, proxyPort)) {
        throw StateError('代理地址或端口无效，请检查代理设置');
      }

      return 'PROXY $proxyHost:$proxyPort';
    };
    return client;
  }

  static Future<bool> testProxy(String host, int port, String testUrl) async {
    if (!_validProxy(host, port)) return false;
    final client = HttpClient();
    try {
      final uri = Uri.parse(testUrl);
      client.findProxy = (_) => 'PROXY $host:$port';
      client.connectionTimeout = const Duration(seconds: 8);

      final request = await client.getUrl(uri).timeout(
            const Duration(seconds: 8),
          );
      final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
      await response.drain<void>().timeout(const Duration(seconds: 8));
      client.close();
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static bool _validProxy(String host, int port) =>
      host.isNotEmpty &&
      !host.contains(RegExp(r'[;\s/]')) &&
      port > 0 &&
      port <= 65535;
}
