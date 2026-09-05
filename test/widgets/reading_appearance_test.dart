import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/bgimg_alignment.dart';
import 'package:anx_reader/enums/bgimg_theme_mode.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/models/bgimg.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/service/book_player/reading_appearance.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ReadTheme theme() => ReadTheme(
    id: 3,
    backgroundColor: 'fffafafa',
    textColor: 'ff123456',
    backgroundImagePath: '');
const image = BgimgModel(
    type: BgimgType.assets,
    path: 'assets/images/bgimg/bg1.jpg',
    nightPath: 'assets/images/bgimg/bg6.jpg',
    alignment: BgimgAlignment.center);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().saveReadThemeToPrefs(theme());
    Prefs().bgimg = image;
    Prefs().autoAdjustReadingTheme = true;
  });

  test(
      'solid colour removes covering image, exits auto mode and survives reload',
      () async {
    final selected = theme()..backgroundColor = 'ffaabbcc';
    var applied = false;
    selectReadingColorTheme(selected, prefs: Prefs(), apply: (value) {
      expect(Prefs().bgimg.type, BgimgType.none);
      expect(value.backgroundColor, 'ffaabbcc');
      applied = true;
    });
    expect(applied, isTrue);
    await Prefs().initPrefs();
    expect(Prefs().readTheme.backgroundColor, 'ffaabbcc');
    expect(Prefs().autoAdjustReadingTheme, isFalse);
    expect(Prefs().bgimg.type, BgimgType.none);
  });

  test(
      'explicit night background persists without being overridden by auto mode',
      () async {
    var applied = false;
    selectReadingBackground(image.copyWith(selectedMode: BgimgThemeMode.night),
        prefs: Prefs(), apply: () => applied = true);
    await Prefs().initPrefs();
    expect(applied, isTrue);
    expect(Prefs().bgimg.selectedMode, BgimgThemeMode.night);
    expect(Prefs().autoAdjustReadingTheme, isFalse);
    expect(Prefs().readTheme.backgroundColor, 'fffafafa');
  });

  for (final dismiss in ['cancel', 'back', 'barrier']) {
    testWidgets('$dismiss does not persist or apply a changed colour',
        (tester) async {
      var saved = 0;
      var applied = 0;
      final current = theme();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ThemeChangeWidget(
        readTheme: current,
        setCurrentPage: (_) {},
        saveTheme: (_) async => saved++,
        applyTheme: (_) => applied++,
      ))));
      await tester.tap(find.byIcon(Icons.circle));
      await tester.pumpAndSettle();
      tester
          .widget<ColorPicker>(find.byType(ColorPicker))
          .onColorChanged(Colors.red);
      if (dismiss == 'cancel') {
        await tester.tap(find.text('Cancel'));
      } else if (dismiss == 'back') {
        await tester.binding.handlePopRoute();
      } else {
        await tester.tapAt(const Offset(5, 5));
      }
      await tester.pumpAndSettle();
      expect(saved, 0);
      expect(applied, 0);
      expect(current.backgroundColor, 'fffafafa');
      expect(Prefs().bgimg.type, BgimgType.assets);
      expect(Prefs().autoAdjustReadingTheme, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  for (final background in [true, false]) {
    testWidgets(
        'confirmed ${background ? 'background' : 'text'} colour is saved and applied immediately',
        (tester) async {
      ReadTheme? saved;
      ReadTheme? applied;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ThemeChangeWidget(
        readTheme: theme(),
        setCurrentPage: (_) {},
        saveTheme: (value) async => saved = value,
        applyTheme: (value) => applied = value,
      ))));
      await tester
          .tap(find.byIcon(background ? Icons.circle : Icons.text_fields));
      await tester.pumpAndSettle();
      tester
          .widget<ColorPicker>(find.byType(ColorPicker))
          .onColorChanged(const Color(0x00123456));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
          background ? saved!.backgroundColor : saved!.textColor, '00123456');
      expect(applied, same(saved));
      expect(
          background
              ? Prefs().readTheme.backgroundColor
              : Prefs().readTheme.textColor,
          '00123456');
      expect(
          Prefs().bgimg.type, background ? BgimgType.none : BgimgType.assets);
      expect(Prefs().autoAdjustReadingTheme, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('database failure preserves previous theme and reports failure',
      (tester) async {
    var applied = false;
    final current = theme();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ThemeChangeWidget(
      readTheme: current,
      setCurrentPage: (_) {},
      saveTheme: (_) async => throw StateError('database unavailable'),
      applyTheme: (_) => applied = true,
    ))));
    await tester.tap(find.byIcon(Icons.circle));
    await tester.pumpAndSettle();
    tester
        .widget<ColorPicker>(find.byType(ColorPicker))
        .onColorChanged(Colors.red);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    expect(current.backgroundColor, 'fffafafa');
    expect(find.text('Could not save the theme. Please try again.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
