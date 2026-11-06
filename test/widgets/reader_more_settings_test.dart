import 'dart:convert';
import 'package:anx_reader/models/reading_info.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/widgets/common/app_scroll_behavior.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:anx_reader/service/ocr/document_text_style.dart';
import 'package:anx_reader/enums/text_alignment.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reader_setting_availability.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/reader_menu_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final readerMenu in [false, true]) {
    for (final section in ['reading', 'style', 'other']) {
      testWidgets('$section groups are reader-only: $readerMenu',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: switch (section) {
                'reading' => ReadingMoreSettings(readerMenu: readerMenu),
                'style' => StyleSettings(readerMenu: readerMenu),
                _ => OtherSettings(readerMenu: readerMenu),
              },
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(ReaderMenuGroup),
            readerMenu ? findsWidgets : findsNothing);
        if (!readerMenu && section != 'other') {
          expect(find.byType(Divider), findsWidgets);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final menu in [false, true]) {
    testWidgets('header/footer typography controls are independent: menu=$menu',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: SingleChildScrollView(
                child: ReadingMoreSettings(readerMenu: menu))),
      ));
      await tester.pumpAndSettle();
      final fontTile = find.ancestor(
          of: find.text('字体').first, matching: find.byType(ListTile));
      await tester.ensureVisible(fontTile);
      await tester.tap(fontTile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('系统字体').last);
      await tester.pumpAndSettle();
      expect(Prefs().readingInfo.header.font, 'system');
      expect(Prefs().readingInfo.footer.font, '');
      final colorTile = find.byKey(const ValueKey('reading-info-color-页眉设置'));
      await tester.ensureVisible(colorTile);
      await tester.tap(colorTile);
      await tester.pumpAndSettle();
      tester
          .widget<ColorPicker>(find.byType(ColorPicker))
          .onColorChanged(const Color(0xff123456));
      await tester.tap(find
          .text(L10n.of(tester.element(find.byType(ColorPicker))).commonOk)
          .last);
      await tester.pumpAndSettle();
      expect(Prefs().readingInfo.header.color, '#123456');
      expect(Prefs().readingInfo.footer.color, '');
      final opacityRow = find
          .ancestor(of: find.text('不透明度 (%)').last, matching: find.byType(Row))
          .first;
      tester
          .widget<Slider>(
              find.descendant(of: opacityRow, matching: find.byType(Slider)))
          .onChanged!(80);
      await tester.pumpAndSettle();
      expect(Prefs().readingInfo.footer.opacity, .8);
      expect(Prefs().readingInfo.header.opacity, isNull);
      final saved = ReadingInfoModel.fromJson(
          jsonDecode(jsonEncode(Prefs().readingInfo)));
      expect(saved, Prefs().readingInfo);
      final marginRow =
          find.ancestor(of: find.text('上边距'), matching: find.byType(Row)).first;
      tester
          .widget<Slider>(
              find.descendant(of: marginRow, matching: find.byType(Slider)))
          .onChanged!(24);
      await tester.pumpAndSettle();
      final reset = find.byKey(const ValueKey('reading-info-reset-页眉设置'));
      await tester.ensureVisible(reset);
      await tester.tap(reset);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-color-reset')));
      await tester.pumpAndSettle();
      expect(Prefs().readingInfo.header.color, '#123456');
      await tester.tap(reset);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-color-reset')));
      await tester.pumpAndSettle();
      expect(Prefs().readingInfo.header.font, '');
      expect(Prefs().readingInfo.header.color, '');
      expect(Prefs().readingInfo.header.opacity, isNull);
      expect(Prefs().readingInfo.header.fontSize, 10);
      expect(Prefs().readingInfo.header.verticalMargin, 24);
      expect(Prefs().readingInfo.footer, saved.footer);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('header and footer margins name their actual edges',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(
          body: ReaderMoreSettings(settings: ReadingSettings.theme)),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ReadingMoreSettings>(find.byType(ReadingMoreSettings))
            .readerMenu,
        isTrue);
    expect(find.text('上边距'), findsOneWidget);
    expect(find.text('下边距'), findsOneWidget);
    expect(find.text('边距'), findsNothing);
    for (final label in ['上边距', '下边距']) {
      final row =
          find.ancestor(of: find.text(label), matching: find.byType(Row)).first;
      tester
          .widget<Slider>(
              find.descendant(of: row, matching: find.byType(Slider)))
          .onChanged!(label == '上边距' ? 24 : 36);
      await tester.pumpAndSettle();
    }
    expect(Prefs().readingInfo.header.verticalMargin, 24);
    expect(Prefs().readingInfo.footer.verticalMargin, 36);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets(
        'OCR gear enables CSS while retaining unsupported-control guards at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = <DocumentTextStyle>[];
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: ReaderMoreSettings(
          settings: ReadingSettings.style,
          documentStyle: const DocumentTextStyle(),
          saveDocumentStyle: (s) async => saved.add(s),
        )),
      ));
      await tester.pumpAndSettle();
      final useBookStyles = Prefs().useBookStyles;
      await tester.tap(find.byType(SwitchListTile), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(Prefs().useBookStyles, useBookStyles);
      final sliders = find.descendant(
          of: find.byType(StyleSettings), matching: find.byType(Slider));
      tester.widget<Slider>(sliders.at(1)).onChanged!(20);
      await tester.pump();
      tester.widget<Slider>(sliders.at(1)).onChangeEnd!(20);
      await tester.pumpAndSettle();
      expect(saved.last.margin, size.width * .2);
      final dropdown = find.byType(DropdownMenu<TextAlignmentEnum>);
      tester
          .widget<DropdownMenu<TextAlignmentEnum>>(dropdown)
          .onSelected!(TextAlignmentEnum.center);
      await tester.pumpAndSettle();
      expect(saved.last.alignment, TextAlign.center);
      expect(saved.last.margin, size.width * .2);
      await tester.tap(find.text('CSS'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomCSSEditor), findsOneWidget);
      expect(
          find.ancestor(
              of: find.byType(CustomCSSEditor),
              matching: find.byType(ReaderSettingAvailability)),
          findsNothing);
      expect(find.byKey(const ValueKey('apply-css-13')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'OCR gear recovers from failed save without changing ebook settings',
      (tester) async {
    var attempts = 0;
    DocumentTextStyle? saved;
    final before = Prefs().bookStyle.toMap();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
          body: ReaderMoreSettings(
        settings: ReadingSettings.style,
        documentStyle: const DocumentTextStyle(),
        saveDocumentStyle: (s) async {
          if (++attempts == 1) throw StateError('save failed');
          saved = s;
        },
      )),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Tab).at(1));
    await tester.pumpAndSettle();
    final sliders = find.descendant(
        of: find.byType(StyleSettings), matching: find.byType(Slider));
    for (var i = 0; i < 2; i++) {
      tester.widget<Slider>(sliders.at(2)).onChanged!(80);
      await tester.pump();
      tester.widget<Slider>(sliders.at(2)).onChangeEnd!(80);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(sliders.at(2)).value, i == 0 ? 16 : 80);
    }
    expect(saved!.padding.top, 80);
    expect(saved!.padding.bottom, 16);
    expect(Prefs().bookStyle.toMap(), before);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(390, 844),
    const Size(1200, 900),
    const Size(844, 390)
  ]) {
    testWidgets(
        'reader settings match query and CSS remains accessible at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        scrollBehavior: const AppScrollBehavior(),
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
            body: Builder(
                builder: (context) => Column(children: [
                      TextButton(
                          onPressed: () => showReaderPopup(context,
                              builder: (_) => const Text('query body')),
                          child: const Text('query')),
                      TextButton(
                          onPressed: () => showReaderPopup(context,
                              enableDrag: false,
                              builder: (_) => const ReaderMoreSettings(
                                  settings: ReadingSettings.style)),
                          child: const Text('settings')),
                    ]))),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('query'));
      await tester.pumpAndSettle();
      final querySize =
          tester.getSize(find.byKey(const ValueKey('reader-popup-body')));
      Navigator.of(tester.element(find.text('query body'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(const ValueKey('reader-popup-body'))),
          querySize);
      expect(find.byType(CustomCSSEditor), findsNothing);
      expect(tester.widgetList<Tab>(find.byType(Tab)).map((t) => t.text),
          ['阅读', '样式', 'CSS', '其他']);
      await tester.tap(find.text('CSS'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomCSSEditor), findsOneWidget);
      expect(find.byKey(const ValueKey('apply-css-8')), findsOneWidget);
      await tester.tap(find.text('其他'));
      await tester.pumpAndSettle();
      expect(find.byType(OtherSettings), findsOneWidget);
      expect(find.text('划词工具栏'), findsNothing);
      expect(find.text('自动总结前文内容'), findsNothing);
      expect(find.text('键盘快捷键翻页'), findsNothing);
      expect(find.text('自定义按键'), findsNothing);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderMoreSettings), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
