import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/translation_toolbar_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: L10n.localizationsDelegates,
        home: Scaffold(body: child),
      );
  const buttonKey = ValueKey('reader-translation-button');
  const stopKey = ValueKey('reader-toolbar-stop-translation');

  testWidgets('inactive translation opens settings directly', (tester) async {
    var opens = 0;
    var stops = 0;
    await tester.pumpWidget(app(TranslationToolbarAction(
      onOpenSettings: () => opens++,
      onStop: () => stops++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(buttonKey));
    expect(opens, 1);
    expect(stops, 0);
    expect(find.byKey(stopKey), findsNothing);
  });

  for (final active in [
    TranslationModeEnum.bilingual,
    TranslationModeEnum.translationOnly,
  ]) {
    testWidgets('$active stop lives in menu; hidden toolbar never covers text',
        (tester) async {
      final mode = ValueNotifier(TranslationModeEnum.off);
      addTearDown(mode.dispose);
      var showToolbar = false;
      var textTaps = 0;
      var stops = 0;
      late StateSetter update;
      await tester.pumpWidget(app(StatefulBuilder(builder: (context, setState) {
        update = setState;
        return Stack(fit: StackFit.expand, children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('reader-text-surface'),
              behavior: HitTestBehavior.opaque,
              onTap: () => textTaps++,
              child: const Text('正文保持原有大小'),
            ),
          ),
          Offstage(
            offstage: !showToolbar,
            child: Align(
              alignment: Alignment.topRight,
              child: TranslationToolbarAction(
                mode: mode,
                onOpenSettings: () {},
                onStop: () {
                  stops++;
                  mode.value = TranslationModeEnum.off;
                },
              ),
            ),
          ),
        ]);
      })));
      await tester.pumpAndSettle();
      final rect =
          tester.getRect(find.byKey(const ValueKey('reader-text-surface')));
      expect(rect.height, greaterThan(100));
      mode.value = active;
      await tester.pumpAndSettle();
      expect(find.byKey(buttonKey), findsNothing);
      expect(find.text('停止翻译'), findsNothing);
      await tester.tapAt(rect.bottomRight - const Offset(40, 70));
      expect(textTaps, 1);
      update(() => showToolbar = true);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(const ValueKey('reader-text-surface'))),
          rect);
      expect(find.byKey(stopKey), findsNothing);
      await tester.tap(find.byKey(buttonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(stopKey));
      await tester.pumpAndSettle();
      expect(stops, 1);
      expect(mode.value, TranslationModeEnum.off);
      expect(find.byKey(stopKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('active translation can still open settings without stopping',
      (tester) async {
    final mode = ValueNotifier(TranslationModeEnum.bilingual);
    addTearDown(mode.dispose);
    var opens = 0;
    var stops = 0;
    await tester.pumpWidget(app(TranslationToolbarAction(
      mode: mode,
      onOpenSettings: () => opens++,
      onStop: () => stops++,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译设置'));
    await tester.pumpAndSettle();
    expect(opens, 1);
    expect(stops, 0);
    expect(mode.value, TranslationModeEnum.bilingual);
  });
}
