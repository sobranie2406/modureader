import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/document_text_menu.dart';
import 'package:anx_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final size in [const Size(320, 600), const Size(640, 480)]) {
    for (final brightness in Brightness.values) {
      for (final language in ['zh', 'en']) {
        testWidgets('text menu retains actions at $size $brightness $language',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var reflows = 0;
          var extractions = 0;
          var exports = 0;
          bool? comparison, forceOcr;
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            locale: Locale(language),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
                body: DocumentTextMenu(
              openReflow: () => reflows++,
              openExtraction: () => extractions++,
              exportText: () => exports++,
              onComparisonChanged: (value) => comparison = value,
              onForceOcrChanged: (value) => forceOcr = value,
            )),
          ));
          await tester.pumpAndSettle();
          expect(
              find.text(language == 'zh' ? '导出本书已保存文字' : 'Export saved text'),
              findsOneWidget);
          expect(find.textContaining('已保存文字 TXT'), findsNothing);
          expect(find.byWidgetPredicate((widget) => widget is Card),
              findsNWidgets(3));
          for (final key in [
            'document-reflow-entry',
            'document-force-ocr-switch',
            'document-comparison-switch',
            'document-extraction-entry',
            'export-saved-txt'
          ]) {
            final target = find.byKey(ValueKey(key));
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            final switchControl =
                find.descendant(of: target, matching: find.byType(Switch));
            final label =
                find.descendant(of: target, matching: find.byType(Text)).first;
            await tester.tap(
                switchControl.evaluate().isNotEmpty ? switchControl : label);
            await tester.pumpAndSettle();
          }
          expect((reflows, extractions, exports, comparison), (1, 1, 1, true));
          expect(forceOcr, isTrue);
          expect(Prefs().ocrPrecacheEnabled, isFalse);
          final scroll = find
              .descendant(
                  of: find.byType(ReaderSettingsScrollView),
                  matching: find.byType(Scrollable))
              .first;
          tester.state<ScrollableState>(scroll).position.jumpTo(0);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
      'unavailable callbacks remain disabled; comparison stays optional',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DocumentTextMenu())));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('document-comparison-switch')), findsNothing);
    for (final key in [
      'document-reflow-entry',
      'document-extraction-entry',
      'export-saved-txt'
    ]) {
      expect(tester.widget<ListTile>(find.byKey(ValueKey(key))).onTap, isNull);
    }
  });
}
