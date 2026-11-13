import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/settings_page/translate.dart';
import 'package:modu_reader/service/translate/index.dart';
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

  Future<void> open(WidgetTester tester,
      {double scale = 1, bool classical = false}) async {
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
    expect(find.byKey(const ValueKey('translation-settings-classical')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('selection-translation-engine')),
        findsNothing);
    await tester.tap(find.byKey(ValueKey(classical
        ? 'translation-settings-classical'
        : 'translation-settings-language')));
    await tester.pumpAndSettle();
  }

  for (final engine in [
    TranslateService.baiduApi,
    TranslateService.microsoftApi
  ]) {
    testWidgets('${engine.name} is selectable and saves shared credentials',
        (tester) async {
      await open(tester);
      await tester
          .tap(find.byKey(const ValueKey('selection-translation-engine')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(ValueKey('translation-engine-${engine.name}')));
      await tester.pumpAndSettle();
      expect(Prefs().fullTextTranslateService, engine);
      final baidu = engine == TranslateService.baiduApi;
      final key = baidu ? 'baidu_key' : 'microsoft_key';
      if (baidu) {
        await tester.enterText(
            find.byKey(const ValueKey('baidu_appid')), 'app-id');
      }
      await tester.enterText(find.byKey(ValueKey(key)), 'test-secret');
      final save = find.byKey(const ValueKey('save-classical-credentials'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(Prefs().classicalTranslationConfig[key], 'test-secret');
      expect(engine.provider.getConfig()[key], 'test-secret');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('classical subpage has independent service and output appearance',
      (tester) async {
    await open(tester, classical: true);
    expect(find.byKey(const ValueKey('classical-engine-ai')), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-translation-engine')),
        findsNothing);
    await tester
        .ensureVisible(find.byKey(const ValueKey('classical-style-font')));
    expect(find.byKey(const ValueKey('classical-style-font')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('language subpage has its own output appearance', (tester) async {
    await open(tester);
    final font = find.byKey(const ValueKey('language-style-font'));
    await tester.ensureVisible(font);
    expect(font, findsOneWidget);
    expect(find.byKey(const ValueKey('classical-style-font')), findsNothing);
    expect(tester.takeException(), isNull);
  });

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
