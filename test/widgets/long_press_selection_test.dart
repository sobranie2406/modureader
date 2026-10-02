import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_catalogs.g.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/long_press_selection_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('paragraph selection is opt-in and persists across preference reloads',
      () async {
    expect(Prefs().longPressSelectParagraph, false);
    for (final value in [true, false]) {
      Prefs().longPressSelectParagraph = value;
      await Prefs().initPrefs();
      expect(Prefs().longPressSelectParagraph, value);
    }
  });

  test('all app languages provide the selection setting and help', () {
    for (final catalog in moduCatalogs.values) {
      expect(catalog['reading_long_press_paragraph'], isNotEmpty);
      expect(catalog['reading_long_press_help'], isNotEmpty);
    }
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('en')]) {
    testWidgets(
        'localized switch toggles at narrow width and large text: $locale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => lookupL10n(locale));
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          ...GlobalMaterialLocalizations.delegates
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => LongPressSelectionTile(
                    value: Prefs().longPressSelectParagraph,
                    onChanged: (value) => setState(
                        () => Prefs().longPressSelectParagraph = value)))),
      ));
      await tester.pumpAndSettle();
      expect(
          find.text(locale.languageCode == 'zh'
              ? '长按选择整段'
              : 'Select paragraph on long press'),
          findsOneWidget);
      final tile = find.byKey(const ValueKey('long-press-select-paragraph'));
      await tester
          .tap(find.descendant(of: tile, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      expect(Prefs().longPressSelectParagraph, true);
      expect(tester.widget<SwitchListTile>(tile).value, true);
      expect(tester.takeException(), isNull);
    });
  }
}
