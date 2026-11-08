import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/remote_library/baidu_auth.dart';
import 'package:anx_reader/service/remote_library/baidu_library.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class TestAuth extends BaiduAuth {
  @override
  Future<String> accessToken() async => 'test-access';
}

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Map<String, dynamic> value) =>
    ResponseBody.fromString(jsonEncode(value), 200, headers: {
      'content-type': ['application/json']
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestAuth auth;
  setUp(() => auth = TestAuth());
  tearDown(() => auth.close());

  test('keeps folders and supported books after a page of unsupported files',
      () async {
    Map<String, Object> entry(int id, String name, {bool folder = false}) => {
          'fs_id': id,
          'path': '/$name',
          'server_filename': name,
          'size': 3,
          'isdir': folder ? 1 : 0,
        };
    final adapter = Adapter((options) {
      expect(options.method, 'GET');
      expect(options.uri.path, '/rest/2.0/xpan/file');
      expect(options.uri.queryParameters['method'], 'list');
      return jsonBody({
        'errno': 0,
        'list': options.uri.queryParameters['start'] == '0'
            ? List.generate(1000, (i) => entry(i + 1, 'video$i.mp4'))
            : [
                entry(1001, '资料', folder: true),
                entry(1002, '书.EPUB'),
                entry(1003, '阅读.pdf'),
                entry(1004, '笔记.md'),
                entry(1005, '压缩包.zip'),
                entry(1006, '照片.jpg'),
              ],
      });
    });
    final library =
        BaiduLibrary(auth, client: Dio()..httpClientAdapter = adapter);
    addTearDown(library.close);
    expect((await library.list(library.root)).map((e) => e.name),
        ['资料', '书.EPUB', '阅读.pdf', '笔记.md']);
    expect(adapter.requests.length, 2);
  });

  test('Chinese spaces and literal percent paths reach Baidu unchanged',
      () async {
    final adapter = Adapter((options) {
      expect(options.uri.queryParameters['dir'], '/中文 空格%20');
      expect(options.uri.queryParameters['access_token'], 'test-access');
      return jsonBody({
        'errno': 0,
        'list': [
          {
            'fs_id': 123,
            'path': '/中文 空格%20/书 %20 #1.epub',
            'server_filename': '书 %20 #1.epub',
            'size': 3,
            'isdir': 0,
          }
        ]
      });
    });
    final library =
        BaiduLibrary(auth, client: Dio()..httpClientAdapter = adapter);
    addTearDown(library.close);
    final entries = await library
        .list(library.root.replace(pathSegments: ['中文 空格%20', '']));
    expect(entries.single.name, '书 %20 #1.epub');
    expect(entries.single.uri.pathSegments, ['中文 空格%20', '书 %20 #1.epub']);
    expect(entries.single.isBook, isTrue);
  });

  test('rejects paths outside the selected folder', () async {
    final adapter = Adapter((_) => jsonBody({
          'errno': 0,
          'list': [
            {
              'fs_id': 1,
              'path': '/other/book.epub',
              'server_filename': 'book.epub',
              'size': 3,
              'isdir': 0,
            }
          ]
        }));
    final library =
        BaiduLibrary(auth, client: Dio()..httpClientAdapter = adapter);
    addTearDown(library.close);
    await expectLater(library.list(library.root), throwsFormatException);
  });

  test('download host validation rejects lookalikes, credentials and HTTP', () {
    for (final uri in [
      'http://d.pcs.baidu.com/book',
      'https://baidu.com.evil.test/x',
      'https://baidu.com@evil.test/x',
      'https://127.0.0.1/x',
      'https://baidu.com:8443/x'
    ]) {
      expect(BaiduLibrary.trustedDownload(Uri.parse(uri)), isFalse);
    }
    expect(
        BaiduLibrary.trustedDownload(Uri.parse('https://d.pcs.baidu.com/file')),
        isTrue);
  });

  for (final scenario in ['success', 'truncated', 'evil redirect']) {
    test('direct download $scenario, staging is cleaned on failure', () async {
      final dir = await Directory.systemTemp.createTemp('modu-baidu-test-');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}/book.epub');
      final adapter = Adapter((options) {
        if (options.uri.path == '/rest/2.0/xpan/multimedia') {
          return jsonBody({
            'errno': 0,
            'list': [
              {'fs_id': 1, 'dlink': 'https://d.pcs.baidu.com/book'}
            ]
          });
        }
        expect(options.uri.host, 'd.pcs.baidu.com');
        expect(options.headers['Authorization'], isNull);
        expect(options.headers['User-Agent'], 'pan.baidu.com');
        if (scenario == 'evil redirect') {
          return ResponseBody.fromString('', 302, headers: {
            'location': ['https://evil.test/book']
          });
        }
        return ResponseBody.fromBytes([1, 2, 3], 200,
            headers: {
              'content-length': [scenario == 'truncated' ? '4' : '3']
            });
      });
      final library =
          BaiduLibrary(auth, client: Dio()..httpClientAdapter = adapter);
      addTearDown(library.close);
      final entry = BaiduEntry(
          library.root.resolve('book.epub'), 'book.epub', false, 3,
          fileId: 1);
      final result = library.download(entry, target, CancelToken(), (_, __) {});
      if (scenario == 'success') {
        await result;
        expect(await target.readAsBytes(), [1, 2, 3]);
      } else {
        await expectLater(result, throwsFormatException);
        expect(await target.exists(), isFalse);
      }
      expect(await File('${target.path}.part').exists(), isFalse);
      expect(adapter.requests.every((r) => !r.uri.host.contains('2406.fun')),
          isTrue);
      expect(adapter.requests.length, 2);
    });
  }
}
