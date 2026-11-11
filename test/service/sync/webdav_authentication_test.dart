import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _basic = 'Basic realm="DUFS"';
const _digest =
    'Digest realm="DUFS", nonce="fixed-nonce", qop="auth", algorithm=MD5';

String _hash(String value) => md5.convert(utf8.encode(value)).toString();

bool _authorized(HttpRequest request) {
  final header = request.headers.value('authorization') ?? '';
  if (header.startsWith('Basic ')) {
    return header ==
        'Basic ${base64Encode(utf8.encode('test:correct-password'))}';
  }
  if (!header.startsWith('Digest ')) return false;
  final fields = {
    for (final match in RegExp(r'(\w+)=(?:"([^"]*)"|([^,\s]+))')
        .allMatches(header.substring(7)))
      match[1]!: match[2] ?? match[3]!,
  };
  if (fields['username'] != 'test' ||
      fields['realm'] != 'DUFS' ||
      fields['nonce'] != 'fixed-nonce' ||
      fields['qop'] != 'auth' ||
      fields['uri'] == null) {
    return false;
  }
  final ha1 = _hash('test:DUFS:correct-password');
  final ha2 = _hash('${request.method}:${fields['uri']}');
  return fields['response'] ==
      _hash('$ha1:fixed-nonce:${fields['nc']}:${fields['cnonce']}:auth:$ha2');
}

void main() {
  late HttpServer server;
  late Directory temporary;
  late WebdavClient client;
  var challenges = <String>[];
  final calls = <String>[];
  final authenticatedSchemes = <String>[];
  final files = <String, List<int>>{};

  setUp(() async {
    challenges = [_digest, _basic];
    calls.clear();
    files.clear();
    authenticatedSchemes.clear();
    temporary = await Directory.systemTemp.createTemp('modu-auth-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      calls.add(request.method);
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final response = request.response;
      // dufs permits anonymous OPTIONS but protects the actual resources.
      if (request.method == 'OPTIONS') {
        response.statusCode = 200;
      } else if (!_authorized(request)) {
        response.statusCode = 401;
        response.headers.set('www-authenticate', challenges);
      } else {
        authenticatedSchemes
            .add(request.headers.value('authorization')!.split(' ').first);
        final path = request.uri.path;
        switch (request.method) {
          case 'PROPFIND':
            response.statusCode = 207;
            response.headers.contentType = ContentType('application', 'xml');
            response.write('<d:multistatus xmlns:d="DAV:"><d:response>'
                '<d:href>$path</d:href><d:propstat><d:prop>'
                '<d:resourcetype/><d:getcontentlength>3</d:getcontentlength>'
                '</d:prop><d:status>HTTP/1.1 200 OK</d:status>'
                '</d:propstat></d:response></d:multistatus>');
          case 'MKCOL':
            response.statusCode = 201;
          case 'PUT':
            files[path] = body;
            response.statusCode = 201;
          case 'GET':
            response.add(files[path]!);
          case 'DELETE':
            files.remove(path);
            response.statusCode = 204;
        }
      }
      await response.close();
    });
    client = WebdavClient(
        url: 'http://127.0.0.1:${server.port}',
        username: 'test',
        password: 'correct-password');
  });
  tearDown(() async {
    await server.close(force: true);
    await temporary.delete(recursive: true);
  });

  for (final variant in {
    'dufs Digest then Basic': [_digest, _basic],
    'Basic then Digest': [_basic, _digest],
    'combined Basic then Digest': ['$_basic, $_digest'],
    'combined Digest then Basic': ['$_digest, $_basic'],
    'quoted scheme text is not a challenge': [
      'Basic realm="ignored, Digest realm=\\"decoy\\""',
      _digest
    ],
    'Digest only': [_digest],
    'Basic only': [_basic],
    'repeated Basic': [_basic, _basic],
  }.entries) {
    test('${variant.key} authenticates protected properties and file transfers',
        () async {
      challenges = variant.value;
      await client.ping();
      expect(calls, ['OPTIONS']);
      expect((await client.readProps('modu/database7.db'))?.size, 3);
      await client.mkdirAll('modu/.test');
      final source =
          await File('${temporary.path}/source').writeAsString('abc');
      await client.uploadFile(source.path, 'modu/.test/book');
      final target = File('${temporary.path}/download');
      await client.downloadFile('modu/.test/book', target.path);
      expect(await target.readAsString(), 'abc');
      await client.remove('modu/.test/book');
      expect(files, isEmpty);
      expect(
          authenticatedSchemes,
          everyElement(variant.value.any((v) => v.contains('nonce='))
              ? 'Digest'
              : 'Basic'));
    });
  }

  test('invalid credentials retain the HTTP 401 and stop retrying', () async {
    client = WebdavClient(
        url: 'http://127.0.0.1:${server.port}',
        username: 'test',
        password: 'wrong-password');
    await expectLater(
        client.readProps('modu/database7.db'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 401)));
    expect(calls, ['PROPFIND', 'PROPFIND']);
    expect(authenticatedSchemes, isEmpty);
  });
}
