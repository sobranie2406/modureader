import 'dart:async';
import 'package:modu_reader/models/translation_text_style.dart';
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

  for (final reflow in [false, true]) {
    testWidgets(
        'language appearance shortcut preserves running translation (reflow=$reflow)',
        (tester) async {
      final mode = ValueNotifier(TranslationModeEnum.bilingual);
      var calls = 0;
      const other =
          '{"font":"serif","size":22,"bold":true,"italic":false,"color":"#287FA3"}';
      Prefs().classicalTranslationTextStyle = other;
      final bodyPalette = Prefs().readTheme.toJson();
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: TranslationWidget(
          bookId: 1,
          epubPlayerKey: GlobalKey<EpubPlayerState>(),
          pageTranslationMode: mode,
          onTranslatePage: reflow
              ? (_, __) async {
                  calls++;
                }
              : null,
          onStopPageTranslation: () {
            calls++;
            mode.value = TranslationModeEnum.off;
          },
        )),
      ));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('reader-language-appearance')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('language-style-font')), findsOneWidget);
      expect(find.byKey(const ValueKey('classical-style-font')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('language-style-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('text-color-preset-#287D75')));
      await tester.tap(find.byKey(const ValueKey('save-font-color')));
      await tester.pumpAndSettle();
      expect(
          TranslationTextStyle.decode(Prefs().languageTranslationTextStyle)
              .color,
          '#287D75');
      expect(Prefs().classicalTranslationTextStyle, other);
      expect(Prefs().readTheme.toJson(), bodyPalette);
      Navigator.of(
              tester.element(find.byKey(const ValueKey('language-style-font'))))
          .pop();
      await tester.pumpAndSettle();
      expect(mode.value, TranslationModeEnum.bilingual);
      expect(calls, 0);
      expect(find.byKey(const ValueKey('reader-stop-translation')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      mode.dispose();
    });
  }
  testWidgets(
      'classical panel stays usable on narrow screens and stops pending work',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final mode = ValueNotifier(TranslationModeEnum.off);
    final pending = Completer<void>();
    var stopped = false;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      builder: (context, child) => MediaQuery(
        data:
            MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
          body: TranslationWidget(
        bookId: 1,
        classical: true,
        epubPlayerKey: GlobalKey<EpubPlayerState>(),
        pageTranslationMode: mode,
        onTranslatePage: (display, _) {
          mode.value = display;
          return pending.future;
        },
        onStopPageTranslation: () {
          stopped = true;
          mode.value = TranslationModeEnum.off;
        },
      )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Translate visible content'));
    await tester.tap(find.text('Translate visible content'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    final stop = find.byKey(const ValueKey('reader-stop-translation'));
    await tester.ensureVisible(stop);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(stopped, isTrue);
    pending.complete();
    await tester.pumpAndSettle();
    expect(mode.value, TranslationModeEnum.off);
    expect(find.text('Translate visible content'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    mode.dispose();
  });

  testWidgets(
      'shared reader settings translate this page and reuse display changes',
      (tester) async {
    final mode = ValueNotifier(TranslationModeEnum.off);
    final calls = <(TranslationModeEnum, bool)>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
          body: SingleChildScrollView(
              child: TranslationWidget(
        bookId: 1,
        epubPlayerKey: GlobalKey<EpubPlayerState>(),
        pageTranslationMode: mode,
        onTranslatePage: (display, force) async {
          calls.add((display, force));
          mode.value = display;
        },
        onStopPageTranslation: () => mode.value = TranslationModeEnum.off,
      ))),
    ));
    await tester.pumpAndSettle();
    const guidance = 'Translate visible paragraphs and continue as you scroll.';
    expect(find.text(guidance), findsNothing);
    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pumpAndSettle();
    expect(find.text(guidance), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translate visible content'));
    await tester.pumpAndSettle();
    expect(calls, [(TranslationModeEnum.bilingual, false)]);
    await tester.tap(find.text('Translation only'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply display mode'));
    await tester.pumpAndSettle();
    expect(calls.last, (TranslationModeEnum.translationOnly, false));
    await tester.tap(find.text('Retranslate current content'));
    await tester.pumpAndSettle();
    expect(calls.last, (TranslationModeEnum.translationOnly, true));
    await tester.tap(find.byKey(const ValueKey('reader-stop-translation')));
    await tester.pumpAndSettle();
    expect(mode.value, TranslationModeEnum.off);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    mode.dispose();
  });

  testWidgets('stop during page translation ignores late completion',
      (tester) async {
    final mode = ValueNotifier(TranslationModeEnum.off);
    final pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
          body: SingleChildScrollView(
              child: TranslationWidget(
        bookId: 1,
        epubPlayerKey: GlobalKey<EpubPlayerState>(),
        pageTranslationMode: mode,
        onTranslatePage: (display, _) {
          mode.value = display;
          return pending.future;
        },
        onStopPageTranslation: () => mode.value = TranslationModeEnum.off,
      ))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translate visible content'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reader-stop-translation')));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(mode.value, TranslationModeEnum.off);
    expect(find.text('Translate visible content'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    mode.dispose();
  });
}
