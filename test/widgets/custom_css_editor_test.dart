import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/models/custom_css_profile.dart';
import 'package:modu_reader/page/settings_page/css_settings.dart';
import 'package:modu_reader/page/settings_page/settings_page.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:modu_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> show(WidgetTester tester,
      {bool manage = true,
      Locale locale = const Locale('en'),
      double textScale = 1,
      bool settingsRoute = false}) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: settingsRoute
          ? const SettingsPageBody(
              title: 'CSS settings', isMobile: true, sections: CssSettings())
          : Scaffold(
              body: SingleChildScrollView(
              child: CustomCSSEditor(
                  manage: manage, bookKey: manage ? null : 'A', onApply: () {}),
            )),
    ));
    await tester.pumpAndSettle();
    AnxToast.fToast.init(tester.element(find.byType(CustomCSSEditor)));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.text('Save template'), findsNothing);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets(
      'template name follows locale without rewriting saved CSS or name',
      (tester) async {
    final original = Prefs().customCssProfiles[8];
    final name = find.byKey(const ValueKey('custom-css-name'));
    await show(tester);
    expect(tester.widget<TextField>(name).controller!.text,
        original.localizedName(const Locale('en')));
    await tap(tester, find.byKey(const ValueKey('css-option-italic')));
    expect(Prefs().customCssProfiles[8].name, original.name);
    expect(Prefs().customCssProfiles[8].css, original.css);
    expect(Prefs().customCssProfiles[8].pattern, original.pattern);
    await show(tester, locale: const Locale('fr'));
    expect(Localizations.localeOf(tester.element(name)), const Locale('fr'));
    expect(tester.widget<TextField>(name).controller!.text,
        original.localizedName(const Locale('fr')));
    await tester.ensureVisible(name);
    await tester.enterText(name, 'My edited template');
    await tester.pumpAndSettle();
    await show(tester, locale: const Locale('ja'));
    expect(
        tester.widget<TextField>(name).controller!.text, 'My edited template');
    expect(Prefs().customCssProfiles[8].name, 'My edited template');
    expect(tester.takeException(), isNull);
  });

  testWidgets('preset dialog and newly added preset use localized names',
      (tester) async {
    await show(tester);
    await tap(tester, find.text('Templates'));
    final preset = customCssTemplates.first;
    final option = find.descendant(
        of: find.byType(SimpleDialog),
        matching: find.text(preset.localizedName(const Locale('en'))));
    expect(option, findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SimpleDialog), matching: find.text(preset.name)),
        findsNothing);
    await tap(tester, option);
    expect(Prefs().customCssProfiles[0].toJson(), preset.toJson());
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('custom-css-name')))
            .controller!
            .text,
        preset.localizedName(const Locale('en')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader only applies templates and preserves other books',
      (tester) async {
    await show(tester, manage: false);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Import'), findsNothing);
    await tap(tester, find.byKey(const ValueKey('apply-css-8')));
    expect(Prefs().customCssSelection('A').enabled, isTrue);
    expect(Prefs().customCssForBook('A'), contains('text-indent: 2.0em'));
    expect(Prefs().customCssSelection('B').enabled, isFalse);
    await tap(tester, find.text('Follow default templates'));
    expect(Prefs().hasBookCustomCssSelection('A'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('named presets save graphical color and underline modules',
      (tester) async {
    await show(tester);
    expect(find.byKey(const ValueKey('css-profile-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('custom-css-code')), findsNothing);
    await tap(tester, find.byKey(const ValueKey('css-option-color')));
    await tap(tester, find.byKey(const ValueKey('css-choice-decoration-wavy')));
    await save(tester);
    final profile = Prefs().customCssProfiles[8];
    expect(profile.visual!.values['color'], isNotNull);
    expect(profile.compiledCss, contains('text-decoration-style: wavy'));
    await tester.pumpWidget(const SizedBox.shrink());
    await show(tester);
    final toggle =
        tester.widget<Switch>(find.byKey(const ValueKey('css-option-color')));
    expect(toggle.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy custom code survives graphical edits', (tester) async {
    const code = 'p { color: blue; }';
    await Prefs().saveCustomCssProfile(
        0, const CustomCssProfile(name: 'Legacy', css: code));
    await show(tester);
    await tap(tester, find.byKey(const ValueKey('css-option-italic')));
    await save(tester);
    expect(Prefs().customCssProfiles[0].css, code);
    expect(Prefs().customCssProfiles[0].compiledCss, endsWith(code));
    expect(Prefs().customCssProfiles[0].visual!.values['italic'], isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid code blocks saving but disabling remains possible',
      (tester) async {
    await Prefs().saveCustomCssProfile(0, const CustomCssProfile(css: 'p {}'));
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 0, enabled: true));
    await show(tester);
    await tester.enterText(
        find.byKey(const ValueKey('custom-css-code')), 'p {');
    await save(tester);
    expect(Prefs().customCssProfiles[0].css, 'p {}');
    await tap(tester, find.byKey(const ValueKey('custom-css-enabled')));
    expect(Prefs().customCssSelection().enabled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow mobile layout with large text does not overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await show(tester, textScale: 1.5, settingsRoute: true);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Clear current CSS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'switching saves separate drafts and duplicate preserves graphics',
      (tester) async {
    await show(tester);
    await tap(tester, find.byKey(const ValueKey('css-option-color')));
    await tap(tester, find.byKey(const ValueKey('css-profile-9')));
    expect(Prefs().customCssProfiles[8].visual!.values['color'], '#a05000');
    expect(Prefs().customCssProfiles[9].visual!.values.containsKey('color'),
        isFalse);
    await tap(tester, find.byKey(const ValueKey('css-option-weight')));
    await tap(tester, find.text('Duplicate'));
    final original = Prefs().customCssProfiles[9];
    final copy = Prefs().customCssProfiles[0];
    expect(copy.visual!.values, original.visual!.values);
    expect(copy.compiledCss, original.compiledCss);
    expect(copy.name, endsWith('copy'));
    expect(Prefs().customCssSelection().activeIndices, isNot(contains(0)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('CSS tags select drafts and scope without enabling profiles',
      (tester) async {
    await show(tester);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byType(PopupMenuButton<bool>), findsNothing);
    final selection = Prefs().customCssSelection();
    await tap(tester, find.byKey(const ValueKey('css-scope-body')));
    expect(Prefs().customCssProfiles[8].scope, 'body');
    await tap(tester, find.byKey(const ValueKey('css-profile-9')));
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('css-profile-9')))
            .selected,
        isTrue);
    await tap(tester, find.byKey(const ValueKey('css-scope-title')));
    expect(Prefs().customCssProfiles[9].scope, 'title');
    await tap(tester, find.byKey(const ValueKey('css-profile-8')));
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('css-scope-body')))
            .selected,
        isTrue);
    expect(Prefs().customCssSelection().enabled, selection.enabled);
    expect(Prefs().customCssSelection().activeIndices, selection.activeIndices);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid CSS still prevents switching with tags', (tester) async {
    await Prefs().saveCustomCssProfile(
        0, const CustomCssProfile(name: 'Legacy', css: 'p {}'));
    await show(tester);
    await tester.enterText(
        find.byKey(const ValueKey('custom-css-code')), 'p {');
    await tap(tester, find.byKey(const ValueKey('css-profile-8')));
    expect(
        tester
            .widget<ChoiceChip>(find.byKey(const ValueKey('css-profile-0')))
            .selected,
        isTrue);
    expect(Prefs().customCssProfiles[0].css, 'p {}');
    expect(tester.takeException(), isNull);
  });
}
