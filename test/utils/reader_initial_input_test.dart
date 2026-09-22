import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
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
}
