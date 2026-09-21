import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/reading_page/vertical_page_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('web chrome shares localized labels and physical geometry', () {
    const chrome = VerticalPageChrome(
      geometry:
          VerticalPageGeometry(EdgeInsets.only(top: 24, bottom: 28), 12, 14),
      chapterTitle: '证明 <文字>',
      remainingPages: 40,
      currentPage: 45,
      totalPages: 1239,
      color: Color(0xb4334455),
      redFrame: true,
    );
    final zh = chrome.toWebStyle(const Locale('zh'));
    expect(zh['title'], '证明 <文字>');
    expect(zh['remaining'], '本章剩余四十页');
    expect(zh['progress'], '四十五·一千二百三十九');
    expect(zh['color'], '#334455');
    expect(zh['opacity'], closeTo(180 / 255, .001));
    expect(zh['safe']['top'], 24);
    expect(chrome.toWebStyle(const Locale('zh', 'TW'))['remaining'], '本章剩餘四十頁');
    expect(chrome.toWebStyle(const Locale('en'))['progress'], '45·1239');
  });
  test('Chinese numbers preserve units and zeros', () {
    for (final entry in {
      0: '零',
      10: '十',
      11: '十一',
      20: '二十',
      40: '四十',
      45: '四十五',
      101: '一百零一',
      110: '一百一十',
      1239: '一千二百三十九',
      10001: '一万零一',
      10010: '一万零一十',
      100000: '十万',
      100000001: '一亿零一'
    }.entries) {
      expect(chinesePageNumber(entry.key), entry.value);
    }
    expect(chinesePageNumber(10001, traditional: true), '一萬零一');
  });
  test('frame preference is opt-in and persists', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    expect(Prefs().verticalRedFrame, false);
    Prefs().verticalRedFrame = true;
    expect((await SharedPreferences.getInstance()).getBool('verticalRedFrame'),
        true);
  });
  for (final locale in [
    const Locale('zh'),
    const Locale('en'),
    const Locale('zh', 'TW')
  ]) {
    for (final frame in [true, false]) {
      testWidgets('vertical sidebar locale=$locale frame=$frame',
          (tester) async {
        tester.view.physicalSize = const Size(390, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          supportedLocales: const [
            Locale('zh'),
            Locale('en'),
            Locale('zh', 'TW')
          ],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const SizedBox(),
          builder: (context, _) => VerticalPageChrome(
            geometry: const VerticalPageGeometry(
                EdgeInsets.only(top: 24, bottom: 28), 12, 12),
            chapterTitle: '证明',
            remainingPages: 40,
            currentPage: 45,
            totalPages: 1239,
            color: Colors.black,
            redFrame: frame,
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('vertical-red-frame')),
            frame ? findsOneWidget : findsNothing);
        final texts = tester.widgetList<Text>(find.byType(Text)).toList();
        final title = texts
            .singleWhere((t) => t.semanticsLabel == '证明' || t.data == '证明');
        final footer = texts.singleWhere(
            (t) => (t.semanticsLabel ?? t.data ?? '').contains('·'));
        final titleRect = tester.getRect(find.byWidget(title));
        final footerRect = tester.getRect(find.byWidget(footer));
        expect(titleRect.left, greaterThan(340));
        expect(footerRect.right, lessThan(44));
        expect(footerRect.bottom, lessThan(780 - 28));
        if (locale.languageCode == 'zh') {
          expect(footer.semanticsLabel, '四十五·一千二百三十九');
          expect(
              texts.any((t) =>
                  t.semanticsLabel ==
                  (locale.countryCode == 'TW' ? '本章剩餘四十頁' : '本章剩余四十页')),
              true);
        } else {
          expect(footer.data, '45·1239');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
