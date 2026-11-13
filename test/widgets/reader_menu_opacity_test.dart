import 'package:modu_reader/widgets/reading_page/document_comparison_view.dart';
import 'package:modu_reader/widgets/reading_page/document_reader_surface.dart';
import 'dart:ui' as ui;
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/enums/ai_chat_display_mode.dart';
import 'package:modu_reader/widgets/reading_page/reader_menu_appearance.dart';
import 'package:modu_reader/widgets/reading_page/reader_menu_group.dart';
import 'package:modu_reader/widgets/reading_page/document_panel_widgets.dart';
import 'package:modu_reader/widgets/reading_page/reader_popup.dart';
import 'package:modu_reader/widgets/settings/reader_menu_opacity_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('reader nested menus stay clear at every opacity',
      (tester) async {
    for (final opacity in [100, 50]) {
      Prefs().readerMenuOpacityPercent = opacity;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        final outside = Theme.of(context);
        final reader = ReaderMenuAppearance.theme(context);
        expect(reader.bottomSheetTheme.modalBarrierColor, Colors.transparent);
        expect(reader.dialogTheme.barrierColor, Colors.transparent);
        expect(outside.bottomSheetTheme.modalBarrierColor, isNull);
        expect(outside.dialogTheme.barrierColor, isNull);
        return const SizedBox();
      })));
    }
  });

  test('opacity is bounded, persists locally and never imports or exports',
      () async {
    final prefs = Prefs();
    expect(prefs.readerMenuOpacityPercent, 100);
    for (final percent in [20, 63, 100]) {
      prefs.readerMenuOpacityPercent = percent;
      await prefs.initPrefs();
      expect(prefs.readerMenuOpacityPercent, percent);
    }
    prefs.readerMenuOpacityPercent = -1;
    expect(prefs.readerMenuOpacityPercent, 20);
    prefs.readerMenuOpacityPercent = 200;
    expect(prefs.readerMenuOpacityPercent, 100);
    await prefs.prefs.setString('readerMenuOpacityPercent', 'invalid');
    expect(prefs.readerMenuOpacityPercent, 100);
    prefs.readerMenuOpacityPercent = 63;
    expect(await prefs.buildPrefsBackupMap(),
        isNot(contains('readerMenuOpacityPercent')));
    for (final scope in ['all', 'reading']) {
      final data = await GlobalSettingsTransfer.decode(
          await GlobalSettingsTransfer.export(prefs, scope: scope));
      expect(data, isNot(contains('readerMenuOpacityPercent')));
      await GlobalSettingsTransfer.apply(prefs, data);
      expect(prefs.readerMenuOpacityPercent, 63);
    }
    await prefs.applyPrefsBackupMap({
      'readerMenuOpacityPercent': {'type': 'int', 'value': 100}
    });
    expect(prefs.readerMenuOpacityPercent, 63);
  });

  testWidgets(
      'slider saves and e-ink disables it without losing the saved value',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ReaderMenuOpacityTile())));
    var slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 20);
    expect(slider.max, 100);
    expect(slider.divisions, 80);
    slider.onChanged!(43);
    slider.onChangeEnd!(43);
    await tester.pump();
    expect(find.text('43%'), findsOneWidget);
    Prefs().eInkMode = true;
    await tester.pump();
    slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    expect(slider.onChangeEnd, isNull);
    expect(slider.value, 100);
    expect(Prefs().readerMenuOpacityPercent, 43);
    Prefs().eInkMode = false;
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 43);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PDF and reflow comparison menus share opacity without fading the book',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Prefs().readerMenuOpacityPercent = 37;
    Widget pane(String title) => DocumentReaderSurface(
        header: Text(title),
        body: Text('$title body'),
        navigation: const SizedBox(height: 48),
        style: const Text('style'),
        tools: DocumentPanelTheme(child: Text('$title tools')));
    await tester.pumpWidget(MaterialApp(
        home: DocumentComparisonView(
      original: pane('PDF'),
      reflow: pane('Reflow'),
      compare: true,
      onOriginalInteraction: () {},
      onReflowInteraction: () {},
    )));
    for (final button in find
        .byKey(const ValueKey('document-tools-menu'))
        .evaluate()
        .toList()) {
      await tester.tap(find.byWidget(button.widget));
      await tester.pumpAndSettle();
    }
    expect(find.byType(BottomSheet), findsNWidgets(2));
    void check(double opacity) {
      for (final element in find.byType(BottomSheet).evaluate()) {
        final material = tester.widget<Material>(find
            .descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(Material))
            .first);
        expect(material.color!.a, closeTo(opacity, .005));
      }
      for (final element in find
          .byKey(const ValueKey('document-reader-background'))
          .evaluate()) {
        expect((element.widget as Material).color!.a, 1);
      }
    }

    check(.37);
    Prefs().eInkMode = true;
    await tester.pumpAndSettle();
    check(1);
    Prefs().eInkMode = false;
    await tester.pumpAndSettle();
    check(.37);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [
    'modal',
    'adjustable',
    'inline',
    'dialog',
    'non-reader'
  ]) {
    for (final eink in [false, true]) {
      testWidgets(
          '$kind paints one background layer and preserves controls, eink=$eink',
          (tester) async {
        Prefs().readerMenuOpacityPercent = 20;
        Prefs().eInkMode = eink;
        Prefs().aiChatDisplayMode = AiChatDisplayMode.popup;
        Prefs().adjustableReaderPopups = kind == 'adjustable';
        const capture = ValueKey('capture');
        const sample = ValueKey('sample');
        var taps = 0;
        late BuildContext root;
        Widget content() => DocumentPanelTheme(
                child: ReaderMenuGroup(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(key: sample, width: 100, height: 60),
              TextButton(onPressed: () => taps++, child: const Text('Action')),
              Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              const AlertDialog(title: Text('Child dialog'))),
                      child: const Text('Child'))),
            ])));
        final theme = ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)
              .copyWith(surface: Colors.white),
          cardTheme: const CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0),
          bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0),
          dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0),
        );
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: MaterialApp(
                theme: theme,
                home: Scaffold(
                    backgroundColor: const Color(0xff0000ff),
                    body: Builder(builder: (context) {
                      root = context;
                      if (kind == 'inline') {
                        return Align(
                            alignment: Alignment.bottomCenter,
                            child: ReaderMenuAppearance.wrap(
                                context,
                                BottomSheet(
                                    onClosing: () {},
                                    builder: (_) => content())));
                      }
                      return TextButton(
                          onPressed: () {
                            if (kind == 'dialog') {
                              showReaderDialog<void>(
                                  context: context,
                                  builder: (_) => Dialog(child: content()));
                            } else {
                              showReaderPopup(context,
                                  allowWindowAdjustment: kind == 'adjustable',
                                  readerAppearance: kind != 'non-reader',
                                  builder: (_) => content());
                            }
                          },
                          child: const Text('Open'));
                    })))));
        if (kind != 'inline') await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final expected = eink || kind == 'non-reader' ? 255 : 51;
        final location = tester.getCenter(find.byKey(sample));
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(capture));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
          final red = bytes.getUint8(
              (location.dy.floor() * image.width + location.dx.floor()) * 4);
          expect(red, closeTo(expected, 2),
              reason:
                  'An opaque child or stacked alpha must not hide the reading page');
          image.dispose();
        });
        expect(Theme.of(root).cardTheme.color, Colors.white,
            reason: 'The outer application theme is untouched');
        await tester.tap(find.text('Action'));
        expect(taps, 1);
        await tester.tap(find.text('Child'));
        await tester.pumpAndSettle();
        final dialogContext = tester.element(find.text('Child dialog'));
        expect(Theme.of(dialogContext).dialogTheme.backgroundColor!.a,
            closeTo(expected / 255, .005));
        expect(Theme.of(dialogContext).colorScheme.onSurface,
            theme.colorScheme.onSurface);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
