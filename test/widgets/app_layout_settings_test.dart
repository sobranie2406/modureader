import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/app_layout_mode.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/settings_page/appearance.dart';
import 'package:modu_reader/widgets/common/anx_segmented_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    await L10n.delegate.load(const Locale('en'));
    await L10n.delegate.load(const Locale('zh', 'CN'));
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('en')]) {
    testWidgets('appearance layout choices save and restore auto: $locale',
        (tester) async {
      tester.view.physicalSize = const Size(390, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: const Scaffold(body: AppearanceSetting()),
      ));
      await tester.pumpAndSettle();
      final control = find.byType(AnxSegmentedButton<AppLayoutMode>);
      await tester.scrollUntilVisible(control, 180,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      final zh = locale.languageCode == 'zh';
      for (final choice in [
        (zh ? '宽屏版' : 'Wide', AppLayoutMode.wide),
        (zh ? '窄屏版' : 'Narrow', AppLayoutMode.narrow),
        (zh ? '自动' : 'Auto', AppLayoutMode.auto)
      ]) {
        await tester
            .tap(find.descendant(of: control, matching: find.text(choice.$1)));
        await tester.pumpAndSettle();
        expect(Prefs().appLayoutMode, choice.$2);
        expect(
            tester.widget<AnxSegmentedButton<AppLayoutMode>>(control).selected,
            {choice.$2});
      }
      expect(tester.takeException(), isNull);
    });
  }
}
