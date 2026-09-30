import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    for (final delegate in L10n.localizationsDelegates) {
      if (delegate.isSupported(const Locale('en'))) {
        await delegate.load(const Locale('en'));
      }
    }
  });

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: widget!,
      ),
      home: const Scaffold(body: TranslateSetting()),
    ));
    await tester.pumpAndSettle();
  }

  for (final engine in [
    TranslateService.baiduWeb,
    TranslateService.youdaoWeb
  ]) {
    testWidgets(
        '${engine.name} picker saves selection without changing full text',
        (tester) async {
      Prefs().fullTextTranslateService = TranslateService.deepl;
      await open(tester);
      await tester
          .tap(find.byKey(const ValueKey('selection-translation-engine')));
      await tester.pumpAndSettle();
      final target = find.byKey(ValueKey('translation-engine-${engine.name}'));
      await tester.scrollUntilVisible(target, 180,
          scrollable: find
              .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable))
              .first);
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(Prefs().translateService, engine);
      expect(Prefs().fullTextTranslateService, TranslateService.deepl);
      expect(find.byKey(const ValueKey('fulltext-translation-engine')),
          findsOneWidget);
      await tester
          .tap(find.byKey(const ValueKey('fulltext-translation-engine')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('translation-engine-${engine.name}')),
          findsNothing);
      await tester
          .tap(find.byKey(const ValueKey('translation-engine-microsoftFree')));
      await tester.pumpAndSettle();
      expect(Prefs().translateService, engine);
      expect(Prefs().fullTextTranslateService, TranslateService.microsoftFree);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('web engine picker scrolls on a small screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, scale: 2);
    await tester
        .tap(find.byKey(const ValueKey('selection-translation-engine')));
    await tester.pumpAndSettle();
    final target = find.byKey(const ValueKey('translation-engine-youdaoWeb'));
    await tester.scrollUntilVisible(target, 200,
        scrollable: find
            .descendant(
                of: find.byType(BottomSheet), matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(Prefs().translateService, TranslateService.youdaoWeb);
    expect(tester.takeException(), isNull);
  });
}
