import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String item(String href,
        {bool folder = false, String status = '200 OK', int size = 12}) =>
    '<d:response><d:href>$href</d:href><d:propstat><d:prop>'
    '<d:resourcetype>${folder ? '<d:collection/>' : ''}</d:resourcetype>'
    '<d:getcontentlength>$size</d:getcontentlength></d:prop>'
    '<d:status>HTTP/1.1 $status</d:status></d:propstat></d:response>';
String listing(String items) =>
    '<d:multistatus xmlns:d="DAV:">$items</d:multistatus>';

class _TreeLibrary extends WebdavLibrary {
  _TreeLibrary() : super(const LibraryConnection(url: 'https://host/dav/'));
  final tree = <String, List<LibraryEntry>>{};
  final requested = <String>[];
  void Function(CancelToken?)? onList;
  @override
  Future<List<LibraryEntry>> list(Uri directory,
      {CancelToken? cancelToken}) async {
    requested.add(directory.path);
    onList?.call(cancelToken);
    return tree[directory.path] ?? [];
  }
}

void main() {
  test('bad UTF-8 href does not discard otherwise valid directory entries', () {
    final client =
        WebdavLibrary(const LibraryConnection(url: 'https://host/dav/'));
    addTearDown(client.close);
    final entries = client.parseListing(
        listing(item('/dav/bad%FF.epub') + item('/dav/good.txt')), client.root);
    expect(entries.map((e) => e.name), ['good.txt']);
    expect(libraryError(const FormatException(), true, listing: true),
        isNot(contains('512')));
    expect(libraryError(const LibraryListingException('tooLarge'), false),
        contains('32 MiB'));
  });

  test(
      'large listing over 4 MiB parses in background; stream limit remains bounded',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final body =
        listing(List.generate(20000, (i) => item('/dav/book$i.epub')).join());
    expect(utf8.encode(body).length, greaterThan(4 * 1024 * 1024));
    server.listen((request) async {
      request.response.statusCode = 207;
      if (request.uri.path == '/dav/large/') {
        request.response.write(' ' * (WebdavLibrary.maxListingBytes + 1));
      } else {
        request.response.write(body);
      }
      try {
        await request.response.close();
      } catch (_) {}
    });
    final client = WebdavLibrary(LibraryConnection(
        url: 'http://127.0.0.1:${server.port}/dav/', allowHttp: true));
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    expect((await client.list(client.root)).length, 20000);
    await expectLater(
        client.list(client.root.resolve('large/')),
        throwsA(isA<LibraryListingException>()
            .having((e) => e.reason, 'reason', 'tooLarge')));
  });

  test(
      'folder discovery includes nested supported formats, deduplicates and ignores hidden entries',
      () async {
    final client = _TreeLibrary();
    addTearDown(client.close);
    LibraryEntry entry(String path, {bool folder = false}) => LibraryEntry(
        client.root.resolve(path),
        path.split('/').where((s) => s.isNotEmpty).last,
        folder,
        null);
    client.tree['/dav/'] = [
      entry('A.epub'),
      entry('A.epub'),
      entry('sub/', folder: true),
      entry('.hidden/', folder: true),
      entry('cover.jpg'),
      entry('.book.txt')
    ];
    client.tree['/dav/sub/'] = [
      for (final ext in ['txt', 'md', 'umd', 'mobi', 'azw3', 'fb2', 'pdf'])
        entry('sub/book.$ext')
    ];
    final books =
        await client.discoverBooks(client.root, cancelToken: CancelToken());
    expect(books.length, 8);
    expect(client.requested, ['/dav/', '/dav/sub/']);
    expect(books.every((e) => e.isBook && !e.isDirectory), isTrue);
  });

  test(
      'folder discovery supports cancellation and fails rather than hiding inaccessible subfolders',
      () async {
    final client = _TreeLibrary();
    addTearDown(client.close);
    client.tree['/dav/'] = [
      LibraryEntry(client.root.resolve('sub/'), 'sub', true, null)
    ];
    client.onList = (token) => token!.cancel();
    await expectLater(
        client.discoverBooks(client.root, cancelToken: CancelToken()),
        throwsA(isA<DioException>()));
    expect(client.requested, ['/dav/']);
    client.onList = (_) {
      if (client.requested.last == '/dav/sub/')
        throw const LibraryListingException('invalid');
    };
    await expectLater(
        client.discoverBooks(client.root, cancelToken: CancelToken()),
        throwsA(isA<LibraryListingException>()));
  });

  test('recursive discovery has a depth bound', () async {
    final client = _TreeLibrary();
    addTearDown(client.close);
    for (var depth = 0; depth < 34; depth++) {
      final parent = '/dav/${'sub/' * depth}';
      client.tree[parent] = [
        LibraryEntry(Uri.parse('https://host${parent}sub/'), 'sub', true, null)
      ];
    }
    await expectLater(
        client.discoverBooks(client.root, cancelToken: CancelToken()),
        throwsA(isA<LibraryListingException>()
            .having((e) => e.reason, 'reason', 'scanLimit')));
    expect(client.requested.length, 33);
  });

  test('HTTPS default rejects credentials in URLs, queries and insecure HTTP',
      () {
    for (final url in [
      'http://host/dav/',
      'https://user:secret@host/dav/',
      'https://host/dav/?token=secret',
      'https://host/dav/#x',
      'file:///tmp/'
    ]) {
      expect(() => LibraryConnection(url: url).root, throwsFormatException);
    }
    expect(const LibraryConnection(url: 'https://host/dav').root.toString(),
        'https://host/dav/');
    expect(
        const LibraryConnection(url: 'http://localhost/dav/', allowHttp: true)
            .root
            .scheme,
        'http');
  });

  test(
      'DAV parsing handles Unicode, percent signs, folders and unsupported files',
      () {
    final client =
        WebdavLibrary(const LibraryConnection(url: 'https://host/dav/'));
    addTearDown(client.close);
    final entries = client.parseListing(
        listing(item('/dav/', folder: true) +
            item('/dav/%E4%B8%AD%E6%96%87%20%231.epub') +
            item('/dav/100%25.pdf') +
            item('/dav/folder', folder: true) +
            item('/dav/image.png') +
            item('/dav/denied.epub', status: '403 Forbidden')),
        client.root);
    expect(entries.map((e) => e.name),
        ['folder', '100%.pdf', 'image.png', '中文 #1.epub']);
    expect(entries.first.uri.path, '/dav/folder/');
    expect(entries.where((e) => e.isBook).length, 2);
  });

  test(
      'untrusted hrefs cannot escape root, cross origins or inject local paths',
      () {
    final client =
        WebdavLibrary(const LibraryConnection(url: 'https://host/dav/'));
    addTearDown(client.close);
    final bad = [
      'https://evil.test/dav/book.epub',
      '/outside/book.epub',
      '../book.epub',
      '/dav/a%2Fb.epub',
      '/dav/a%5Cb.epub',
      '/dav/sub/book.epub',
      'file:///dav/book.epub',
      '/dav/book.epub?secret=x'
    ];
    expect(client.parseListing(listing(bad.map(item).join()), client.root),
        isEmpty);
    expect(() => client.parseListing('<!DOCTYPE x><x/>', client.root),
        throwsFormatException);
    expect(() => client.parseListing('<html>login</html>', client.root),
        throwsFormatException);
  });

  test(
      'password persists locally across preference reload and clear removes it',
      () async {
    SharedPreferences.setMockInitialValues({});
    await LibraryConnectionStore.clear();
    await LibraryConnectionStore.save(const LibraryConnection(
        url: 'https://host/dav/',
        username: 'reader',
        password: ' local-test-密码 &:? '));
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(LibraryConnectionStore.key)!;
    expect(jsonDecode(saved)['password'], ' local-test-密码 &:? ');
    // Simulate a new process loading only persisted preferences, not a session cache.
    SharedPreferences.setMockInitialValues({LibraryConnectionStore.key: saved});
    expect(
        (await LibraryConnectionStore.load())!.password, ' local-test-密码 &:? ');
    await LibraryConnectionStore.clear();
    expect(await LibraryConnectionStore.load(), isNull);
    expect(
        (await SharedPreferences.getInstance())
            .getString(LibraryConnectionStore.key),
        '',
        reason: 'An empty deletion marker contains no credentials');
  });

  test('legacy password-free preferences load without inventing a password',
      () async {
    SharedPreferences.setMockInitialValues({
      LibraryConnectionStore.key: jsonEncode({
        'url': 'https://host/dav/',
        'username': 'reader',
        'allowHttp': false
      })
    });
    final value = (await LibraryConnectionStore.load())!;
    expect(value.url, 'https://host/dav/');
    expect(value.username, 'reader');
    expect(value.password, '');
  });

  test('explicit empty password replaces an earlier saved password', () async {
    SharedPreferences.setMockInitialValues({});
    await LibraryConnectionStore.save(const LibraryConnection(
        url: 'https://host/dav/', password: 'old-test-secret'));
    await LibraryConnectionStore.save(
        const LibraryConnection(url: 'https://host/dav/'));
    expect((await LibraryConnectionStore.load())!.password, '');
    expect(
        (await SharedPreferences.getInstance())
            .getString(LibraryConnectionStore.key),
        isNot(contains('old-test-secret')));
  });

  test('live server: Depth 1 browsing and authenticated streamed download only',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final methods = <String>[];
    final failures = <String>[];
    final payload = utf8.encode('synthetic public book content');
    server.listen((request) async {
      methods.add(request.method);
      if (request.headers.value('authorization') !=
          'Basic ${base64Encode(utf8.encode('reader:password'))}') {
        failures.add('auth');
        request.response.statusCode = 401;
      } else if (request.method == 'PROPFIND') {
        if (request.headers.value('depth') != '1') failures.add('depth');
        final requestedProperties = await utf8.decoder.bind(request).join();
        if (!requestedProperties.contains('<d:creationdate/>') ||
            !requestedProperties.contains('<d:getlastmodified/>')) {
          failures.add('missing timestamp properties');
        }
        request.response.statusCode = 207;
        request.response.write(listing(item('/dav/', folder: true) +
            item('/dav/book.txt', size: payload.length)));
      } else if (request.method == 'GET') {
        request.response.contentLength = payload.length;
        request.response.add(payload);
      } else {
        failures.add('write');
        request.response.statusCode = 405;
      }
      await request.response.close();
    });
    final client = WebdavLibrary(LibraryConnection(
        url: 'http://127.0.0.1:${server.port}/dav/',
        username: 'reader',
        password: 'password',
        allowHttp: true));
    final temp = await Directory.systemTemp.createTemp('modu-library-test-');
    try {
      final entries = await client.list(client.root);
      final file = File('${temp.path}/book.txt');
      await client.download(
          entries.single, file, CancelToken(), (received, total) {});
      expect(await file.readAsBytes(), payload);
      expect(await File('${file.path}.part').exists(), false);
      expect(methods, ['PROPFIND', 'GET']);
      expect(failures, isEmpty);
    } finally {
      client.close();
      await server.close(force: true);
      await temp.delete(recursive: true);
    }
  });

  test('redirects are not followed and failed downloads leave no partial files',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var redirected = 0;
    server.listen((request) async {
      if (request.uri.path == '/dav/redirect.txt') {
        request.response.statusCode = 302;
        request.response.headers.set('location', '/outside.txt');
      } else {
        redirected++;
        request.response.write('no');
      }
      await request.response.close();
    });
    final client = WebdavLibrary(LibraryConnection(
        url: 'http://127.0.0.1:${server.port}/dav/', allowHttp: true));
    final temp = await Directory.systemTemp.createTemp('modu-library-test-');
    try {
      final file = File('${temp.path}/book.txt');
      await expectLater(
          client.download(
              LibraryEntry(client.root.resolve('redirect.txt'), 'redirect.txt',
                  false, null),
              file,
              CancelToken(),
              (received, total) {}),
          throwsA(isA<DioException>()));
      expect(await file.exists(), false);
      expect(await File('${file.path}.part').exists(), false);
      expect(redirected, 0);
    } finally {
      client.close();
      await server.close(force: true);
      await temp.delete(recursive: true);
    }
  });

  test('cancelled download cleans staging file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      try {
        for (var i = 0; i < 16; i++) {
          request.response.add(List.filled(4096, 42));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await request.response.close();
      } catch (_) {}
    });
    final client = WebdavLibrary(LibraryConnection(
        url: 'http://127.0.0.1:${server.port}/dav/', allowHttp: true));
    final temp = await Directory.systemTemp.createTemp('modu-library-test-');
    try {
      final cancel = CancelToken();
      final file = File('${temp.path}/book.txt');
      await expectLater(
          client.download(
              LibraryEntry(
                  client.root.resolve('book.txt'), 'book.txt', false, null),
              file,
              cancel,
              (received, total) => cancel.cancel()),
          throwsA(anything));
      expect(await file.exists(), false);
      expect(await File('${file.path}.part').exists(), false);
    } finally {
      client.close();
      await server.close(force: true);
      await temp.delete(recursive: true);
    }
  });
}
