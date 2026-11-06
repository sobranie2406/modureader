import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/installed_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, fonts;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modu-remove-font-');
    fonts = await Directory('${root.path}/fonts').create();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  tearDown(() => root.delete(recursive: true));

  test('removes app copy and only matching font references, preserving styles',
      () async {
    const filename = '示例%20字体.ttf';
    final source = await File('${root.path}/$filename').writeAsString('font');
    await source.copy('${fonts.path}/$filename');
    final prefs = Prefs().prefs;
    for (final key in ['font', 'englishFont', 'excerptShareFont']) {
      await prefs.setString(
          key, jsonEncode({'name': 'custom', 'path': filename}));
    }
    await prefs.setString(
        'languageTranslationTextStyle',
        jsonEncode({
          'font': filename,
          'size': 24,
          'bold': true,
          'italic': true,
        }));
    const classical = '{"font":"other.otf","size":30}';
    await prefs.setString('classicalTranslationTextStyle', classical);
    await prefs.setString(
        'documentTextStyles',
        jsonEncode({
          'a': {'font': filename, 'size': 28, 'margin': 33},
          'b': {'font': 'other.otf', 'size': 16},
        }));
    await prefs.setString(
        'readingInfo',
        jsonEncode({
          'header': {'font': filename, 'color': '#123456', 'opacity': .7},
          'footer': {'font': 'other.otf', 'fontSize': 14},
        }));
    final events = <String>[];
    final subscription = removedFonts.listen(events.add);
    final changed = await removeInstalledFont(filename, directory: fonts);
    expect(await source.exists(), isTrue);
    expect(await File('${fonts.path}/$filename').exists(), isFalse);
    expect(changed, containsAll(['font', 'englishFont', 'excerptShareFont']));
    expect(prefs.getString('font'), isNull);
    expect(prefs.getString('englishFont'), isNull);
    expect(prefs.getString('excerptShareFont'), isNull);
    expect(jsonDecode(prefs.getString('languageTranslationTextStyle')!),
        {'font': '', 'size': 24, 'bold': true, 'italic': true});
    expect(prefs.getString('classicalTranslationTextStyle'), classical);
    expect(jsonDecode(prefs.getString('documentTextStyles')!), {
      'a': {'font': '', 'size': 28, 'margin': 33},
      'b': {'font': 'other.otf', 'size': 16},
    });
    expect(jsonDecode(prefs.getString('readingInfo')!), {
      'header': {'font': '', 'color': '#123456', 'opacity': .7},
      'footer': {'font': 'other.otf', 'fontSize': 14},
    });
    expect(events, [filename]);
    await subscription.cancel();
  });

  test('protects bundled fonts, traversal, directories and links', () async {
    final bundled = await File('${fonts.path}/$bundledFontFilename')
        .writeAsString('builtin');
    final external =
        await File('${root.path}/outside.ttf').writeAsString('original');
    await Link('${fonts.path}/linked.ttf').create(external.path);
    await Directory('${fonts.path}/folder.ttf').create();
    for (final name in [
      bundledFontFilename,
      bundledFontFilename.toUpperCase(),
      '../outside.ttf',
      'nested/font.ttf',
      r'nested\font.ttf',
      'font.zip',
      'linked.ttf',
      'folder.ttf',
      'absent.otf'
    ]) {
      await expectLater(
          removeInstalledFont(name, directory: fonts), throwsA(anything));
    }
    expect(await bundled.exists(), isTrue);
    expect(await external.readAsString(), 'original');
    expect(installedFontFiles(fonts).map((f) => f.uri.pathSegments.last),
        [bundledFontFilename]);
  });

  test('unused download removal preserves all preference bytes', () async {
    await File('${fonts.path}/download.otf').writeAsString('font');
    const old = '{"name":"custom","path":"retained.ttf"}';
    await Prefs().prefs.setString('font', old);
    expect(
        await removeInstalledFont('download.otf', directory: fonts), isEmpty);
    expect(Prefs().prefs.getString('font'), old);
  });

  test('invalid saved data fails before deleting or changing preferences',
      () async {
    final file = await File('${fonts.path}/font.ttf').writeAsString('font');
    const old = '{"path":"font.ttf"}';
    await Prefs().prefs.setString('font', old);
    await Prefs().prefs.setString('documentTextStyles', '{broken');
    await expectLater(removeInstalledFont('font.ttf', directory: fonts),
        throwsFormatException);
    expect(await file.exists(), isTrue);
    expect(Prefs().prefs.getString('font'), old);
  });
}
