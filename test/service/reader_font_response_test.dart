import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/reader_file_access.dart';
import 'package:anx_reader/service/book_player/reader_font_response.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('modu-font-test-');
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final filename in [
    'SourceHanSerifSC-Regular.otf',
    '俗日困我 盛夏邮青.ttf',
    '中文.ttf',
    'with space.ttf',
    "书体 (测试)'s #100% + ?.TTF",
    'literal%20name.ttf',
    'literal%2Fname.ttf',
    'quote"name.otf',
  ]) {
    test('URL and preference round trip: $filename', () async {
      final bytes = [0, 1, 0, 0, 11, 22, 33];
      await File('${directory.path}/$filename').writeAsBytes(bytes);
      final url = readerFontUrl(filename, 1234);
      final uri = Uri.parse(url);
      expect(uri.pathSegments, ['fonts', filename]);
      expect(uri.query, isEmpty);
      expect(uri.fragment, isEmpty);
      expect(url, isNot(contains("'")));

      final selected =
          FontModel(label: '字体 "预览"', name: 'customFont1', path: url);
      final saved = selected.toJson();
      expect(jsonDecode(saved)['path'], filename);
      final restored = FontModel.fromJson(saved, serverPort: 4567);
      expect(restored.litePath, filename);
      expect(Uri.parse(restored.path).port, 4567);
      expect(restored, selected);
      expect(restored.hashCode, selected.hashCode);
      expect(jsonDecode(restored.toJson())['path'], filename);

      final response = await readerFontResponse(Uri.parse(restored.path),
          directory: directory);
      expect(response.statusCode, 200);
      expect(response.headers['content-type'],
          filename.toLowerCase().endsWith('.otf') ? 'font/otf' : 'font/ttf');
      expect(await response.read().expand((b) => b).toList(), bytes);
    });
  }

  test('legacy raw filename preference works without reimporting or renaming',
      () async {
    const filename = '俗日困我 盛夏邮青.ttf';
    await File('${directory.path}/$filename').writeAsBytes([1, 2, 3]);
    final restored = FontModel.fromJson(
      '{"label":"俗日困我 盛夏邮青","name":"customFont0","path":"$filename"}',
      serverPort: 1234,
    );
    final uri = Uri.parse(restored.path);
    // Reproduce the old server's lookup failure for this exact filename.
    expect(ReaderFileAccess.within(directory, path.basename(uri.path)), isNull);
    expect(
        (await readerFontResponse(uri, directory: directory)).statusCode, 200);
  });

  test('raw filename preserves literal percent sequences when saving', () {
    final model = FontModel(
        label: 'font', name: 'customFont0', path: 'literal%20name.ttf');
    expect(jsonDecode(model.toJson())['path'], 'literal%20name.ttf');
    expect(FontModel.fromJson(model.toJson(), serverPort: 1234).litePath,
        model.litePath);
  });

  test('system and book selections need no running server', () {
    for (final value in ['system', 'book', '']) {
      final name = value == 'book' ? 'book' : 'system';
      final model = FontModel(label: name, name: name, path: value);
      expect(FontModel.fromJson(model.toJson()), model);
    }
  });

  test('same-name replacement is served fresh, and deletion returns 404',
      () async {
    final file = await File('${directory.path}/replace.ttf').writeAsBytes([1]);
    final uri = Uri.parse(readerFontUrl('replace.ttf', 1234));
    final first = await readerFontResponse(uri, directory: directory);
    expect(first.headers['cache-control'], 'no-store');
    expect(await first.read().expand((b) => b).toList(), [1]);
    await file.writeAsBytes([2, 3]);
    final second = await readerFontResponse(uri, directory: directory);
    expect(await second.read().expand((b) => b).toList(), [2, 3]);
    await file.delete();
    expect(
        (await readerFontResponse(uri, directory: directory)).statusCode, 404);
  });

  test('rejects traversal, escaping symlinks and non-font files', () async {
    final fonts = await Directory('${directory.path}/fonts').create();
    final outside =
        await File('${directory.path}/private.ttf').writeAsBytes([99]);
    await Link('${fonts.path}/link.ttf').create(outside.path);
    await File('${fonts.path}/key.json').writeAsString('private');
    for (final route in [
      '/fonts/link.ttf',
      '/fonts/key.json',
      '/fonts/missing.ttf',
      '/fonts/',
      '/fonts/../private.ttf',
      '/fonts/%2E%2E%2Fprivate.ttf',
      '/fonts/%2E%2E%5Cprivate.ttf',
      '/fonts/nested/private.ttf',
      '/fonts/%00.ttf',
      '/fonts/%252E%252E%252Fprivate.ttf',
    ]) {
      expect(
          (await readerFontResponse(Uri.parse('http://127.0.0.1$route'),
                  directory: fonts))
              .statusCode,
          404,
          reason: route);
    }
  });

  test('actual reader HTTP server serves an encoded filename', () async {
    final previousPath = documentPath;
    documentPath = directory.path;
    SharedPreferences.setMockInitialValues({'lastServerPort': 0});
    await Prefs().initPrefs();
    await getFontDir().create();
    const filename = "俗日困我 盛夏邮青 #100%'s.ttf";
    await File('${getFontDir().path}/$filename').writeAsBytes([0, 1, 2, 3]);
    // Flutter's widget-test HTTP mock always returns 400. This test explicitly
    // uses a real loopback connection to the production server instead.
    final client = HttpOverrides.runWithHttpOverrides(
        HttpClient.new, _LoopbackHttpOverrides());
    try {
      await Server().start();
      final model = FontModel.fromJson(jsonEncode(
          {'label': filename, 'name': 'customFont0', 'path': filename}));
      final response =
          await (await client.getUrl(Uri.parse(model.path))).close();
      expect(response.statusCode, 200);
      expect(await response.expand((b) => b).toList(), [0, 1, 2, 3]);
    } finally {
      client.close(force: true);
      await Server().stop();
      documentPath = previousPath;
    }
  });

  // The user's font remains outside source control and is never redistributed.
  final actualFont = Platform.environment['MODU_TEST_FONT'];
  test('provided font loads from the repaired route with identical bytes',
      () async {
    final bytes = await File(actualFont!).readAsBytes();
    const filename = '俗日困我 盛夏邮青.ttf';
    await File('${directory.path}/$filename').writeAsBytes(bytes);
    final response = await readerFontResponse(
        Uri.parse(readerFontUrl(filename, 1234)),
        directory: directory);
    expect(response.statusCode, 200);
    final received =
        Uint8List.fromList(await response.read().expand((b) => b).toList());
    expect(received, orderedEquals(bytes));
    await (FontLoader('moduProvidedFont')
          ..addFont(Future.value(ByteData.sublistView(received))))
        .load();
  },
      skip: actualFont == null
          ? 'Set MODU_TEST_FONT for the private local fixture'
          : false);
}
