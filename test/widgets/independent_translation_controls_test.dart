import 'package:modu_reader/enums/translation_mode.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/service/translate/reader_translation_modes.dart';
import 'package:modu_reader/widgets/reading_page/translation_toolbar_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('classical and language controls never show each other as active',
      (tester) async {
    final modes = ReaderTranslationModes();
    addTearDown(modes.dispose);
    var languageOpened = 0;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Scaffold(
          body: Row(children: [
        TranslationToolbarAction(
            mode: modes.language,
            onOpenSettings: () => languageOpened++,
            onStop: () {}),
        TranslationToolbarAction(
            classical: true,
            mode: modes.classical,
            onOpenSettings: () {},
            onStop: () =>
                modes.update(TranslationModeEnum.off, isClassical: true)),
      ])),
    ));
    modes.update(TranslationModeEnum.bilingual, isClassical: true);
    await tester.pumpAndSettle();
    expect(modes.language.value, TranslationModeEnum.off);
    expect(find.byType(Badge), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reader-translation-button')));
    await tester.pumpAndSettle();
    expect(languageOpened, 1);
    expect(modes.classical.value, TranslationModeEnum.bilingual);
    expect(find.text('停止翻译'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('reader-classical-translation-button')));
    await tester.pumpAndSettle();
    await tester.tap(find
        .byKey(const ValueKey('reader-toolbar-stop-classical-translation')));
    await tester.pumpAndSettle();
    expect(modes.classical.value, TranslationModeEnum.off);
    expect(find.byType(Badge), findsNothing);
    modes.update(TranslationModeEnum.bilingual, isClassical: false);
    expect(modes.classical.value, TranslationModeEnum.off);
    modes.update(TranslationModeEnum.bilingual, isClassical: true);
    expect(modes.language.value, TranslationModeEnum.off);
    expect(modes.classical.value, TranslationModeEnum.bilingual);
    await tester.pumpWidget(const SizedBox());
  });
}
