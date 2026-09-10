import 'dart:io';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late WebdavClient client;
  var status = 207;
  var malformed = false;
  String? xmlOverride;
  final calls = <String>[];
  final requestHeaders = <Map<String, String?>>[];
  const xml = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:"><d:response>
<d:href>/library/modu/database7.db</d:href><d:propstat><d:prop>
<d:resourcetype/><d:getcontentlength>32768</d:getcontentlength>
<d:getlastmodified>Wed, 09 Sep 2026 13:56:15 GMT</d:getlastmodified>
</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
</d:response></d:multistatus>''';
  setUp(() async {
    status = 207;
    malformed = false;
    xmlOverride = null;
    calls.clear();
    requestHeaders.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add('${request.method} ${request.uri.path}');
      requestHeaders.add({
        for (final key in ['depth', 'if-match', 'if-none-match'])
          key: request.headers.value(key)
      });
      await request.drain<void>();
      request.response.statusCode = request.method == 'OPTIONS'
          ? 200
          : request.method == 'MKCOL'
              ? 201
              : request.uri.path.endsWith('.db/')
                  ? 400
                  : status;
      request.response.headers.contentType = ContentType('application', 'xml');
      request.response.write(malformed ? '<bad>' : (xmlOverride ?? xml));
      await request.response.close();
    });
    client = WebdavClient(
        url: 'http://127.0.0.1:${server.port}/library',
        username: 'test',
        password: 'test');
  });
  tearDown(() => server.close(force: true));

  test('real WebDAV client reads database metadata under the configured parent',
      () async {
    final props = await client.readProps('modu/database7.db');
    expect(props?.size, 32768);
    expect(props?.mTime?.toUtc(), DateTime.utc(2026, 9, 9, 13, 56, 15));
    expect(calls.single, 'PROPFIND /library/modu/database7.db');
    expect(requestHeaders.single['depth'], '0');
  });
  test('Depth zero directory lookup preserves explicit slash', () async {
    xmlOverride = xml.replaceFirst('<d:resourcetype/>',
        '<d:resourcetype><d:collection/></d:resourcetype>');
    expect((await client.readProps('modu/data/file/'))?.isDir, isTrue);
    expect(calls.single, 'PROPFIND /library/modu/data/file/');
  });
  test('207 resource-level 404 is absent, but a missing property is not',
      () async {
    xmlOverride =
        '<d:multistatus xmlns:d="DAV:"><d:response><d:status>HTTP/1.1 404 Not Found</d:status></d:response></d:multistatus>';
    expect(await client.readProps('modu/database8.db'), isNull);
    xmlOverride = xml.replaceFirst('HTTP/1.1 200 OK', 'HTTP/1.1 404 Not Found');
    await expectLater(
        client.readProps('modu/database8.db'), throwsFormatException);
  });
  test('weak or absent ETag fails before any upload request', () async {
    for (final etag in [null, 'W/"weak"', 'not-quoted']) {
      await expectLater(
          client.uploadFileConditionally('/not-read.db', 'modu/database8.db',
              expectedETag: etag),
          throwsUnsupportedError);
    }
    expect(calls, isEmpty);
  });
  test(
      'first publish uses create-only and a conflict never retries unconditionally',
      () async {
    final temp =
        await Directory.systemTemp.createTemp('modu-create-only-test-');
    try {
      final file =
          await File('${temp.path}/fixture.db').writeAsString('fixture');
      status = 412;
      await expectLater(
          client.uploadFileConditionally(file.path, 'modu/database8.db',
              createOnly: true),
          throwsA(isA<DioException>()));
      expect(calls, ['PUT /library/modu/database8.db']);
      expect(requestHeaders.single['if-none-match'], '*');
      expect(requestHeaders.single['if-match'], isNull);
    } finally {
      await temp.delete(recursive: true);
    }
  });
  test('only HTTP 404 means absent', () async {
    status = 404;
    expect(await client.readProps('modu/database7.db'), isNull);
  });
  for (final code in [400, 401, 403, 500, 503]) {
    test('HTTP $code is an error, not an empty library', () async {
      status = code;
      await expectLater(
          client.readProps('modu/database7.db'), throwsA(isA<DioException>()));
    });
  }
  test('malformed listing is not reported as a missing database', () async {
    malformed = true;
    await expectLater(client.readProps('modu/database7.db'), throwsA(anything));
  });
  test('failed upload never deletes the existing cloud database first',
      () async {
    final temp = await Directory.systemTemp.createTemp('modu-upload-test-');
    try {
      final file = await File('${temp.path}/fixture.db')
          .writeAsString('synthetic upload');
      status = 500;
      await expectLater(client.uploadFile(file.path, 'modu/database7.db'),
          throwsA(isA<DioException>()));
      expect(calls.any((call) => call.startsWith('DELETE ')), isFalse);
      expect(calls, contains('PUT /library/modu/database7.db'));
    } finally {
      await temp.delete(recursive: true);
    }
  });
}
