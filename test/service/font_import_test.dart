import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/service/font.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Minimal name-table fixture for import/selection tests. Actual font decoding
// is covered separately by reader_font_response_test's private font fixture.
Uint8List namedFont(String name) {
  final data = ByteData(46 + name.length * 2);
  data.setUint32(0, 0x00010000);
  data.setUint16(4, 1);
  data.setUint32(12, 0x6e616d65);
  data.setUint32(20, 28);
  data.setUint32(24, 18 + name.length * 2);
  data.setUint16(30, 1);
  data.setUint16(32, 18);
  data.setUint16(34, 3);
  data.setUint16(36, 1);
  data.setUint16(38, 0x804);
  data.setUint16(40, 1);
  data.setUint16(42, name.length * 2);
  for (var i = 0; i < name.length; i++) {
    data.setUint16(46 + i * 2, name.codeUnitAt(i));
  }
  return data.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, destination;
  late String previousFont;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-font-import-test-');
    destination = Directory('${root.path}/font');
    previousFont = FontModel(label: 'old', name: 'book', path: 'book').toJson();
    SharedPreferences.setMockInitialValues(
        {'locale': 'zh-CN', 'font': previousFont});
    await Prefs().initPrefs();
  });
  tearDown(() async => root.delete(recursive: true));

  Future<PlatformFile> source(String filename, String label) async {
    final bytes = namedFont(label);
    final file = await File('${root.path}/$filename').writeAsBytes(bytes);
    return PlatformFile(name: filename, path: file.path, size: bytes.length);
  }

  test('applies after copying and saving; Chinese filename survives reopening',
      () async {
    final item = await source('京華老宋体v3.0.ttf', '京華老宋体');
    final applied = <FontModel>[];
    final result = await importFontFiles([item],
        directory: destination, serverPort: 12345, onApplied: (font) {
      expect(File('${destination.path}/${item.name}').existsSync(), isTrue);
      expect(jsonDecode(Prefs().prefs.getString('font')!)['name'], font.name);
      applied.add(font);
    });
    expect(result.failed, 0);
    expect(applied.single.label, '京華老宋体');
    expect(result.font, applied.single);
    final restored =
        FontModel.fromJson(Prefs().prefs.getString('font')!, serverPort: 54321);
    expect(restored.litePath, item.name);
    expect(Uri.parse(restored.path).port, 54321);
    expect(await destination.list().length, 1);
  });

  test(
      'batch applies only the last successful font, even if the last file fails',
      () async {
    final first = await source('first.ttf', '第一');
    final second = await source('second.otf', '第二');
    final applied = <FontModel>[];
    final result = await importFontFiles([
      first,
      second,
      PlatformFile(name: 'missing.ttf', size: 0),
    ], directory: destination, serverPort: 12345, onApplied: applied.add);
    expect(result.failed, 1);
    expect(result.font!.label, '第二');
    expect(applied, hasLength(1));
    expect(await destination.list().length, 2);
  });

  test('empty selection and all-failed import preserve previous font',
      () async {
    for (final files in <List<PlatformFile>>[
      [],
      [
        PlatformFile(
            name: 'missing.ttf', path: '${root.path}/missing.ttf', size: 0)
      ],
    ]) {
      var applied = false;
      final result = await importFontFiles(files,
          directory: destination,
          serverPort: 12345,
          onApplied: (_) => applied = true);
      expect(result.font, isNull);
      expect(applied, isFalse);
      expect(Prefs().prefs.getString('font'), previousFont);
    }
  });

  test('English import applies independently and survives reopening', () async {
    await Server().start();
    addTearDown(() => Server().stop());
    final item = await source('English.ttf', 'English Serif');
    final applied = <FontModel>[];
    final result = await importFontFiles([item],
        directory: destination,
        serverPort: 12345,
        target: FontTarget.english,
        onApplied: applied.add);
    expect(result.failed, 0);
    expect(applied.single.label, 'English Serif');
    expect(Prefs().prefs.getString('font'), previousFont);
    expect(Prefs().englishFont!.litePath, 'English.ttf');
    await Prefs().initPrefs();
    expect(Prefs().englishFont!.litePath, 'English.ttf');
    await importFontFiles([await source('中文.ttf', '中文')],
        directory: destination, serverPort: 12345);
    expect(Prefs().englishFont!.litePath, 'English.ttf');
    Prefs().englishFont = null;
    expect(Prefs().englishFont, isNull);
    expect(jsonDecode(Prefs().prefs.getString('font')!)['label'], '中文');
  });

  test('cancelled or failed English imports preserve both choices', () async {
    final previousEnglish =
        FontModel(label: 'English', name: 'system', path: 'system');
    Prefs().englishFont = previousEnglish;
    for (final files in <List<PlatformFile>>[
      [],
      [PlatformFile(name: 'missing.ttf', size: 0)],
    ]) {
      final result = await importFontFiles(files,
          directory: destination,
          serverPort: 12345,
          target: FontTarget.english);
      expect(result.font, isNull);
      expect(Prefs().englishFont!.name, 'system');
      expect(Prefs().prefs.getString('font'), previousFont);
    }
  });

  test(
      'bad replacement does not overwrite existing font and leaves no staging directory',
      () async {
    await destination.create();
    final old = await File('${destination.path}/bad.ttf')
        .writeAsBytes(namedFont('原来字体'));
    final oldBytes = await old.readAsBytes();
    final bad = await File('${root.path}/bad.ttf').writeAsBytes([0, 1]);
    final result = await importFontFiles([
      PlatformFile(name: 'bad.ttf', path: bad.path, size: 2),
    ], directory: destination, serverPort: 12345);
    expect(result.failed, 1);
    expect(result.font, isNull);
    expect(await old.readAsBytes(), oldBytes);
    expect(Prefs().prefs.getString('font'), previousFont);
    expect(await destination.list().length, 1);
  });

  test(
      'valid replacement updates face identity and can import from the font folder itself',
      () async {
    final first = await source('replace.ttf', '原字体');
    final a = await importFontFiles([first],
        directory: destination, serverPort: 12345);
    final second = await source('replace.ttf', '新字体');
    final b = await importFontFiles([second],
        directory: destination, serverPort: 12345);
    expect(a.font!.name, isNot(b.font!.name));
    final c = await importFontFiles([
      PlatformFile(
          name: 'replace.ttf',
          path: '${destination.path}/replace.ttf',
          size: 0),
    ], directory: destination, serverPort: 12345);
    expect(c.failed, 0);
    expect(c.font!.name, b.font!.name);
    expect(await destination.list().length, 1);
  });
}
