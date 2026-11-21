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
          'prefetch switch remembers its bounded page count independently classical=$classical locale=$locale',
          (tester) async {
        await tester.runAsync(() => L10n.delegate.load(Locale(locale)));
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const languageStyle =
            '{"font":"serif","size":18,"bold":false,"italic":true}';
        const classicalStyle =
            '{"font":"monospace","size":22,"bold":true,"italic":false}';
        Prefs().languageTranslationTextStyle = languageStyle;
        Prefs().classicalTranslationTextStyle = classicalStyle;
        final mode = ValueNotifier(TranslationModeEnum.bilingual);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          mode.dispose();
        });
        var translated = 0, stopped = 0;
        Widget app() => MaterialApp(
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
            );
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        final field = find.byKey(ValueKey(classical
            ? 'reader-classical-prefetch-pages'
            : 'reader-language-prefetch-pages'));
        final toggle =
            find.descendant(of: field, matching: find.byType(Switch));
        final minus = find.descendant(
            of: field, matching: find.widgetWithIcon(IconButton, Icons.remove));
        final plus = find.descendant(
            of: field, matching: find.widgetWithIcon(IconButton, Icons.add));
        int effectivePages() => classical
            ? Prefs().classicalTranslationPrefetchPages
            : Prefs().languageTranslationPrefetchPages;
        Future<void> change(Finder control) async {
          await tester.ensureVisible(control);
          await tester.tap(control);
          await tester.pumpAndSettle();
        }

        void expectPages(int pages) {
          expect(effectivePages(), pages);
          expect(Prefs().translationPrefetchPageCount(classical: classical),
              pages);
          expect(find.descendant(of: field, matching: find.text('$pages')),
              findsOneWidget);
        }

        expect(field, findsOneWidget);
        expect(
            find.descendant(of: field, matching: find.byType(SwitchListTile)),
            findsOneWidget);
        expect(
            find.descendant(
                of: field, matching: find.byType(DropdownButton<int>)),
            findsNothing);
        expect(tester.widget<Switch>(toggle).value, false);
        expect(effectivePages(), 0);
        expect(Prefs().translationPrefetchPageCount(classical: classical), 3);
        expect(minus, findsNothing);
        expect(plus, findsNothing);

        await change(toggle);
        expect(tester.widget<Switch>(toggle).value, true);
        expectPages(3);
        for (final pages in [2, 1]) {
          await change(minus);
          expectPages(pages);
        }
        expect(tester.widget<IconButton>(minus).onPressed, isNull);
        for (final pages in [2, 3, 4, 5]) {
          await change(plus);
          expectPages(pages);
        }
        expect(tester.widget<IconButton>(plus).onPressed, isNull);
        expect(
            classical
                ? Prefs().languageTranslationPrefetchPages
                : Prefs().classicalTranslationPrefetchPages,
            0);

        if (classical) {
          Prefs().classicalTranslationPrefetchPages = 4;
        } else {
          Prefs().languageTranslationPrefetchPages = 4;
        }
        await tester.pumpAndSettle();
        expectPages(4);

        await change(toggle);
        expect(tester.widget<Switch>(toggle).value, false);
        expect(effectivePages(), 0);
        expect(Prefs().translationPrefetchPageCount(classical: classical), 4);
        expect(minus, findsNothing);
        expect(plus, findsNothing);
        await tester.pumpWidget(const SizedBox());
        await Prefs().initPrefs();
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(tester.widget<Switch>(toggle).value, false);
        await change(toggle);
        expectPages(4);
        expect(Prefs().translationPrefetchPageCount(classical: !classical), 3);
        expect(Prefs().languageTranslationTextStyle, languageStyle);
        expect(Prefs().classicalTranslationTextStyle, classicalStyle);
        expect(translated, 0);
        expect(stopped, 0);
        expect(mode.value, TranslationModeEnum.bilingual);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
