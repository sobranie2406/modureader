import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:anx_reader/service/sync/s3_client.dart';
import 'package:anx_reader/service/sync/s3_config.dart';
import 'package:anx_reader/service/sync/s3_signer.dart';
import 'package:anx_reader/service/sync/row_sync_engine.dart';
import 'package:anx_reader/service/sync/row_sync_store.dart';
import 'package:anx_reader/service/sync/immutable_sync_log.dart';
import 'row_sync_test.dart' show fixture, noteRow;

Map<String, dynamic> configuration([Map<String, dynamic> extra = const {}]) => {
      'endpoint': 'https://s3.amazonaws.com',
      'bucket': 'examplebucket',
      'region': 'us-east-1',
      'remoteRoot': 'Books/中文',
      'accessKeyId': 'AKIDEXAMPLE',
      'secretAccessKey': 'test-secret',
      ...extra,
    };

/// Isolated wire-protocol fixture. No real cloud credentials/data involved.
class S3Fixture {
  late HttpServer server;
  final objects = <String, List<int>>{};
  final calls = <String>[];
  String? listingOverride;
  int? failure;
  int pageSize = 2;
  bool corruptDownload = false;
  String xml(String text) => const HtmlEscape().convert(text);
  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.pathSegments.skip(1).join('/');
      calls.add('${request.method} $path');
      final response = request.response;
      if (failure != null) {
        response.statusCode = failure!;
        response.headers.set('retry-after', '120');
        if (failure == 302)
          response.headers
              .set('location', 'https://never-follow.example/private');
        response.write('sensitive-response-body');
        await response.close();
        return;
      }
      if (request.headers.value('authorization') == null) {
        response.statusCode = 403;
        await response.close();
        return;
      }
      if (request.method == 'GET' &&
          request.uri.queryParameters.containsKey('prefix')) {
        if (listingOverride != null) {
          response.write(listingOverride);
          await response.close();
          return;
        }
        final prefix = request.uri.queryParameters['prefix']!;
        final entries = <String, bool>{};
        for (final key in objects.keys.where((key) => key.startsWith(prefix))) {
          final rest = key.substring(prefix.length);
          if (rest.isEmpty) {
            entries[key] = false;
            continue;
          }
          final slash = rest.indexOf('/');
          entries[slash < 0 ? key : '$prefix${rest.substring(0, slash + 1)}'] =
              slash >= 0;
        }
        final keys = entries.keys.toList()..sort();
        final start = int.parse(
            request.uri.queryParameters['continuation-token'] ??
                request.uri.queryParameters['marker'] ??
                '0');
        final limit = int.parse(request.uri.queryParameters['max-keys']!)
            .clamp(1, pageSize);
        final page = keys.skip(start).take(limit).toList();
        final more = start + page.length < keys.length;
        response.write(
            '<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">'
            '<Prefix>${xml(s3Encode(prefix))}</Prefix><EncodingType>url</EncodingType>'
            '<IsTruncated>$more</IsTruncated>');
        for (final key in page) {
          if (entries[key]!) {
            response.write(
                '<CommonPrefixes><Prefix>${xml(s3Encode(key))}</Prefix></CommonPrefixes>');
          } else {
            response.write(
                '<Contents><Key>${xml(s3Encode(key))}</Key><Size>${objects[key]!.length}</Size>'
                '<ETag>"${md5.convert(objects[key]!)}"</ETag></Contents>');
          }
        }
        if (more)
          response.write(
              '<NextContinuationToken>${start + page.length}</NextContinuationToken><NextMarker>${start + page.length}</NextMarker>');
        response.write('</ListBucketResult>');
      } else if (request.method == 'PUT') {
        final bytes =
            await request.fold<List<int>>([], (all, b) => all..addAll(b));
        expect(request.headers.contentLength, bytes.length);
        expect(request.headers.value('transfer-encoding'), isNull);
        if (request.headers.value('x-amz-content-sha256')
            case final String hash) {
          expect(hash, sha256.convert(bytes).toString());
        }
        if (request.headers.value('content-md5') case final String hash) {
          expect(hash, base64Encode(md5.convert(bytes).bytes));
        }
        if (request.headers.value('if-none-match') == '*' &&
            objects.containsKey(path)) {
          response.statusCode = 412;
        } else {
          objects[path] = bytes;
        }
      } else if (request.method == 'DELETE') {
        objects.remove(path);
        response.statusCode = 204;
      } else if (!objects.containsKey(path)) {
        response.statusCode = 404;
      } else {
        var bytes = objects[path]!;
        if (corruptDownload) bytes = [1, 2, 3];
        response.headers.set('etag', '"${md5.convert(bytes)}"');
        response.contentLength = bytes.length;
        if (request.method != 'HEAD') response.add(bytes);
      }
      await response.close();
    });
  }

  S3SyncClient client([Map<String, dynamic> extra = const {}]) =>
      S3SyncClient(configuration({
        'endpoint': 'http://127.0.0.1:${server.port}',
        'allowInsecure': true,
        ...extra,
      }));
}

void main() {
  test(
      'V4 agrees with official @smithy/signature-v4 for Unicode and query tokens',
      () {
    final config = S3Config(configuration({
      'endpoint': 'https://s3.amazonaws.com',
      'addressing': 'virtual',
      'sessionToken': 'test-token'
    }));
    // Independently generated by AWS @smithy/signature-v4, uriEscapePath=false.
    for (final entry in {
      'test.txt':
          '60bc77b8755eff3b4eba934e73c080981dab0e63a99ba6359df961df04e6cd4c',
      'modu/中文 +%?.txt':
          '92c3d61de9a91abaf8bcc4ff32d8eabc2a651bbd6be444da435633e7705b8df6',
    }.entries) {
      final uri = s3Uri(config, entry.key,
          {'prefix': '中文/+%', 'continuation-token': 'a+b/='});
      final headers = signS3Request(
          config: config,
          method: 'GET',
          uri: uri,
          key: entry.key,
          payloadHash: sha256.convert([]).toString(),
          now: DateTime.utc(2026, 10, 7, 1, 2, 3));
      expect(headers['authorization'], endsWith('Signature=${entry.value}'));
    }
  });
  test('V2 matches the published AWS S3 GET example', () {
    final config = S3Config(configuration({
      'signature': 'v2',
      'bucket': 'johnsmith',
      'accessKeyId': 'AKIAIOSFODNN7EXAMPLE',
      'secretAccessKey': 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
    }));
    final headers = signS3Request(
        config: config,
        method: 'GET',
        uri: Uri.parse('https://johnsmith.s3.amazonaws.com/photos/puppy.jpg'),
        key: 'photos/puppy.jpg',
        payloadHash: '',
        now: DateTime.utc(2007, 3, 27),
        headers: {'date': 'Tue, 27 Mar 2007 19:36:42 +0000'});
    expect(headers['authorization'],
        'AWS AKIAIOSFODNN7EXAMPLE:bWq2s1WEIj+Ydj0vQ697zp+IXMU=');
  });
  test('provider addressing and path boundaries preserve case', () {
    for (final preset
        in S3Preset.values.where((p) => p.addressing == 'virtual')) {
      final config = S3Config(configuration(
          {'endpoint': preset.endpoint, 'addressing': preset.addressing}));
      expect(s3Uri(config, config.key('modu/data/书 %.epub'), {}).host,
          startsWith('examplebucket.'));
    }
    final config = S3Config(configuration());
    expect(config.key('/modu/A%2F.epub'), 'Books/中文/A%2F.epub');
    expect(config.logicalPath('Books/中文/A%2F.epub'), 'modu/A%2F.epub');
    for (final bad in [
      'modu/../x',
      'other/x',
      'modu//x',
      'modu/./x',
      'modu/\\x'
    ]) {
      expect(() => config.key(bad), throwsFormatException);
    }
    expect(() => config.logicalPath('Books/中文-other/x'), throwsFormatException);
    expect(() => S3Config(configuration({'endpoint': 'http://example.com'})),
        throwsFormatException);
    expect(
        () => S3Config(
            configuration({'endpoint': 'https://user:secret@example.com'})),
        throwsFormatException);
  });

  group('HTTP and sync integration', () {
    late S3Fixture server;
    late Directory temp;
    setUp(() async {
      server = S3Fixture();
      await server.start();
      temp = await Directory.systemTemp.createTemp('modu-s3-test-');
    });
    tearDown(() async {
      await server.server.close(force: true);
      await temp.delete(recursive: true);
    });
    test('V1/V2 complete pagination, virtual directories and special names',
        () async {
      for (final name in [
        '一 +%.epub',
        'two.pdf',
        'three.txt',
        'four.md',
        'five.mobi'
      ]) {
        server.objects['Books/中文/data/file/$name'] = [1, 2, 3];
      }
      for (final version in ['v1', 'v2']) {
        final client = server.client({'listVersion': version});
        final files = await client.readSyncDirectory('modu/data/file');
        expect(files.length, 5);
        expect(files.map((f) => f.name), contains('一 +%.epub'));
        expect((await client.readProps('modu/data/file'))?.isDir, true);
        expect(await client.safeReadDir('modu/empty'), isEmpty);
      }
    });
    test('capability probe cleans only its own object, streamed round trip',
        () async {
      final client = server.client();
      server.objects['outside/untouched'] = [4];
      await client.testFullCapabilities();
      expect(server.objects.keys, ['outside/untouched']);
      for (final signature in ['v4', 'v2']) {
        final c = server.client({'signature': signature});
        final input = File('${temp.path}/input');
        await input.writeAsBytes(List.generate(100000, (i) => i % 256));
        await c.uploadFile(input.path, 'modu/data/file/中文 +%.epub');
        final output = '${temp.path}/output';
        await c.downloadFile('modu/data/file/中文 +%.epub', output);
        expect(await File(output).readAsBytes(), await input.readAsBytes());
        await expectLater(
            c.uploadFile(input.path, 'modu/data/file/中文 +%.epub',
                replace: false),
            throwsA(isA<DioException>()));
      }
      expect(await client.supportsAtomicSyncWrites(), false);
      expect(() => client.uploadFileConditionally('', 'modu/database8.db'),
          throwsUnsupportedError);
    });
    test('a directory marker on the first page cannot hide real children',
        () async {
      server.objects['Books/中文/data/file/'] = [];
      server.objects['Books/中文/data/file/book.pdf'] = [1, 2, 3];
      for (final version in ['v1', 'v2']) {
        final client = server.client({'listVersion': version});
        expect((await client.readProps('modu/data/file/'))?.isDir, true);
        expect(
            (await client.readDir('modu/data/file')).single.name, 'book.pdf');
      }
    });
    test('errors, redirects, malformed and truncated lists fail closed',
        () async {
      for (final status in [403, 404, 302, 503]) {
        server.failure = status;
        final client = server.client();
        await expectLater(client.readDir('modu'), throwsA(isA<DioException>()));
        try {
          await client.readDir('modu');
        } on DioException catch (e) {
          expect(e.toString(), isNot(contains('test-secret')));
          expect(e.toString(), isNot(contains('sensitive-response-body')));
          expect(e.requestOptions.headers, isEmpty);
        }
      }
      server.failure = null;
      for (final xml in [
        '<Error><Code>Denied</Code></Error>',
        '<ListBucketResult><Prefix>Books/中文/</Prefix><IsTruncated>true</IsTruncated></ListBucketResult>',
        '<ListBucketResult><Prefix>wrong/</Prefix><IsTruncated>false</IsTruncated></ListBucketResult>'
      ]) {
        server.listingOverride = xml;
        await expectLater(
            server.client().readDir('modu'), throwsFormatException);
      }
    });
    test(
        'failed download preserves existing local file and cooldown avoids retry requests',
        () async {
      final output = File('${temp.path}/output');
      await output.writeAsString('keep-me');
      server.failure = 503;
      final client = server.client();
      await expectLater(client.downloadFile('modu/data/file/a', output.path),
          throwsA(isA<DioException>()));
      await expectLater(client.ping(), throwsA(isA<DioException>()));
      expect(server.calls.length, 1);
      expect(await output.readAsString(), 'keep-me');
      expect((await temp.list().toList()).length, 1);
    });
    test(
        'two devices merge book notes through real S3 HTTP without shared DB overwrite',
        () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final a = await fixture();
      final b = await fixture(bookId: 77);
      try {
        final sa = RowSyncStore(a), sb = RowSyncStore(b);
        await a.insert('tb_notes', noteRow(1, 'desktop'));
        await b.insert('tb_notes', noteRow(77, 'phone'));
        Future<void> sync(RowSyncStore store) async {
          await RowSyncEngine(
                  store: store, client: server.client(), cache: temp)
              .synchronize();
        }

        await sync(sa);
        await sync(sb);
        await sync(sa);
        expect((await a.query('tb_notes')).map((r) => r['content']).toSet(),
            {'desktop', 'phone'});
        expect(
            server.calls.where(
                (s) => s.startsWith('PUT ') && s.endsWith('/database8.db')),
            isEmpty);
        final pendingA = ImmutableSyncLog(server.client(), temp, temp,
                durableDirectory: temp)
            .pending
            .path;
        final pendingB = ImmutableSyncLog(
                server.client({'bucket': 'other-bucket'}), temp, temp,
                durableDirectory: temp)
            .pending
            .path;
        final pendingC = ImmutableSyncLog(
                server.client({'remoteRoot': 'Other'}), temp, temp,
                durableDirectory: temp)
            .pending
            .path;
        expect({pendingA, pendingB, pendingC}.length, 3);
      } finally {
        await a.close();
        await b.close();
      }
    });
    test(
        'corrupt remote records do not erase local records or publish an empty library',
        () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final a = await fixture();
      final b = await fixture(bookId: 77);
      try {
        await a.insert('tb_notes', noteRow(1, 'cloud-note'));
        await RowSyncEngine(
                store: RowSyncStore(a), client: server.client(), cache: temp)
            .synchronize();
        await b.insert('tb_notes', noteRow(77, 'local-note'));
        final localBefore = await b.query('tb_notes');
        // A second device must not share the first device's verified cache.
        final phoneCache = await Directory('${temp.path}/phone').create();
        final previousObjects = Map<String, List<int>>.from(server.objects);
        server.calls.clear();
        server.corruptDownload = true;
        await expectLater(
            RowSyncEngine(
                    store: RowSyncStore(b),
                    client: server.client(),
                    cache: phoneCache)
                .synchronize(),
            throwsA(anything));
        expect(await b.query('tb_notes'), localBefore);
        expect(
            server.calls
                .where((s) => s.startsWith('PUT ') || s.startsWith('DELETE ')),
            isEmpty);
        expect(server.objects, previousObjects);
      } finally {
        await a.close();
        await b.close();
      }
    });
  });
}
