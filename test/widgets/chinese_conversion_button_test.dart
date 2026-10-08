import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/convert_chinese_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:anx_reader/widgets/reading_page/chinese_conversion_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh'));
  });

  for (final locale in ['zh', 'en']) {
    testWidgets('conversion persists, applies and restores original ($locale)',
        (tester) async {
      final applied = <ReadingRules>[];
      Prefs().readingRules = Prefs().readingRules.copyWith(bionicReading: true);
      await tester.pumpWidget(MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: ChineseConversionButton(onChanged: applied.add),
        ),
      ));
      await tester.pumpAndSettle();
      final l10n =
          L10n.of(tester.element(find.byType(ChineseConversionButton)));
      for (final entry in {
        ConvertChineseMode.s2t: l10n.readingPageTraditional,
        ConvertChineseMode.t2s: l10n.readingPageSimplified,
        ConvertChineseMode.none: l10n.readingPageOriginal,
      }.entries) {
        await tester.tap(find.byType(ChineseConversionButton));
        await tester.pumpAndSettle();
        await tester.tap(find.byWidgetPredicate((widget) =>
            widget is CheckedPopupMenuItem<ConvertChineseMode> &&
            widget.value == entry.key));
        await tester.pumpAndSettle();
        expect(Prefs().readingRules.convertChineseMode, entry.key);
        expect(applied.last.convertChineseMode, entry.key);
        expect(applied.last.bionicReading, isTrue);
        expect(find.text(entry.value), findsOneWidget);
      }
      // Selecting the current mode does not reload the reader unnecessarily.
      await tester.tap(find.byType(ChineseConversionButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((widget) =>
          widget is CheckedPopupMenuItem<ConvertChineseMode> &&
          widget.value == ConvertChineseMode.none));
      await tester.pumpAndSettle();
      expect(applied, hasLength(3));
      // Changes from advanced settings are reflected in the quick control.
      Prefs().readingRules = Prefs()
          .readingRules
          .copyWith(convertChineseMode: ConvertChineseMode.s2t);
      await tester.pump();
      expect(find.text(l10n.readingPageTraditional), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
