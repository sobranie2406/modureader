import 'dart:io';

import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/service/book_source_format.dart';
import 'package:anx_reader/service/convert_to_epub/create_epub.dart';
import 'package:anx_reader/service/convert_to_epub/markdown/convert_from_markdown.dart';
import 'package:anx_reader/service/convert_to_epub/section.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late BookSourceFormat formats;
  late String previousDocuments;
  Book book() => Book.mock()..filePath = 'file/converted.epub';

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-source-format-');
    previousDocuments = documentPath;
    documentPath = root.path;
    await Directory('${root.path}/file').create();
    SharedPreferences.setMockInitialValues({});
    formats = BookSourceFormat(await SharedPreferences.getInstance());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => root.path);
  });
  tearDown(() async {
    documentPath = previousDocuments;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await root.delete(recursive: true);
  });

  for (final source in ['TXT', 'MD', 'markdown', 'UMD']) {
    test(
        'new $source imports retain their original badge without changing bytes',
        () async {
      final value = book();
      final file = await File(value.fileFullPath).writeAsString('stored EPUB');
      await formats.remember(value, source);
      final expected = source == 'markdown' ? 'MD' : source;
      expect(formats.format(value), expected);
      expect(await formats.resolve(value), expected);
      expect(
          BookSourceFormat(await SharedPreferences.getInstance()).format(value),
          expected);
      expect(await file.readAsString(), 'stored EPUB');
      expect(collectAiSettingsForSync(await SharedPreferences.getInstance()),
          isEmpty,
          reason: 'Local badge caches must not enter settings sync');
      // A remembered format remains available after releasing the local file.
      await file.delete();
      expect(await formats.resolve(value), expected);
    });
  }

  for (final source in ['TXT', 'MD', 'UMD']) {
    test('recognizes historical $source conversion after download', () async {
      final value = book();
      expect(await formats.resolve(value), 'EPUB');
      final bytes = source == 'TXT'
          ? await (await createEpub('Synthetic', 'Author',
                  [Section('Chapter', 'Example text', 1)]))
              .readAsBytes()
          : source == 'UMD'
              ? umdTextToEpub(
                  title: 'Synthetic',
                  author: 'Author',
                  sections: [Section('Chapter', 'Example text', 1)],
                  sourceDigest: 'a' * 64)
              : markdownToEpub('# Synthetic\n\nExample text',
                  fallbackTitle: 'Synthetic');
      final file = await File(value.fileFullPath).writeAsBytes(bytes);
      expect(await formats.resolve(value), source);
      expect(formats.format(value), source);
      expect(await file.readAsBytes(), bytes);
      // Replacing a file must invalidate the old display cache.
      await file.writeAsString('not a converted EPUB');
      expect(await formats.resolve(value), 'EPUB');
    });
  }

  test(
      'unknown files fall back safely; no inference from titles or other formats',
      () async {
    final value = book()..title = 'Example.txt';
    await File(value.fileFullPath).writeAsString('broken EPUB');
    expect(await formats.resolve(value), 'EPUB');
    for (final extension in ['pdf', 'mobi', 'azw3', 'fb2', 'epub']) {
      value.filePath = 'file/book.$extension';
      expect(await formats.resolve(value), extension.toUpperCase());
    }
  });
}
