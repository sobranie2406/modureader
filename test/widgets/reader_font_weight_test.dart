import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: StyleSettings())),
    ));
    await tester.pumpAndSettle();
  }

  Finder getWeight() => find.descendant(
      of: find.byWidgetPredicate((widget) =>
          widget is StyleSlider && widget.icon == Icons.format_bold),
      matching: find.byType(Slider));

  testWidgets('advanced settings no longer duplicate the font weight slider',
      (tester) async {
    Prefs().useBookStyles = false;
    await Prefs()
        .saveBookStyleToPrefs(Prefs().bookStyle.copyWith(fontWeight: 700));
    await show(tester);
    expect(getWeight(), findsNothing);
    expect(Prefs().bookStyle.fontWeight, 700);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'following book styles disables weight without resetting saved choice',
      (tester) async {
    await Prefs()
        .saveBookStyleToPrefs(Prefs().bookStyle.copyWith(fontWeight: 700));
    Prefs().useBookStyles = true;
    await show(tester);
    expect(getWeight(), findsNothing);
    tester
        .widget<SwitchListTile>(find.byType(SwitchListTile).first)
        .onChanged!(false);
    await tester.pumpAndSettle();
    expect(getWeight(), findsNothing);
    expect(Prefs().bookStyle.fontWeight, 700);
    expect(tester.takeException(), isNull);
  });
}
