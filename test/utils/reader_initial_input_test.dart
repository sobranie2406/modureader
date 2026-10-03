import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/utils/webView/gererate_url.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'lastServerPort': 0});
    await Prefs().initPrefs();
    await Server().start();
  });
  tearDown(() => Server().stop());

  test('body classification is only requested by explicit import metadata work', () {
    Map<String, String> params({bool importing = false, bool inspect = false}) =>
        Uri.parse(generateUrl('https://example.test/book.epub', '',
            fontName: 'serif', fontPath: '',
            importing: importing, inspectDocumentOnImport: inspect)).queryParameters;
    expect(params(inspect: true).containsKey('inspectDocumentOnImport'), isFalse);
    expect(params(importing: true)['inspectDocumentOnImport'], 'false');
    expect(params(importing: true, inspect: true)['inspectDocumentOnImport'], 'true');
  });

  test('night palette is present on first load and saved palette is restored',
      () {
    final original = Prefs().readTheme;
    for (final night in [true, false]) {
      Prefs().readingNightMode = night;
      final uri = Uri.parse(generateUrl('https://example.test/book.epub', '',
          fontName: 'serif', fontPath: ''));
      final style = jsonDecode(uri.queryParameters['style']!);
      expect(
          style['backgroundColor'],
          night
              ? '#1C1C1EFF'
              : '#${original.backgroundColor.substring(2)}${original.backgroundColor.substring(0, 2)}');
      if (night) {
        expect(style['fontColor'], '#D8D8D8FF');
        expect(style['backgroundImage'], 'none');
      }
      expect(Prefs().readTheme.toJson(), original.toJson());
    }
  });

  test('fresh reader URL uses the selected book profile, not another book',
      () async {
    const css = r'p::after { content: "${value}`\\中文"; }';
    await Prefs().saveCustomCssProfile(6, const CustomCssProfile(css: css));
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 6, enabled: true),
        bookKey: 'A');
    final a = Uri.parse(generateUrl('https://example.test/book.epub', '',
        fontName: 'serif', fontPath: '', cssBookKey: 'A'));
    final b = Uri.parse(generateUrl('https://example.test/other.epub', '',
        fontName: 'serif', fontPath: '', cssBookKey: 'B'));
    expect(jsonDecode(a.queryParameters['style']!)['customCSS'], css);
    expect(jsonDecode(a.queryParameters['style']!)['customCSSEnabled'], isTrue);
    expect(
        jsonDecode(b.queryParameters['style']!)['customCSSEnabled'], isFalse);
    expect(jsonDecode(b.queryParameters['style']!)['customCSS'], isEmpty);
  });

  test('fresh book URL enables platform input before any style change', () {
    for (final tapOnly in [false, true]) {
      Prefs().tapOnlyPageTurn = tapOnly;
      final uri = Uri.parse(generateUrl('https://example.test/book.epub', '',
          fontName: 'serif', fontPath: ''));
      final style = jsonDecode(uri.queryParameters['style']!);
      expect(style['desktopPageInput'], AnxPlatform.isDesktop);
      expect(style['mobileTouchPaging'], AnxPlatform.isMobile);
      expect(style['mobileImageFit'], AnxPlatform.isMobile);
      expect(style['tapOnlyPageTurn'], tapOnly);
    }
  });

  test('scroll page percentage is applied on first open', () {
    for (final percent in [80, 91, 100]) {
      Prefs().scrollPagePercent = percent;
      final uri = Uri.parse(generateUrl('https://example.test/book.epub', '',
          fontName: 'serif', fontPath: ''));
      expect(jsonDecode(uri.queryParameters['style']!)['scrollPagePercent'],
          percent);
    }
  });

  test('simulated bold and its weight are supplied on first open', () async {
    for (final enabled in [false, true]) {
      await Prefs().saveBookStyleToPrefs(
          Prefs().bookStyle.copyWith(fontWeight: 640, simulateBold: enabled));
      final uri = Uri.parse(generateUrl('https://example.test/book.epub', '',
          fontName: 'body', fontPath: '/body.ttf'));
      final style = jsonDecode(uri.queryParameters['style']!);
      expect(style['simulateBold'], enabled);
      expect(style['fontWeight'], 640);
    }
  });

  test('long-press mode and app language are applied on first open', () async {
    for (final paragraph in [false, true]) {
      Prefs().longPressSelectParagraph = paragraph;
      await Prefs().saveLocaleToPrefs('zh-CN');
      final uri = Uri.parse(generateUrl('https://example.test/book.epub', '',
          fontName: 'serif', fontPath: ''));
      final style = jsonDecode(uri.queryParameters['style']!);
      expect(style['longPressSelectParagraph'], paragraph);
      expect(style['selectionLocale'], 'zh-CN');
    }
  });

  test('reader receives e-ink mode without changing the saved page style', () {
    final savedStyle = Prefs().pageTurnStyle;
    for (final eInk in [true, false]) {
      Prefs().eInkMode = eInk;
      final uri = Uri.parse(generateUrl('https://example.test/book.epub', '',
          fontName: 'serif', fontPath: ''));
      final style = jsonDecode(uri.queryParameters['style']!);
      expect(style['eInkMode'], eInk);
      expect(style['pageTurnStyle'], savedStyle.name);
      expect(Prefs().pageTurnStyle, savedStyle);
    }
  });

  test('independent English face is included on first open and can follow body',
      () {
    Map<String, dynamic> style() =>
        jsonDecode(Uri.parse(generateUrl('https://example.test/book.epub', '',
                fontName: 'body', fontPath: '/body.ttf'))
            .queryParameters['style']!);
    expect(style()['englishFontName'], isNull);
    Prefs().englishFont =
        FontModel(label: 'Latin', name: 'latin', path: 'latin.ttf');
    expect(style()['englishFontName'], 'latin');
    expect(style()['englishFontPath'], contains('latin.ttf'));
    expect(style()['fontName'], 'body');
    Prefs().englishFont = null;
    expect(style()['englishFontName'], isNull);
  });
}
