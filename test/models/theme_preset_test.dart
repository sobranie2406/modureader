import 'dart:convert';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/theme_preset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('built-in presets have unique ids and no duplicate colours', () {
    expect(builtInThemePresets, isNotEmpty);
    expect(builtInThemePresets.map((p) => p.id).toSet().length,
        builtInThemePresets.length);
    expect(builtInThemePresets.map((p) => p.colorValue).toSet().length,
        builtInThemePresets.length);
    expect(builtInThemePresets.every((p) => p.builtIn), isTrue);
    expect(builtInThemePresets.every((p) => p.name.trim().isNotEmpty), isTrue);
  });

  test('light canvases are tinted and distinct so switching is visible', () {
    final ids = [
      'day',
      'dusk',
      'ink',
      'purple',
      'green',
      'ocean',
      'sunset',
      'pink'
    ];
    final backgrounds = <int>{};
    for (final id in ids) {
      final canvas = builtInThemePresetById(id)!.canvasFor(Brightness.light);
      final hsl = HSLColor.fromColor(canvas.background);
      expect(hsl.saturation, greaterThan(0.25), reason: id);
      expect(canvas.surface, isNot(canvas.background), reason: id);
      backgrounds.add(canvas.background.toARGB32());
    }
    expect(backgrounds.length, ids.length);
  });

  test('dark scenes keep an explicit dark canvas', () {
    for (final id in ['night', 'dusk', 'ink', 'purple']) {
      final preset = builtInThemePresetById(id)!;
      final canvas = preset.canvasFor(Brightness.dark);
      final hsl = HSLColor.fromColor(canvas.background);
      expect(hsl.lightness, lessThan(0.2), reason: id);
      expect(HSLColor.fromColor(canvas.text).lightness, greaterThan(0.7),
          reason: id);
    }
  });

  test('every preset has a distinct background in both brightnesses', () {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final backgrounds = <int>{};
      for (final preset in builtInThemePresets) {
        final canvas = preset.canvasFor(brightness);
        expect(backgrounds.add(canvas.background.toARGB32()), isTrue,
            reason: '${preset.id} ${brightness.name}');
        // The high-contrast preset intentionally uses plain white for both.
        if (preset.id != 'glare') {
          expect(canvas.surface, isNot(canvas.background),
              reason: '${preset.id} ${brightness.name}');
        }
      }
    }
  });

  test('canvas edits survive, fall back, and can be reset', () async {
    final prefs = Prefs();
    final preset = builtInThemePresetById('ocean')!;
    final edited = preset.canvasFor(Brightness.light).copyWith(
          background: const Color(0xFF203040),
          surface: const Color(0xFF304050),
        );
    await prefs.savePresetCanvasOverride(preset, Brightness.light, edited);
    expect(prefs.presetHasOverride(preset.id), isTrue);
    expect(prefs.canvasForPreset(preset, Brightness.light).background,
        const Color(0xFF203040));
    // The other brightness keeps the factory canvas.
    expect(prefs.canvasForPreset(preset, Brightness.dark).background,
        preset.canvasFor(Brightness.dark).background);

    await prefs.resetPresetCanvasOverride(preset.id);
    expect(prefs.presetHasOverride(preset.id), isFalse);
    expect(prefs.canvasForPreset(preset, Brightness.light).background,
        preset.canvasFor(Brightness.light).background);

    await prefs.savePresetCanvasOverride(preset, Brightness.light, edited);
    await prefs.savePresetCanvasOverride(
        builtInThemePresetById('green')!, Brightness.dark, edited);
    await prefs.resetAllPresetOverrides();
    expect(prefs.presetHasOverride(preset.id), isFalse);
    expect(prefs.presetHasOverride('green'), isFalse);
  });

  test(
      'incomplete or invalid canvases fall back and damaged entries can be replaced',
      () async {
    final prefs = Prefs();
    final preset = builtInThemePresets.first;
    final canvas = preset.canvasFor(Brightness.light);
    for (final data in [
      {'background': 0xFFFFFFFF},
      {...canvas.toMap(), 'text': -1},
      {...canvas.toMap(), 'surface': 'white'},
    ]) {
      expect(ThemeCanvas.fromMap(data), isNull);
      await prefs.prefs.setString(
          'themePresetOverrides',
          jsonEncode({
            preset.id: {'light': data}
          }));
      expect(prefs.canvasForPreset(preset, Brightness.light).text, canvas.text);
    }
    await prefs.prefs
        .setString('themePresetOverrides', jsonEncode({preset.id: 'broken'}));
    await prefs.savePresetCanvasOverride(preset, Brightness.light, canvas);
    expect(prefs.canvasForPreset(preset, Brightness.light).background,
        canvas.background);
  });

  test('the linked reader page follows later palette changes', () async {
    final prefs = Prefs();
    final ink = builtInThemePresetById('ink')!;
    await prefs.saveThemeModeToPrefs('light');
    await prefs.selectThemePreset(ink);
    await prefs.setThemeAppliesToReader(true);
    expect(prefs.readTheme.backgroundColor, 'FFF3E9D6');
    expect(prefs.readTheme.textColor, 'FF332A1E');

    // Fine-tuning the active preset repaints the paper at once, and keeps the
    // rest of the canvas override for the interface.
    await prefs.savePresetCanvasOverride(
        ink,
        Brightness.light,
        prefs
            .canvasForPreset(ink, Brightness.light)
            .copyWith(background: const Color(0xFF203040)));
    expect(prefs.readTheme.backgroundColor, 'FF203040');
    expect(prefs.readTheme.textColor, 'FF332A1E');

    // Editing a preset that is not selected must not leak into the reader.
    await prefs.savePresetCanvasOverride(
        builtInThemePresetById('ocean')!,
        Brightness.light,
        prefs
            .canvasForPreset(builtInThemePresetById('ocean')!, Brightness.light)
            .copyWith(background: const Color(0xFF102030)));
    expect(prefs.readTheme.backgroundColor, 'FF203040');

    // Switching the interface to dark must swap the paper, not keep the light
    // canvas that was stored when the switch was turned on.
    await prefs.saveThemeModeToPrefs('dark');
    expect(prefs.readTheme.backgroundColor, 'FF15120D');
    expect(prefs.readTheme.textColor, 'FFEDE4D3');

    // OLED black flattens the paper exactly like the interface.
    prefs.trueDarkMode = true;
    expect(prefs.readTheme.backgroundColor, 'FF000000');

    // Resetting the override restores the factory canvas.
    await prefs.resetPresetCanvasOverride(ink.id);
    expect(prefs.readTheme.backgroundColor, 'FF000000');
    prefs.trueDarkMode = false;
    expect(prefs.readTheme.backgroundColor, 'FF15120D');
  });

  test('an unlinked reader page keeps its own theme', () async {
    final prefs = Prefs();
    await prefs.selectThemePreset(builtInThemePresetById('ink')!);
    await prefs.saveThemeModeToPrefs('light');
    final before = prefs.readTheme.backgroundColor;
    await prefs.setThemeAppliesToReader(false);
    await prefs.saveThemeModeToPrefs('dark');
    expect(prefs.readTheme.backgroundColor, before);
  });

  test('a preset round-trips through JSON', () {
    const preset = ThemePreset(
        id: 'custom_1', name: '夜晚', nameEn: '', colorValue: 0xFF123456);
    expect(ThemePreset.fromMap(preset.toMap()), preset);
    expect(ThemePreset.fromMap({'id': 'x'}), isNull);
    expect(ThemePreset.fromMap('nope'), isNull);
    // A missing colour falls back to the default seed instead of crashing.
    expect(ThemePreset.fromMap({'id': 'x', 'name': 'y'})!.colorValue,
        defaultThemeSeed);
  });

  test('labels follow the locale', () {
    final preset = builtInThemePresets.first;
    expect(preset.label(const Locale('zh')), preset.name);
    expect(preset.label(const Locale('en')), preset.nameEn);
    expect(preset.label(const Locale('de')), preset.nameEn);
  });

  test('selecting a preset stores the colour and the selection id', () async {
    final prefs = Prefs();
    final ocean = builtInThemePresetById('ocean')!;
    await prefs.selectThemePreset(ocean);
    expect(prefs.themeColor.toARGB32(), ocean.colorValue);
    expect(prefs.themePresetId, 'ocean');
    expect(prefs.activeThemePreset, ocean);
  });

  test('legacy installations resolve the preset from the stored colour',
      () async {
    await Prefs().saveThemeToPrefs(builtInThemePresetById('green')!.colorValue);
    expect(Prefs().themePresetId, isEmpty);
    expect(Prefs().activeThemePreset?.id, 'green');
  });

  test('custom presets are saved, edited and deleted', () async {
    final prefs = Prefs();
    const preset = ThemePreset(
        id: 'custom_9', name: '我的青', nameEn: '', colorValue: 0xFF227766);
    await prefs.saveCustomThemePreset(preset);
    expect(prefs.customThemePresets, [preset]);
    expect(prefs.themeColor.toARGB32(), preset.colorValue);
    expect(prefs.activeThemePreset, preset);

    await prefs.saveCustomThemePreset(
        preset.copyWith(name: '我的蓝', colorValue: 0xFF225588));
    expect(prefs.customThemePresets.single.name, '我的蓝');
    expect(prefs.themeColor.toARGB32(), 0xFF225588);

    await prefs.deleteCustomThemePreset(preset.id);
    expect(prefs.customThemePresets, isEmpty);
    expect(prefs.themePresetId, isEmpty);
  });

  test('resetting the colour also clears the preset selection', () async {
    final prefs = Prefs();
    await prefs.selectThemePreset(builtInThemePresets.first);
    await prefs.resetThemeColor();
    expect(prefs.themePresetId, isEmpty);
    expect(prefs.themeColor.toARGB32(), defaultThemeSeed);
    expect(prefs.activeThemePreset?.id, 'modu');
  });

  test('a corrupt custom preset list is ignored', () async {
    SharedPreferences.setMockInitialValues({'customThemePresets': '{oops'});
    await Prefs().initPrefs();
    expect(Prefs().customThemePresets, isEmpty);
  });
}
