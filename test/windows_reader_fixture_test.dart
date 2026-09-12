import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:anx_reader/service/convert_to_epub/txt/convert_from_txt.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import '../integration_test/fixtures/windows_reader_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('tiny TXT fixture has exactly 42 ASCII characters', () {
    expect(tinyReaderText.length, 42);
    expect(ascii.encode(tinyReaderText).length, 42);
  });
  test('tiny PDF fixture has a valid xref for all five objects', () {
    final pdf = ascii.decode(tinyReaderPdf());
    expect(pdf, startsWith('%PDF-1.4'));
    expect(pdf, contains('MODU_PDF_SENTINEL'));
    final xref = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(pdf)![1]!);
    expect(pdf.substring(xref), startsWith('xref\n0 6\n'));
    final entries = RegExp(r'(\d{10}) 00000 n').allMatches(pdf).toList();
    expect(entries.length, 5);
    for (var i = 0; i < entries.length; i++) {
      final offset = int.parse(entries[i][1]!);
      expect(pdf.substring(offset), startsWith('${i + 1} 0 obj\n'));
    }
  });
  test('tiny TXT survives the real import conversion without losing text',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final root = await Directory.systemTemp.createTemp('modu-tiny-import-');
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FixturePaths(root.path);
    try {
      final input =
          await File('${root.path}/tiny.txt').writeAsString(tinyReaderText);
      final epub = await convertFromTxt(input);
      final zip = ZipDecoder().decodeBytes(await epub.readAsBytes());
      final text = zip.files
          .where((f) => f.name.endsWith('.xhtml'))
          .map((f) => utf8.decode(f.content as List<int>))
          .join('\n');
      expect(text, contains(tinyReaderText));
    } finally {
      PathProviderPlatform.instance = previous;
      await root.delete(recursive: true);
    }
  });
  testWidgets('native reader fixture can build URL with default font settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: Text('Fixture'))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Server().start();
      try {
        expect(generateUrl('http://127.0.0.1/fixture', ''),
            contains('/foliate-js/index.html'));
      } finally {
        await Server().stop();
      }
    });
  });
}

class _FixturePaths extends PathProviderPlatform {
  _FixturePaths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}
