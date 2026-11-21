import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/page/book_player/epub_player.dart';
import 'package:modu_reader/widgets/reading_page/translation_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final classical in [false, true]) {
    for (final locale in ['en', 'zh']) {
      testWidgets(
          'prefetch choice stays independent without starting or stopping translation classical=$classical locale=$locale',
          (tester) async {
        await tester.runAsync(() => L10n.delegate.load(Locale(locale)));
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final mode = ValueNotifier(TranslationModeEnum.bilingual);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          mode.dispose();
        });
        var translated = 0, stopped = 0;
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale(locale),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!),
          home: Scaffold(
              body: TranslationWidget(
            bookId: 1,
            classical: classical,
            epubPlayerKey: GlobalKey<EpubPlayerState>(),
            pageTranslationMode: mode,
            onTranslatePage: (_, __) async {
              translated++;
            },
            onStopPageTranslation: () => stopped++,
          )),
        ));
        await tester.pumpAndSettle();
        final field = find.byKey(ValueKey(classical
            ? 'reader-classical-prefetch-pages'
            : 'reader-language-prefetch-pages'));
        final dropdown = find.descendant(
            of: field, matching: find.byType(DropdownButton<int>));
        expect(field, findsOneWidget);
        expect(dropdown, findsOneWidget);
        expect(
            tester
                .widget<DropdownButton<int>>(dropdown)
                .items!
                .map((item) => item.value),
            [0, 1, 2, 3, 4, 5]);
        expect(tester.widget<DropdownButton<int>>(dropdown).value, 0);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text('5').last);
        await tester.pumpAndSettle();
        expect(
            classical
                ? Prefs().classicalTranslationPrefetchPages
                : Prefs().languageTranslationPrefetchPages,
            5);
        expect(
            classical
                ? Prefs().languageTranslationPrefetchPages
                : Prefs().classicalTranslationPrefetchPages,
            0);

        if (classical) {
          Prefs().classicalTranslationPrefetchPages = 3;
        } else {
          Prefs().languageTranslationPrefetchPages = 3;
        }
        await tester.pumpAndSettle();
        expect(tester.widget<DropdownButton<int>>(dropdown).value, 3);

        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(locale == 'zh' ? '关闭' : 'Off').last);
        await tester.pumpAndSettle();
        expect(
            classical
                ? Prefs().classicalTranslationPrefetchPages
                : Prefs().languageTranslationPrefetchPages,
            0);
        expect(translated, 0);
        expect(stopped, 0);
        expect(mode.value, TranslationModeEnum.bilingual);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
