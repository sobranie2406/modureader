import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/utils/theme_mode_to_string.dart';
import 'package:modu_reader/widgets/settings/theme_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('theme values use canonical names, including legacy setter input',
      () async {
    for (final mode in ThemeMode.values) {
      expect(themeModeToString(mode), mode.name);
      await Prefs().saveThemeModeToPrefs(mode.name);
      expect(Prefs().prefs.getString('themeMode'), mode.name);
      expect(Prefs().themeMode, mode);
    }
    await Prefs().saveThemeModeToPrefs('auto');
    expect(Prefs().prefs.getString('themeMode'), 'system');
    expect(Prefs().themeMode, ThemeMode.system);
  });

  for (final saved in [null, 'auto', 'system', 'light', 'dark']) {
    testWidgets('theme selector reads $saved and saves system', (tester) async {
      if (saved != null) await Prefs().prefs.setString('themeMode', saved);
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: ChangeThemeMode()),
      ));
      await tester.pumpAndSettle();
      final selector = find.byType(SegmentedButton<String>);
      expect(tester.widget<SegmentedButton<String>>(selector).selected,
          {saved == 'light' || saved == 'dark' ? saved : 'system'});
      final context = tester.element(selector);
      await tester.tap(find.text(L10n.of(context).settingsDarkMode));
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10n.of(context).settingsSystemMode));
      await tester.pumpAndSettle();
      expect(Prefs().prefs.getString('themeMode'), 'system');
      expect(tester.widget<SegmentedButton<String>>(selector).selected,
          {'system'});
      expect(tester.takeException(), isNull);
    });
  }
}
