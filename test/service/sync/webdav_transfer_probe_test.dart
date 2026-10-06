import 'dart:io';
import 'dart:convert';

import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final auth in ['Basic', 'Digest', 'anonymous']) {
    test('$auth transfer probes preserve authentication and explicit ping',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final temp =
          await Directory.systemTemp.createTemp('modu-transfer-probe-');
      var options = 0;
      var deny = false;
      server.listen((request) async {
        await request.drain<void>();
        if (request.method == 'OPTIONS') options++;
        final response = request.response;
        if (auth != 'anonymous' &&
            request.headers.value('authorization') == null) {
          response.statusCode = 401;
          response.headers.set(
              'www-authenticate',
              auth == 'Basic'
                  ? 'Basic realm="test"'
                  : 'Digest realm="test", nonce="fixed-nonce", qop="auth", algorithm=MD5');
        } else if (request.method == 'GET') {
          response.statusCode = deny ? 403 : 200;
          if (!deny) response.add(utf8.encode('synthetic book'));
        } else {
          response.statusCode = 200;
        }
        await response.close();
      });
      try {
        final client = WebdavClient(
            url: 'http://127.0.0.1:${server.port}',
            username: 'test',
            password: 'test');
        await client.ping();
        final initial = options;
        await client.downloadFile('one', '${temp.path}/one');
        await client.downloadFile('two', '${temp.path}/two');
        expect(await File('${temp.path}/two').readAsString(), 'synthetic book');
        expect(options, initial + (auth == 'Basic' ? 0 : 2));
        final beforePing = options;
        await client.ping();
        expect(options, beforePing + 1);
        if (auth == 'Basic') {
          deny = true;
          await expectLater(
              client.downloadFile('denied', '${temp.path}/denied'),
              throwsA(isA<DioException>()));
          deny = false;
          final beforeRetry = options;
          await client.downloadFile(
              'after-denial', '${temp.path}/after-denial');
          expect(options, beforeRetry + 1);
        }
      } finally {
        await server.close(force: true);
        await temp.delete(recursive: true);
      }
    });
  }
}
