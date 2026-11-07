import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/theme_preset.dart';
import 'package:anx_reader/page/settings_page/theme_colors.dart';
import 'package:anx_reader/widgets/settings/theme_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('zh'));
    await L10n.delegate.load(const Locale('en'));
  });

  Widget app(String locale) => MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const ThemeColorsPage(),
      );

  testWidgets(
      'appearance retains the schedule and custom hours alongside presets',
      (tester) async {
    await Prefs().saveThemeSchedule(start: 1260, end: 390);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(body: AppearanceSetting()),
    ));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const ValueKey('scheduled-theme-enabled'));
    final control = find.descendant(of: toggle, matching: find.byType(Switch));
    expect(tester.widget<Switch>(control).value, isFalse);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(Prefs().scheduledTheme, isTrue);
    final hours = find.byKey(const ValueKey('scheduled-theme-hours'));
    expect(hours, findsOneWidget);
    await tester.tap(hours);
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(Prefs().nightStartMinute, 1260);
    expect(Prefs().nightEndMinute, 390);
    await Prefs().selectThemePreset(builtInThemePresetById('ink')!);
    expect(Prefs().scheduledTheme, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the colour style header explains the six canvas colours',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();

    final help = find.byKey(const ValueKey('theme-canvas-help'));
    expect(help, findsOneWidget);
    await tester.ensureVisible(help);
    await tester.pumpAndSettle();
    await tester.tap(
        find.descendant(of: help, matching: find.byIcon(Icons.help_outline)));
    await tester.pumpAndSettle();

    for (final label in [
      '背景',
      '卡片与导航栏',
      '正文文字',
      '次要文字',
      '选中项底色',
      '选中项文字',
    ]) {
      expect(find.textContaining(label, findRichText: true), findsWidgets,
          reason: label);
    }
    expect(
        find.textContaining('书页跟随背景和正文颜色', findRichText: true), findsOneWidget);

    // Tapping outside closes the popover and changes nothing.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('书页跟随背景和正文颜色', findRichText: true), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fine-tune dialog offers the same colour legend',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('theme-preset-menu-ink'));
    await tester.scrollUntilVisible(menu, 300);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('微调颜色（当前模式）').last);
    await tester.pumpAndSettle();

    final help = find.byKey(const ValueKey('theme-canvas-help-dialog'));
    expect(help, findsOneWidget);
    // Keep the original short inline hints as requested.
    expect(find.text('页面与书页的底色'), findsOneWidget);
    expect(find.text('选中项上的文字与图标'), findsOneWidget);
    await tester.tap(
        find.descendant(of: help, matching: find.byIcon(Icons.help_outline)));
    await tester.pumpAndSettle();
    expect(find.textContaining('卡片与导航栏：', findRichText: true), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['zh', 'en']) {
    testWidgets('$locale: every preset is listed and the active one is checked',
        (tester) async {
      tester.view.physicalSize = const Size(420, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app(locale));
      await tester.pumpAndSettle();
      for (final preset in builtInThemePresets) {
        expect(
            find.byKey(ValueKey('theme-preset-${preset.id}')), findsOneWidget,
            reason: preset.id);
      }
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('tapping a preset applies it and moves the check mark',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();
    final ocean = builtInThemePresetById('ocean')!;
    await tester
        .ensureVisible(find.byKey(const ValueKey('theme-preset-ocean')));
    await tester.tap(find.byKey(const ValueKey('theme-preset-ocean')));
    await tester.pumpAndSettle();
    expect(Prefs().themeColor.toARGB32(), ocean.colorValue);
    expect(Prefs().themePresetId, 'ocean');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('the light/dark mode switch lives on the theme page',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();
    expect(find.byType(ChangeThemeMode), findsOneWidget);
    await tester.tap(find.textContaining('深色').first);
    await tester.pumpAndSettle();
    expect(Prefs().themeMode, ThemeMode.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E-Ink disables the mode switch on the theme page',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Prefs().eInkMode = true;
    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();
    final segmented = tester
        .widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>));
    expect(segmented.onSelectionChanged, isNull);
    expect(segmented.selected, {'light'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('the reader switch copies the canvas into the read theme',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await Prefs().selectThemePreset(builtInThemePresetById('ink')!);
    await Prefs().saveThemeModeToPrefs('light');
    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('theme-applies-to-reader'));
    await tester.ensureVisible(toggle);
    expect(Prefs().themeAppliesToReader, isFalse);
    await tester
        .tap(find.descendant(of: toggle, matching: find.byType(Switch)));
    await tester.pumpAndSettle();

    expect(Prefs().themeAppliesToReader, isTrue);
    expect(Prefs().readTheme.backgroundColor, 'FFF3E9D6');
    expect(Prefs().readTheme.textColor, 'FF332A1E');

    // A new preset now also repaints the reading page.
    await tester.tap(find.byKey(const ValueKey('theme-preset-pink')));
    await tester.pumpAndSettle();
    expect(Prefs().readTheme.backgroundColor, 'FFFFE4EC');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom theme can be created and deleted', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app('zh'));
    await tester.pumpAndSettle();

    final newTile = find.byKey(const ValueKey('theme-preset-new'));
    await tester.ensureVisible(newTile);
    await tester.tap(newTile);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('theme-preset-name')), '我的主题');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-preset-save')));
    await tester.pumpAndSettle();

    final custom = Prefs().customThemePresets;
    expect(custom, hasLength(1));
    expect(custom.single.name, '我的主题');
    expect(Prefs().themePresetId, custom.single.id);
    expect(find.byKey(ValueKey('theme-preset-${custom.single.id}')),
        findsOneWidget);

    // Deleting restores the default colour because the deleted theme was active.
    await tester
        .tap(find.byKey(ValueKey('theme-preset-menu-${custom.single.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除主题').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(Prefs().customThemePresets, isEmpty);
    expect(Prefs().themePresetId, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
