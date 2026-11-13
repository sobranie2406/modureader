import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/page/settings_page/css_settings.dart';
import 'package:modu_reader/page/settings_page/reading.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets('Reading opens CSS management and returns at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        navigatorKey: navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: ReadingSettings()),
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-popup-height-percent')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('reader-menu-opacity-percent')),
          findsOneWidget);
      final entry = find.byKey(const ValueKey('reading-css-settings'));
      await tester.scrollUntilVisible(entry.hitTestable(), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(CssSettings), findsOneWidget);
      expect(
          tester.widget<CustomCSSEditor>(find.byType(CustomCSSEditor)).manage,
          isTrue);
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(CssSettings), findsNothing);
      expect(entry, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
