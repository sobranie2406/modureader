import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/css_visual_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Prefs prefs;
  Future<void> init([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    prefs = Prefs();
    await prefs.initPrefs();
  }

  test('named presets available by default without enabling surprising CSS',
      () async {
    await init();
    expect(prefs.customCssProfiles, hasLength(customCssProfileCount));
    expect(prefs.customCssProfiles.take(8).every((p) => p.isEmpty), isTrue);
    expect(prefs.customCssProfiles[8].name, customCssTemplates.first.name);
    expect(prefs.customCssForBook(), isEmpty);
    expect(prefs.customCssSelection().enabled, isFalse);
    expect(prefs.customCssSelection().index, 0);
  });

  test('legacy eight slots keep their indexes when named presets are added',
      () async {
    final old = List.generate(8,
        (i) => CustomCssProfile(name: 'old-$i', css: 'p {color:red}').toJson());
    await init({
      'customCssProfiles': jsonEncode(old),
      'customCssDefaultIndex': 7,
      'customCSSEnabled': true,
    });
    expect(
        prefs.customCssProfiles.take(8).map((p) => p.toJson()).toList(), old);
    expect(prefs.customCssSelection().index, 7);
    expect(prefs.customCssForBook(), 'p {color:red}');
    await prefs.saveCustomCssProfile(7, prefs.customCssProfiles[7]);
    await prefs.initPrefs();
    expect(
        prefs.customCssProfiles.take(8).map((p) => p.toJson()).toList(), old);
    expect(prefs.customCssSelection().index, 7);
  });

  test(
      'local template fonts resolve against current device server, not exported port',
      () async {
    await init({'lastServerPort': 12345});
    await prefs.saveCustomCssProfile(
        0,
        const CustomCssProfile(
            name: 'Font', visual: CssVisualStyle({'fontFile': 'font 中文.ttf'})));
    expect(prefs.customCssForBook(),
        contains('http://127.0.0.1:12345/fonts/font%20'));
    prefs.lastServerPort = 23456;
    expect(prefs.customCssForBook(),
        contains('http://127.0.0.1:23456/fonts/font%20'));
    final portable = jsonEncode(prefs.customCssProfiles[0].toJson());
    expect(portable, isNot(contains('127.0.0.1')));
  });

  test('legacy CSS and enablement survive initial use and subsequent saves',
      () async {
    await init({'customCSS': 'p { color: red; }', 'customCSSEnabled': true});
    expect(prefs.customCssForBook(), 'p { color: red; }');
    await prefs.saveCustomCssProfile(
        7, const CustomCssProfile(name: '精排', css: 'p { margin: 0; }'));
    await prefs.initPrefs();
    expect(prefs.customCssProfiles[0].css, 'p { color: red; }');
    expect(prefs.customCssProfiles[7].name, '精排');
    expect(prefs.customCssSelection().enabled, isTrue);
    expect(prefs.customCssProfiles[1].css, isEmpty);
  });

  test('books independently remember profile and enablement after reopening',
      () async {
    await init();
    await prefs.saveCustomCssProfile(
        1, const CustomCssProfile(css: 'p { writing-mode: vertical-rl; }'));
    await prefs.saveCustomCssProfile(
        2, const CustomCssProfile(css: 'p { writing-mode: horizontal-tb; }'));
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 1, enabled: true),
        bookKey: 'A');
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 2, enabled: false),
        bookKey: 'B');
    await prefs.initPrefs();
    expect(prefs.customCssSelection('A').enabled, isTrue);
    expect(prefs.customCssSelection('B').enabled, isFalse);
    expect(prefs.customCssForBook('A'), contains('vertical-rl'));
    expect(prefs.customCssForBook('B'), contains('horizontal-tb'));
    expect(prefs.customCssSelection().enabled, isFalse);
    expect(prefs.customCssSelection('C').index, 0);
  });

  test('default and follow-default do not overwrite explicit book settings',
      () async {
    await init();
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 3, enabled: false),
        bookKey: 'A');
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 5, enabled: true));
    expect(prefs.customCssSelection('B').index, 5);
    expect(prefs.customCssSelection('A').index, 3);
    await prefs.clearBookCustomCssSelection('A');
    expect(prefs.hasBookCustomCssSelection('A'), isFalse);
    expect(prefs.customCssSelection('A').index, 5);
    expect(prefs.customCssSelection('A').enabled, isTrue);
  });

  test('invalid backup data and out-of-range indexes fall back safely',
      () async {
    await init({
      'customCSS': 'legacy',
      'customCssProfiles': '{broken',
      'customCssDefaultIndex': 99,
      'bookCustomCssSelections': jsonEncode({
        'A': {'index': -1, 'enabled': true}
      })
    });
    expect(prefs.customCssForBook('A'), 'legacy');
    expect(prefs.customCssSelection('A').index, 0);
    expect(prefs.customCssSelection('A').enabled, isFalse);
    await expectLater(
        prefs.saveCustomCssProfile(
            customCssProfileCount, const CustomCssProfile()),
        throwsRangeError);
    await expectLater(
        prefs.saveCustomCssSelection(
            const CustomCssSelection(index: -1, enabled: true)),
        throwsRangeError);
    expect(prefs.customCssForBook(), 'legacy');
  });

  test('profile backup keeps CSS but never transfers local book IDs', () async {
    await init();
    await prefs.saveCustomCssProfile(
        4, const CustomCssProfile(name: 'test', css: 'p {}'));
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 4, enabled: true),
        bookKey: 'A');
    final backup = await prefs.buildPrefsBackupMap();
    expect(backup, contains('customCssProfiles'));
    expect(backup, isNot(contains('bookCustomCssSelections')));
    await prefs.applyPrefsBackupMap({
      'bookCustomCssSelections': {'type': 'string', 'value': '{}'}
    });
    expect(prefs.customCssSelection('A').index, 4);
  });

  test('book identity survives file replacement and distinguishes reused IDs',
      () {
    final book = Book.mock();
    expect(customCssBookKey(book.copyWith(filePath: '/new.epub', title: 'new')),
        customCssBookKey(book));
    expect(
        customCssBookKey(book.copyWith(
            createTime: book.createTime.add(const Duration(seconds: 1)))),
        isNot(customCssBookKey(book)));
  });

  test('CSS is preserved verbatim including template literals and escapes',
      () async {
    await init();
    const code = r'p::after { content: "${notJavascript}`\\中文"; }';
    await prefs.saveCustomCssProfile(0, const CustomCssProfile(css: code));
    expect(prefs.customCssForBook(), code);
    expect(jsonDecode(jsonEncode(prefs.customCssForBook())), code);
  });

  test('multiple profiles cascade by slot; highlights are separate from CSS',
      () async {
    await init();
    await prefs.saveCustomCssProfile(
        0, const CustomCssProfile(css: 'p {color:red}'));
    await prefs.saveCustomCssProfile(
        1,
        const CustomCssProfile(
            css: 'color:blue;', pattern: '对白', scope: 'body'));
    await prefs.saveCustomCssProfile(
        2, const CustomCssProfile(css: 'p {color:green}'));
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(
            index: 7, enabled: true, indices: [2, 0, 1, 2]),
        bookKey: 'A');
    expect(prefs.customCssSelection('A').activeIndices, [0, 1, 2]);
    expect(prefs.customCssForBook('A'), 'p {color:red}\n\np {color:green}');
    expect(prefs.customHighlightRulesForBook('A').single['pattern'], '对白');
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 7, enabled: false, indices: [0, 1]),
        bookKey: 'A');
    expect(prefs.customHighlightRulesForBook('A'), isEmpty);
    expect(prefs.customCssSelection('A').activeIndices, [0, 1]);
  });

  test('deleted/reused slots are disabled in defaults and every book',
      () async {
    await init();
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 1, enabled: true, indices: [1, 3]));
    await prefs.saveCustomCssSelection(
        const CustomCssSelection(index: 1, enabled: true),
        bookKey: 'A');
    await prefs.disableCustomCssSlots({1});
    expect(prefs.customCssSelection().activeIndices, [3]);
    expect(prefs.customCssSelection('A').activeIndices, isEmpty);
    expect(prefs.customCssSelection('B').activeIndices, [3]);
  });
}
