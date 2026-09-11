import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/home_page.dart' show webViewEnvironment;
import 'package:anx_reader/service/ai/tools/repository/book_content_search_repository.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/webView/anx_headless_webview.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows repeatedly extracts EPUB chapters using native WebView2',
      (tester) async {
    if (!Platform.isWindows ||
        !const bool.fromEnvironment('MODU_WINDOWS_READER_TEST')) {
      fail(
          'Run only in isolated Windows CI with MODU_WINDOWS_READER_TEST=true');
    }
    // No real preferences, database, books, keys or synchronization endpoints.
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final root = await Directory.systemTemp.createTemp('modu-reader-fixture-');
    documentPath = root.path;
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Synthetic reader integration test'))));
    await tester.pumpAndSettle();
    try {
      final archive = Archive();
      void add(String name, String text) {
        final bytes = utf8.encode(text);
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      }

      add('mimetype', 'application/epub+zip');
      add('META-INF/container.xml', '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''');
      add('content.opf', '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">modu-test</dc:identifier><dc:title>Fixture</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">2026-09-11T00:00:00Z</meta></metadata>
<manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="one" href="one.xhtml" media-type="application/xhtml+xml"/><item id="two" href="two.xhtml" media-type="application/xhtml+xml"/></manifest>
<spine><itemref idref="one"/><itemref idref="two"/></spine></package>''');
      add('nav.xhtml',
          '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol><li><a href="one.xhtml">One</a></li><li><a href="two.xhtml">Two</a></li></ol></nav></body></html>''');
      for (final chapter in ['one', 'two']) {
        add('$chapter.xhtml',
            '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$chapter</title></head><body><h1>$chapter</h1><p>MODU_SENTINEL_$chapter</p></body></html>');
      }
      await File('${root.path}/fixture.epub')
          .writeAsBytes(ZipEncoder().encode(archive)!);
      await Server().start();
      expect(await WebViewEnvironment.getAvailableVersion(), isNotNull);
      webViewEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
              userDataFolder: '${root.path}/webview'));
      final book = Book(
          id: 1,
          title: 'Fixture',
          coverPath: '',
          filePath: 'fixture.epub',
          lastReadPosition: '',
          readingPercentage: 0,
          author: '',
          isDeleted: false,
          rating: 0,
          createTime: DateTime(2026),
          updateTime: DateTime(2026));
      for (var cycle = 0; cycle < 3; cycle++) {
        final chapters = await BookContentSearchRepository()
            .extractChaptersForIndex(book)
            .timeout(const Duration(minutes: 2));
        expect(chapters.values.join('\n'), contains('MODU_SENTINEL_one'));
        expect(chapters.values.join('\n'), contains('MODU_SENTINEL_two'));
        debugPrint('WINDOWS EPUB EXTRACTION PASS cycle=${cycle + 1}');
      }
    } finally {
      await AnxHeadlessWebView.disposeAll()
          .timeout(const Duration(seconds: 20));
      await Server().stop();
      await webViewEnvironment?.dispose();
      webViewEnvironment = null;
      // WebView2 child processes may retain cache files briefly after close.
      // Leave only this synthetic OS temp directory for the CI runner cleanup.
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
