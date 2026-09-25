import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> show(WidgetTester tester,
      {String? bookKey = 'A', double textScale = 1}) async {
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: Scaffold(
          body: SingleChildScrollView(
              child: CustomCSSEditor(
        bookKey: bookKey,
        onApply: () {},
      ))),
    ));
    await tester.pumpAndSettle();
    AnxToast.fToast.init(tester.element(find.byType(CustomCSSEditor)));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets(
      'all eight slots are available and switching saves independent drafts',
      (tester) async {
    await show(tester);
    expect(find.byType(ChoiceChip), findsNWidgets(10));
    await tester.enterText(
        find.byKey(const ValueKey('custom-css-name')), 'Vertical');
    await tester.enterText(
        find.byKey(const ValueKey('custom-css-code')), 'p { color: blue; }');
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-profile-7')));
    await tester.tap(find.byKey(const ValueKey('custom-css-profile-7')));
    await tester.pumpAndSettle();
    expect(Prefs().customCssProfiles[0].name, 'Vertical');
    expect(Prefs().customCssProfiles[0].css, 'p { color: blue; }');
    expect(Prefs().customCssSelection('A').index, 7);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('custom-css-code')))
            .controller!
            .text,
        isEmpty);
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-profile-0')));
    await tester.tap(find.byKey(const ValueKey('custom-css-profile-0')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('custom-css-code')))
            .controller!
            .text,
        'p { color: blue; }');
    expect(Prefs().customCssSelection('other').index, 0);
  });

  testWidgets('invalid draft blocks switching but disabling remains possible',
      (tester) async {
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 0, enabled: true),
        bookKey: 'A');
    await show(tester);
    await tester.enterText(
        find.byKey(const ValueKey('custom-css-code')), 'p {');
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-profile-1')));
    await tester.tap(find.byKey(const ValueKey('custom-css-profile-1')));
    await tester.pumpAndSettle();
    expect(Prefs().customCssSelection('A').index, 0);
    expect(Prefs().customCssProfiles[0].css, isEmpty);
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-enabled')));
    await tester.tap(find.byKey(const ValueKey('custom-css-enabled')));
    await tester.pumpAndSettle();
    expect(Prefs().customCssSelection('A').enabled, isFalse);
  });

  testWidgets('narrow mobile layout and large text do not overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await Prefs().saveCustomCssProfile(
        0,
        const CustomCssProfile(
            name: 'A long profile name for vertical publisher layout'));
    await show(tester, textScale: 1.5);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(ElevatedButton));
    expect(tester.takeException(), isNull);
  });

  testWidgets('save, default and follow-default preserve the intended scope',
      (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const ValueKey('custom-css-profile-2')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('custom-css-name')), 'Publisher');
    await tester.enterText(
        find.byKey(const ValueKey('custom-css-code')), 'p { margin: 0; }');
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-slot-enabled')));
    await tester.tap(find.byKey(const ValueKey('custom-css-slot-enabled')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-enabled')));
    await tester.tap(find.byKey(const ValueKey('custom-css-enabled')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(Prefs().customCssSelection('A').index, 2);
    expect(Prefs().customCssSelection('A').enabled, isTrue);
    expect(Prefs().customCssSelection('B').enabled, isFalse);
    expect(find.text('Could not save. Please retry.'), findsNothing);
    await tester.ensureVisible(find.text('Set as default'));
    await tester.tap(find.text('Set as default'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(Prefs().customCssSelection('B').index, 2);
    await tester.tap(find.text('Follow default'));
    await tester.pumpAndSettle();
    expect(Prefs().hasBookCustomCssSelection('A'), isFalse);
    expect(Prefs().customCssForBook('A'), 'p { margin: 0; }');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'templates copy into free slots disabled and can be toggled independently',
      (tester) async {
    await Prefs().saveCustomCssProfile(
        0, const CustomCssProfile(name: 'Existing', css: 'p {color:red}'));
    await Prefs().saveCustomCssSelection(
        const CustomCssSelection(index: 0, enabled: true));
    await show(tester);
    await tester.ensureVisible(find.text('Templates'));
    await tester.tap(find.text('Templates'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('对白 · 变色'));
    await tester.tap(find.text('对白 · 变色'));
    await tester.pumpAndSettle();
    expect(Prefs().customCssProfiles[0].name, 'Existing');
    expect(Prefs().customCssProfiles[1].isHighlight, true);
    expect(Prefs().customCssSelection('A').activeIndices, [0]);
    expect(Prefs().customCssSelection('A').index, 1);
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-slot-enabled')));
    await tester.tap(find.byKey(const ValueKey('custom-css-slot-enabled')));
    await tester.pumpAndSettle();
    expect(Prefs().customCssSelection('A').activeIndices, [0, 1]);
    expect(Prefs().customHighlightRulesForBook('A'), hasLength(1));
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-profile-0')));
    await tester.tap(find.byKey(const ValueKey('custom-css-profile-0')));
    await tester.pumpAndSettle();
    expect(Prefs().customCssSelection('A').activeIndices, [0, 1]);
    await tester
        .ensureVisible(find.byKey(const ValueKey('custom-css-slot-enabled')));
    await tester.tap(find.byKey(const ValueKey('custom-css-slot-enabled')));
    await tester.pumpAndSettle();
    expect(Prefs().customCssSelection('A').activeIndices, [1]);
    expect(Prefs().customCssSelection('other').activeIndices, [0]);
    expect(tester.takeException(), isNull);
  });
}
