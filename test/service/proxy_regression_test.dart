import 'dart:io';
import 'package:anx_reader/service/network/http_proxy_overrides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an unavailable proxy cannot report success by connecting directly',
      () async {
    final target = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final unavailablePort = proxy.port;
    await proxy.close();
    var directRequests = 0;
    target.listen((request) {
      directRequests++;
      request.response.close();
    });
    try {
      final result = await AnxHttpProxyOverrides.testProxy('127.0.0.1',
          unavailablePort, 'http://127.0.0.1:${target.port}/fixture');
      expect(result, isFalse);
      expect(directRequests, 0);
    } finally {
      await target.close(force: true);
    }
  });
}
