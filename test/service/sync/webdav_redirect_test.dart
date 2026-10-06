import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late WebdavClient client;
  final calls = <String>[];
  final depths = <String?>[];
  final bodies = <String>[];
  var status = 301;
  var finalStatus = 207;
  var loop = false;
  var resourceMissing = false;
  var stripSlash = false;
  String? location;
  String props(String path) => '<d:response><d:href>$path</d:href>'
      '${resourceMissing ? '<d:status>HTTP/1.1 404 Not Found</d:status>' : '<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype>'
          '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'}'
      '</d:response>';
  setUp(() async {
    calls.clear();
    depths.clear();
    bodies.clear();
    status = 301;
    finalStatus = 207;
    loop = false;
    resourceMissing = false;
    stripSlash = false;
    location = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add('${request.method} ${request.uri}');
      depths.add(request.headers.value('depth'));
      bodies.add(await utf8.decoder.bind(request).join());
      final shouldRedirect = loop ||
          (stripSlash
              ? request.uri.path.endsWith('/')
              : !request.uri.path.endsWith('/'));
      if (shouldRedirect) {
        request.response.statusCode = status;
        request.response.headers.set(
            'location',
            location ??
                (request.uri.path.endsWith('/')
                    ? request.uri.path.substring(0, request.uri.path.length - 1)
                    : '${request.uri.path}/'));
      } else {
        request.response.statusCode = finalStatus;
        request.response.headers.contentType =
            ContentType('application', 'xml');
        request.response.write(
            '<d:multistatus xmlns:d="DAV:">${props(request.uri.path)}'
            '${request.headers.value('depth') == '1' ? props('${request.uri.path.replaceFirst(RegExp(r'/$'), '')}/a/') : ''}'
            '</d:multistatus>');
      }
      await request.response.close();
    });
    client = WebdavClient(
        url: 'http://127.0.0.1:${server.port}/dav/library',
        username: 'fixture',
        password: 'private-password');
  });
  tearDown(() => server.close(force: true));

  for (final code in [301, 302, 307, 308]) {
    for (final path in ['modu/record-log-v1', 'modu/record-log-v1/a']) {
      test(
          'HTTP $code normalizes directory $path with PROPFIND body and Depth intact',
          () async {
        status = code;
        expect((await client.readProps(path))?.isDir, isTrue);
        expect(calls,
            ['PROPFIND /dav/library/$path', 'PROPFIND /dav/library/$path/']);
        expect(depths, ['0', '0']);
        expect(bodies.first, contains('getetag'));
        expect(bodies[1], bodies[0]);
      });
    }
  }

  for (final path in [
    'modu',
    'modu/data/file',
    'modu/data/cover',
    'modu/record-log-v1'
  ]) {
    test('Depth-one listing tolerates the reverse slash redirect: $path',
        () async {
      stripSlash = true;
      final files = path.contains('record-log')
          ? await client.readSyncDirectory(path)
          : await client.safeReadDir(path);
      expect(files.single.name, 'a');
      expect(files.single.isDir, isTrue);
      expect(calls,
          ['PROPFIND /dav/library/$path/', 'PROPFIND /dav/library/$path']);
      expect(depths, ['1', '1']);
      expect(bodies[0], bodies[1]);
    });
  }

  test('directory property lookup retains encoded literal characters',
      () async {
    stripSlash = true;
    expect((await client.readProps('modu/中文 #100% %2F/'))?.isDir, isTrue);
    expect(calls[0],
        'PROPFIND /dav/library/modu/%E4%B8%AD%E6%96%87%20%23100%25%20%252F/');
    expect(calls[1], calls[0].substring(0, calls[0].length - 1));
  });

  for (final target in [
    '/dav/elsewhere/',
    '/dav/library/modu/record-log-v1/?new=1',
    '/dav/library/modu/record-log-v1/#fragment',
    'file:///tmp/book',
    'https://127.0.0.1/dav/library/modu/record-log-v1/'
  ]) {
    test('reject unsafe or different-resource Location $target', () async {
      location = target;
      await expectLater(
          client.readProps('modu/record-log-v1'), throwsA(isA<DioException>()));
      expect(calls, hasLength(1));
    });
  }

  test('redirect does not send requests or credentials to a different origin',
      () async {
    status =
        302; // The upstream req() used to follow this even with redirects disabled.
    final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var received = 0;
    other.listen((request) async {
      received++;
      await request.response.close();
    });
    try {
      location =
          'http://127.0.0.1:${other.port}/dav/library/modu/record-log-v1/';
      await expectLater(
          client.readProps('modu/record-log-v1'), throwsA(isA<DioException>()));
      expect(received, 0);
      expect(calls, hasLength(1));
    } finally {
      await other.close(force: true);
    }
  });

  test('slash redirect loop is bounded', () async {
    loop = true;
    await expectLater(
        client.readProps('modu/record-log-v1'), throwsA(isA<DioException>()));
    expect(calls, hasLength(2));
  });
  test('303 cannot change PROPFIND into GET', () async {
    status = 303;
    await expectLater(
        client.readProps('modu/record-log-v1'), throwsA(isA<DioException>()));
    expect(calls, hasLength(1));
  });
  test('a database file must never be retried as a directory', () async {
    await expectLater(
        client.readProps('modu/database8.db'), throwsA(isA<DioException>()));
    expect(calls, ['PROPFIND /dav/library/modu/database8.db']);
  });
  for (final missingInXml in [false, true]) {
    test(
        'redirected ${missingInXml ? '207/404' : '404'} is not empty cloud metadata',
        () async {
      finalStatus = missingInXml ? 207 : 404;
      resourceMissing = missingInXml;
      await expectLater(
          client.readProps('modu/record-log-v1'), throwsFormatException);
      expect(calls, hasLength(2));
    });
    test(
        'safeReadDir never creates a directory after redirected ${missingInXml ? '207/404' : '404'}',
        () async {
      stripSlash = true;
      finalStatus = missingInXml ? 207 : 404;
      resourceMissing = missingInXml;
      await expectLater(client.safeReadDir('modu'), throwsFormatException);
      expect(calls, hasLength(2));
      expect(calls.every((c) => c.startsWith('PROPFIND ')), isTrue);
    });
  }
  test('conditional database PUT remains non-redirecting', () async {
    status = 302;
    final temp = await Directory.systemTemp.createTemp('modu-put-redirect-');
    try {
      final file =
          await File('${temp.path}/test.db').writeAsString('test-only');
      await expectLater(
          client.uploadFileConditionally(file.path, 'modu/database8.db',
              createOnly: true),
          throwsA(isA<DioException>()));
      expect(calls, ['PUT /dav/library/modu/database8.db']);
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
