import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Warm locale resources outside each widget test's fake async zone.
    for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
      await L10n.delegate.load(locale);
      await GlobalMaterialLocalizations.delegate.load(locale);
      await GlobalCupertinoLocalizations.delegate.load(locale);
      await GlobalWidgetsLocalizations.delegate.load(locale);
    }
  });
  late Directory temporary;
  late String oldPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().useBookStyles = false;
    oldPath = documentPath;
    temporary = await Directory.systemTemp.createTemp('modu-quick-weight-');
    documentPath = temporary.path;
    await getFontDir().create();
  });
  tearDown(() async {
    documentPath = oldPath;
    await temporary.delete(recursive: true);
  });

  Future<void> show(WidgetTester tester,
      {Locale locale = const Locale('en'),
      double scale = 1,
      Brightness brightness = Brightness.light}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(brightness: brightness),
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
        body: SizedBox(
          height: 420,
          child: StyleWidget(
            themes: const [],
            epubPlayerKey: GlobalKey<EpubPlayerState>(),
            setCurrentPage: (_) {},
            hideAppBarAndBottomBar: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(StyleWidget), findsOneWidget);
    expect(find.byKey(const ValueKey('reading-font-weight-slider')),
        findsOneWidget);
  }

  Finder weight() => find.byKey(const ValueKey('reading-font-weight-slider'));
  Finder simulated() =>
      find.byKey(const ValueKey('reading-simulated-bold-toggle'));

  testWidgets('boldness slider is between font size and line spacing',
      (tester) async {
    await show(tester, locale: const Locale('zh', 'CN'));
    expect(find.text('字体粗细'), findsOneWidget);
    final boldY = tester.getCenter(weight()).dy;
    expect(
        tester.getCenter(find.byIcon(Icons.format_size)).dy, lessThan(boldY));
    expect(tester.getCenter(find.byIcon(Icons.line_weight)).dy,
        greaterThan(boldY));
    final slider = tester.widget<Slider>(weight());
    expect(slider.min, 0.5);
    expect(slider.max, 2.0);
    expect(slider.divisions, 15);
    expect((slider.max - slider.min) / slider.divisions!, closeTo(0.1, 1e-10));
    expect(slider.value, 1.0);
    expect(slider.label, '1.0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick weight changes persist without changing other styles',
      (tester) async {
    final original = Prefs().bookStyle;
    await show(tester);
    for (var step = 0; step <= 15; step++) {
      final value = (5 + step) / 10;
      tester.widget<Slider>(weight()).onChanged!(value);
      await tester.pumpAndSettle();
      expect(Prefs().bookStyle.fontWeight, (5 + step) * 40.0);
      expect(tester.widget<Slider>(weight()).value, value);
      expect(tester.widget<Slider>(weight()).label, value.toStringAsFixed(1));
    }
    expect(Prefs().bookStyle.fontSize, original.fontSize);
    expect(Prefs().bookStyle.lineHeight, original.lineHeight);
    await tester.pumpWidget(const SizedBox.shrink());
    await Prefs().initPrefs();
    await show(tester);
    expect(tester.widget<Slider>(weight()).value, 2.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weight control is moved out of advanced style settings',
      (tester) async {
    await show(tester);
    tester.widget<Slider>(weight()).onChanged!(1.5);
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: StyleSettings())),
    ));
    await tester.pumpAndSettle();
    final advanced = find.descendant(
        of: find.byWidgetPredicate(
            (w) => w is StyleSlider && w.icon == Icons.format_bold),
        matching: find.byType(Slider));
    expect(advanced, findsNothing);
    await show(tester);
    expect(tester.widget<Slider>(weight()).value, 1.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book styles disable quick boldness without losing the value',
      (tester) async {
    await Prefs()
        .saveBookStyleToPrefs(Prefs().bookStyle.copyWith(fontWeight: 600));
    Prefs().useBookStyles = true;
    await show(tester);
    expect(tester.widget<Slider>(weight()).onChanged, isNull);
    expect(tester.widget<Slider>(weight()).value, 1.5);
    Prefs().useBookStyles = false;
    await tester.pumpWidget(const SizedBox.shrink());
    await show(tester);
    expect(tester.widget<Slider>(weight()).onChanged, isNotNull);
    expect(tester.widget<Slider>(weight()).value, 1.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('simulated bold toggle sits beside weight and persists',
      (tester) async {
    await show(tester, locale: const Locale('zh', 'CN'));
    expect(find.text('模拟加粗'), findsOneWidget);
    expect(tester.getCenter(simulated()).dx,
        greaterThan(tester.getCenter(weight()).dx));
    expect(tester.getCenter(simulated()).dy,
        closeTo(tester.getCenter(weight()).dy, 1));
    expect(Prefs().bookStyle.simulateBold, isFalse);
    expect(
        find.descendant(
            of: simulated(),
            matching: find.byIcon(Icons.radio_button_unchecked)),
        findsOneWidget);
    expect(tester.getSize(simulated()).height, greaterThanOrEqualTo(48));
    await tester.tap(simulated());
    await tester.pumpAndSettle();
    expect(Prefs().bookStyle.simulateBold, isTrue);
    expect(
        find.descendant(
            of: simulated(), matching: find.byIcon(Icons.check_circle)),
        findsOneWidget);
    expect(tester.widget<Semantics>(simulated()).properties.toggled, isTrue);
    // Switching modes does not silently change the slider or other styles.
    expect(tester.widget<Slider>(weight()).value, 1.0);
    tester.widget<Slider>(weight()).onChanged!(1.7);
    await tester.pumpAndSettle();
    expect(Prefs().bookStyle.fontWeight, 680);
    expect(Prefs().bookStyle.simulateBold, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await Prefs().initPrefs();
    await show(tester);
    expect(tester.widget<Semantics>(simulated()).properties.toggled, isTrue);
    expect(tester.widget<Slider>(weight()).value, 1.7);
    await tester.tap(simulated());
    await tester.pumpAndSettle();
    expect(Prefs().bookStyle.simulateBold, isFalse);
    expect(Prefs().bookStyle.fontWeight, 680);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book styles disable simulation but preserve its saved value',
      (tester) async {
    await Prefs().saveBookStyleToPrefs(
        Prefs().bookStyle.copyWith(fontWeight: 600, simulateBold: true));
    Prefs().useBookStyles = true;
    await show(tester);
    final button =
        find.descendant(of: simulated(), matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(Prefs().bookStyle.simulateBold, isTrue);
    Prefs().useBookStyles = false;
    await show(tester);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    expect(Prefs().bookStyle.simulateBold, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('boldness remains reachable with large text on narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, scale: 1.5);
    await tester.ensureVisible(weight());
    expect(find.text('Font thickness'), findsOneWidget);
    expect(find.text('Simulated bold'), findsOneWidget);
    await tester.tap(simulated());
    await tester.pumpAndSettle();
    expect(Prefs().bookStyle.simulateBold, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('simulation has outlined and selected states in $brightness',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await show(tester, scale: 1.5, brightness: brightness);
      final button =
          find.descendant(of: simulated(), matching: find.byType(TextButton));
      final theme = Theme.of(tester.element(button)).colorScheme;
      var style = tester.widget<TextButton>(button).style!;
      expect(style.side!.resolve({})!.color, theme.outlineVariant);
      expect(tester.getSize(weight()).width, greaterThanOrEqualTo(100));
      await tester.tap(simulated());
      await tester.pumpAndSettle();
      style = tester.widget<TextButton>(button).style!;
      expect(style.side!.resolve({})!.color, theme.primary);
      expect(style.backgroundColor!.resolve({}), theme.primaryContainer);
      expect(tester.widget<Semantics>(simulated()).properties.toggled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
