import 'dart:convert';
import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/widgets/settings/translation_preview_text.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/translation_text_style.dart';
import 'package:modu_reader/service/config_transfer/settings_modules.dart';
import 'package:modu_reader/service/config_transfer/settings_value_validation.dart';
import 'package:modu_reader/widgets/settings/translation_text_style_settings.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  test(
      'appearance is portable and validates fonts/numbers without changing source',
      () {
    final style = TranslationTextStyle.decode(
        '{"font":"测试 字体.ttf","size":28,"bold":true,"italic":true,"color":"#287D75"}');
    expect(
        TranslationTextStyle.decode(style.encode()).textStyle, style.textStyle);
    expect(style.textStyle.fontWeight, FontWeight.bold);
    expect(style.textStyle.color, const Color(0xFF287D75));
    expect(style.webStyle(1234)['color'], '#287D75');
    expect(TranslationTextStyle.decode('{"color":"red;opacity:0"}').color, '');
    expect(style.webStyle(1234)['fontUrl'], contains('127.0.0.1:1234/fonts/'));
    expect(
        TranslationTextStyle.decode('{"font":"../a.ttf","size":999}').font, '');
    expect(TranslationTextStyle.decode('{"size":999}').size, 48);
    expect(TranslationTextStyle.decode('broken').size, 0);
    for (final key in [
      'classicalTranslationTextStyle',
      'languageTranslationTextStyle'
    ]) {
      expect(settingsModuleForKey(key), 'translation');
      validateSettingsValue(key, style.encode());
      for (final size in [8.0, 16.0, 17.6, 48.0]) {
        final scaled = TranslationTextStyle(size: size);
        validateSettingsValue(key, scaled.encode());
        expect(TranslationTextStyle.decode(scaled.encode()).size, size);
        expect(scaled.webStyle(1234)['size'], size);
        expect(scaled.textStyle.fontSize, size);
      }
      expect(
          () => validateSettingsValue(
              key, const TranslationTextStyle(size: 7).encode()),
          throwsFormatException);
      expect(() => validateSettingsValue(key, '{"font":"../a.ttf"}'),
          throwsFormatException);
    }
  });
  test('translation colours persist independently of the existing body palette',
      () async {
    final bodyPalette = Prefs().readTheme.toJson();
    Prefs().languageTranslationTextStyle =
        const TranslationTextStyle(color: '#287D75').encode();
    Prefs().classicalTranslationTextStyle =
        const TranslationTextStyle(color: '#287FA3').encode();
    await Prefs().initPrefs();
    expect(Prefs().readTheme.toJson(), bodyPalette);
    final backup = jsonDecode(await GlobalSettingsTransfer.export(Prefs()));
    final values = backup['preferences'] as Map;
    for (final key in [
      'languageTranslationTextStyle',
      'classicalTranslationTextStyle'
    ]) {
      expect(values[key]['value'], Prefs().prefs.get(key));
    }
    final language = Prefs().languageTranslationTextStyle;
    Prefs().classicalTranslationTextStyle =
        TranslationTextStyle.decode(Prefs().classicalTranslationTextStyle)
            .withValue('color', '')
            .encode();
    expect(Prefs().readTheme.toJson(), bodyPalette);
    expect(Prefs().languageTranslationTextStyle, language);
  });
  testWidgets('preview follows target language independently of UI language',
      (tester) async {
    Prefs().fullTextTranslateTo = LangListEnum.japanese;
    await tester.pumpWidget(const MaterialApp(
        locale: Locale('en'),
        home: Scaffold(
            body: SingleChildScrollView(
                child: TranslationTextStyleSettings(classical: false)))));
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('language-style-preview'));
    expect(tester.widget<Text>(preview).data, contains('学び'));
    Prefs().fullTextTranslateTo = LangListEnum.english;
    await tester.pump();
    expect(
        tester.widget<Text>(preview).data, startsWith('Is it not a pleasure'));
    Prefs().fullTextTranslateTo = LangListEnum.simplifiedChinese;
    await tester.pump();
    expect(tester.widget<Text>(preview).data, contains('学习并时常温习'));
    Prefs().fullTextTranslateTo = LangListEnum.arabic;
    await tester.pump();
    expect(tester.widget<Text>(preview).textDirection, TextDirection.rtl);
    expect(tester.widget<Text>(preview).data, contains('تتعلم'));
    expect(Prefs().prefs.get('languageTranslationTextStyle'), isNull);
    for (final language in LangListEnum.values) {
      expect(translationPreviewText(language), isNotEmpty);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('size slider changes preview live and can follow original again',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const other = '{"size":30,"bold":true}';
    Prefs().classicalTranslationTextStyle = other;
    Prefs().languageTranslationTextStyle =
        const TranslationTextStyle(size: 18, italic: true, color: '#287D75')
            .encode();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: TranslationTextStyleSettings(classical: false)))));
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('language-style-size'));
    final control = tester.widget<Slider>(slider);
    expect(control.min, .5);
    expect(control.max, 3);
    expect(control.divisions, 25);
    await tester.ensureVisible(slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump();
    final style =
        TranslationTextStyle.decode(Prefs().languageTranslationTextStyle);
    expect(style.size, greaterThan(18));
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('language-style-preview')))
            .style!
            .fontSize,
        style.size);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-style-size-reset')));
    await tester.pumpAndSettle();
    final reset =
        TranslationTextStyle.decode(Prefs().languageTranslationTextStyle);
    expect(reset.size, 0);
    expect(reset.italic, true);
    expect(reset.color, '#287D75');
    expect(Prefs().classicalTranslationTextStyle, other);
    expect(Prefs().prefs.get('readStyle'), isNull);
    expect(tester.takeException(), isNull);
  });

  for (final classical in [true, false]) {
    final prefix = classical ? 'classical' : 'language';
    testWidgets(
        '$prefix appearance persists independently and previews only output',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const otherStyle =
          '{"font":"serif","size":36,"bold":false,"italic":false}';
      if (classical) {
        Prefs().languageTranslationTextStyle = otherStyle;
      } else {
        Prefs().classicalTranslationTextStyle = otherStyle;
      }
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: TranslationTextStyleSettings(classical: classical)))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('$prefix-style-font')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monospace'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('$prefix-style-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('text-color-preset-#287D75')));
      await tester.tap(find.byKey(const ValueKey('save-font-color')));
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(find.byKey(ValueKey('$prefix-style-size')))
          .onChanged!(1.1);
      await tester.pumpAndSettle();
      for (final name in ['bold', 'italic']) {
        final row = find.byKey(ValueKey('$prefix-style-$name'));
        await tester.ensureVisible(row);
        await tester
            .tap(find.descendant(of: row, matching: find.byType(Switch)));
        await tester.pumpAndSettle();
      }
      final style = TranslationTextStyle.decode(classical
          ? Prefs().classicalTranslationTextStyle
          : Prefs().languageTranslationTextStyle);
      expect(style.font, 'monospace');
      expect(style.color, '#287D75');
      expect(style.size, closeTo(17.6, .0001));
      expect(style.bold, true);
      expect(style.italic, true);
      expect(
          Prefs().prefs.getKeys(), contains('${prefix}TranslationTextStyle'));
      expect(
          classical
              ? Prefs().languageTranslationTextStyle
              : Prefs().classicalTranslationTextStyle,
          otherStyle);
      expect(Prefs().prefs.get('readStyle'), isNull);
      expect(
          tester
              .widget<Text>(find.byKey(ValueKey('$prefix-style-preview')))
              .style,
          style.textStyle);
      final row = find.byKey(ValueKey('$prefix-style-color'));
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reset-font-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cancel-color-reset')));
      await tester.pumpAndSettle();
      expect(
          TranslationTextStyle.decode(
                  Prefs().prefs.getString('${prefix}TranslationTextStyle')!)
              .color,
          '#287D75');
      await tester.tap(find.byKey(const ValueKey('reset-font-color')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-color-reset')));
      await tester.pumpAndSettle();
      final restored = TranslationTextStyle.decode(
          Prefs().prefs.getString('${prefix}TranslationTextStyle')!);
      expect(restored.color, '');
      expect(restored.font, style.font);
      expect(restored.size, style.size);
      expect(restored.bold, style.bold);
      expect(restored.italic, style.italic);
      expect(tester.takeException(), isNull);
    });
  }
}
