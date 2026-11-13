import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/ai_chat_display_mode.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/widgets/reading_page/reader_popup.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:modu_reader/widgets/reading_page/reader_settings_scroll_view.dart';
import 'package:modu_reader/widgets/settings/reader_popup_height_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget child) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('height defaults to 80, clamps and persists only on this device',
      () async {
    final prefs = Prefs();
    expect(prefs.readerPopupMaxHeightPercent, 80);
    for (final percent in [40, 61, 80]) {
      prefs.readerPopupMaxHeightPercent = percent;
      await prefs.initPrefs();
      expect(prefs.readerPopupMaxHeightPercent, percent);
    }
    prefs.readerPopupMaxHeightPercent = 10;
    expect(prefs.readerPopupMaxHeightPercent, 40);
    prefs.readerPopupMaxHeightPercent = 95;
    expect(prefs.readerPopupMaxHeightPercent, 80);
    await prefs.prefs.setString('readerPopupMaxHeightPercent', 'invalid');
    expect(prefs.readerPopupMaxHeightPercent, 80);
    prefs.readerPopupMaxHeightPercent = 53;
    expect(await prefs.buildPrefsBackupMap(),
        isNot(contains('readerPopupMaxHeightPercent')));
    for (final scope in ['all', 'reading']) {
      final data = await GlobalSettingsTransfer.decode(
          await GlobalSettingsTransfer.export(prefs, scope: scope));
      expect(data, isNot(contains('readerPopupMaxHeightPercent')));
      await GlobalSettingsTransfer.apply(prefs, data);
      expect(prefs.readerPopupMaxHeightPercent, 53);
    }
    await prefs.applyPrefsBackupMap({
      'readerPopupMaxHeightPercent': {'type': 'int', 'value': 80}
    });
    expect(prefs.readerPopupMaxHeightPercent, 53);
  });

  testWidgets('height slider displays and saves a percentage', (tester) async {
    await tester.pumpWidget(app(const ReaderPopupHeightTile()));
    await tester.pumpAndSettle();
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 40);
    expect(slider.max, 80);
    expect(slider.divisions, 40);
    slider.onChanged!(57);
    await tester.pump();
    expect(find.text('57%'), findsOneWidget);
    slider.onChangeEnd!(57);
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpWidget(app(const ReaderPopupHeightTile()));
    expect(find.text('57%'), findsOneWidget);
  });

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1200, 800)
  ]) {
    for (final adjustable in [false, true]) {
      testWidgets(
          '40% cap keeps last item reachable at $size adjustable=$adjustable',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Prefs().readerPopupMaxHeightPercent = 40;
        Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
        Prefs().adjustableReaderPopups = adjustable;
        await tester.pumpWidget(app(Builder(
            builder: (context) => TextButton(
                  onPressed: () => showReaderPopup(context,
                      allowWindowAdjustment: true,
                      builder: (_) => ReaderSettingsScrollView(
                              child: Column(children: [
                            const SizedBox(height: 1000),
                            TextButton(
                                onPressed: () {},
                                child: const Text('last item')),
                          ]))),
                  child: const Text('open'),
                ))));
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final panel = find.byKey(ValueKey(adjustable
            ? 'adjustable-reader-popup-frame'
            : 'reader-popup-body'));
        expect(tester.getSize(panel).height, closeTo(size.height * .4, .01));
        if (adjustable) {
          final handle = find.byKey(const ValueKey('reader-popup-top-right'));
          await tester.drag(handle, const Offset(0, -500));
          await tester.pumpAndSettle();
          expect(tester.getSize(panel).height,
              lessThanOrEqualTo(size.height * .4));
        }
        await tester.ensureVisible(find.text('last item'));
        await tester.pumpAndSettle();
        expect(find.text('last item').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'book style explanation is hidden until help is tapped, without toggling',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const ReaderSettingsScrollView(
        child: StyleSettings(readerMenu: true))));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(StyleSettings));
    final description = L10n.of(context).useBookStylesDescription;
    expect(find.text(description), findsNothing);
    final before = Prefs().useBookStyles;
    await tester.tap(find.byIcon(Icons.help_outline).first);
    await tester.pumpAndSettle();
    expect(find.text(description), findsOneWidget);
    expect(Prefs().useBookStyles, before);
    // Help text lives in an anchored popup menu; dismiss it with an outside tap.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text(description), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(Prefs().useBookStyles, !before);
    expect(tester.takeException(), isNull);
  });
}
