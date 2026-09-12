import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'row_sync_test.dart' show fixture, noteRow;

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late HttpServer server;
  late WebdavClient client;
  final files = <String, List<int>>{};
  final revisions = <String, int>{};
  final directories = <String>{};
  final calls = <String>[];
  var mode = 'strong';
  int? error;
  String? pageLink;
  String props(String path, bool dir) =>
      '<d:response><d:href>$path${dir ? '/' : ''}</d:href>'
      '<d:propstat><d:prop><d:resourcetype>${dir ? '<d:collection/>' : ''}</d:resourcetype>'
      '<d:getcontentlength>${files[path]?.length ?? 0}</d:getcontentlength>'
      '<d:getlastmodified>Sat, 12 Sep 2026 00:00:00 GMT</d:getlastmodified>'
      '${mode == 'none' ? '' : '<d:getetag>${mode == 'weak' ? 'W/' : ''}"${mode == 'constant' ? 1 : revisions[path] ?? 1}"</d:getetag>'}'
      '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
  setUp(() async {
    files.clear();
    revisions.clear();
    directories.clear();
    calls.clear();
    mode = 'strong';
    error = null;
    pageLink = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = WebdavClient(
        url: 'http://127.0.0.1:${server.port}/library',
        username: 'test',
        password: 'test');
    server.listen((request) async {
      final path = request.uri.path.replaceFirst(RegExp(r'/$'), '');
      calls.add('${request.method} $path');
      final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
      final response = request.response;
      if (error != null) {
        response.statusCode = error!;
        await response.close();
        return;
      }
      switch (request.method) {
        case 'OPTIONS':
          response.statusCode = 200;
        case 'MKCOL':
          response.statusCode = directories.add(path) ? 201 : 405;
          final parts = path.split('/');
          for (var i = 2; i < parts.length; i++) {
            directories.add(parts.take(i).join('/'));
          }
        case 'PUT':
          final stale = request.headers.value('if-match');
          final duplicate = request.headers.value('if-none-match') == '*' &&
              files.containsKey(path);
          final expected = '"${mode == 'constant' ? 1 : revisions[path] ?? 1}"';
          if (mode == 'reject-all' && stale != null) {
            response.statusCode = 412;
          } else if (mode == 'false-rejection' &&
              stale != null &&
              stale != expected) {
            files[path] = body;
            response.statusCode = 412;
          } else if (mode != 'ignored' &&
              (duplicate || stale != null && stale != expected)) {
            response.statusCode = 412;
          } else {
            files[path] = body;
            revisions[path] = (revisions[path] ?? 0) + 1;
            response.statusCode = 201;
          }
        case 'HEAD':
          response.statusCode = files.containsKey(path) ? 200 : 404;
          if (mode != 'none') {
            response.headers.set('etag',
                '${mode == 'weak' ? 'W/' : ''}"${revisions[path] ?? 1}"');
          }
        case 'GET':
          response.statusCode = files.containsKey(path) ? 200 : 404;
          if (files.containsKey(path)) response.add(files[path]!);
        case 'DELETE':
          files.remove(path);
          directories.remove(path);
          response.statusCode = 204;
        case 'PROPFIND':
          if (!files.containsKey(path) && !directories.contains(path)) {
            response.statusCode = 404;
            break;
          }
          response.statusCode = 207;
          response.headers.contentType = ContentType('application', 'xml');
          var children = <String>[];
          if (request.headers.value('depth') == '1') {
            children = {...files.keys, ...directories}
                .where((p) =>
                    p.startsWith('$path/') &&
                    !p.substring(path.length + 1).contains('/'))
                .toList()
              ..sort();
            if (pageLink != null) {
              children = request.uri.query.isEmpty
                  ? children.take(1).toList()
                  : children.skip(1).toList();
              if (request.uri.query.isEmpty) {
                response.headers.set('link', pageLink!);
              }
            }
          }
          response.write(
              '<d:multistatus xmlns:d="DAV:">${props(path, directories.contains(path))}'
              '${children.map((p) => props(p, directories.contains(p))).join()}</d:multistatus>');
        default:
          response.statusCode = 405;
      }
      await response.close();
    });
  });
  tearDown(() => server.close(force: true));

  for (final value in [
    'strong',
    'none',
    'weak',
    'constant',
    'ignored',
    'false-rejection',
    'reject-all'
  ]) {
    test('isolated HTTP capability check: $value', () async {
      mode = value;
      files['/library/modu/database8.db'] = utf8.encode('do-not-touch');
      expect(await client.supportsAtomicSyncWrites(), value == 'strong');
      expect(
          files, {'/library/modu/database8.db': utf8.encode('do-not-touch')});
      expect(calls.every((c) => !c.endsWith('/modu/database8.db')), isTrue);
      final count = calls.length;
      expect(await client.supportsAtomicSyncWrites(), value == 'strong');
      expect(calls.length, count);
    });
  }
  for (final code in [401, 403, 503]) {
    test('HTTP $code cannot trigger capability downgrade', () async {
      error = code;
      await expectLater(client.supportsAtomicSyncWrites(), throwsA(anything));
      expect(files, isEmpty);
    });
  }
  test('complete directory pagination follows only the same origin and path',
      () async {
    directories.add('/library/modu/record-log-v1');
    directories.add('/library/modu/record-log-v1/ab');
    directories.add('/library/modu/record-log-v1/cd');
    pageLink = '</library/modu/record-log-v1/?page=2>; rel="next"';
    final entries = await client.readSyncDirectory('modu/record-log-v1');
    expect(entries.map((e) => e.name).toSet(), {'ab', 'cd'});
    expect(calls.length, 2);
    calls.clear();
    pageLink = '<https://example.invalid/steal>; rel="next"';
    await expectLater(
        client.readSyncDirectory('modu/record-log-v1'), throwsFormatException);
    expect(calls.length, 1);
    pageLink = '</library/elsewhere/?page=2>; rel="next"';
    await expectLater(
        client.readSyncDirectory('modu/record-log-v1'), throwsFormatException);
  });
  for (final value in ['none', 'ignored', 'strong']) {
    test('real WebDAV engine round trip: $value', () async {
      mode = value;
      final temp = await Directory.systemTemp.createTemp('modu-http-sync-');
      final a = await fixture();
      final b = await fixture(bookId: 77);
      try {
        await a.insert('tb_notes', noteRow(1, 'desktop'));
        await RowSyncEngine(store: RowSyncStore(a), client: client, cache: temp)
            .synchronize();
        await b.insert('tb_notes', noteRow(77, 'phone'));
        await RowSyncEngine(store: RowSyncStore(b), client: client, cache: temp)
            .synchronize();
        await RowSyncEngine(store: RowSyncStore(a), client: client, cache: temp)
            .synchronize();
        expect((await a.query('tb_notes')).map((r) => r['content']).toSet(),
            {'desktop', 'phone'});
        expect(
            files.containsKey('/library/modu/database8.db'), value == 'strong');
        expect(files.keys.any((p) => p.contains('/record-log-v1/')),
            value != 'strong');
      } finally {
        await a.close();
        await b.close();
        await temp.delete(recursive: true);
      }
    });
  }
}
