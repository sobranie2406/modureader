import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/page/settings_page/appearance.dart';
import 'package:anx_reader/page/settings_page/ai.dart';
import 'package:anx_reader/page/settings_page/ai_reading_skills.dart';
import 'package:anx_reader/page/settings_page/settings_page.dart';
import 'package:anx_reader/page/settings_page/selection_toolbar.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/widgets/context_menu/selection_toolbar_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget child, {double scale = 1}) => ProviderScope(
      child: AnimatedBuilder(
          animation: Prefs(),
          builder: (context, _) => MaterialApp(
                locale: Prefs().locale,
                localeListResolutionCallback: resolveAppLocale,
                supportedLocales: L10n.supportedLocales,
                localizationsDelegates: L10n.localizationsDelegates,
                builder: (context, widget) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: widget!,
                ),
                home: Scaffold(body: child),
              )),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    // Deferred language libraries must be loaded before pumping widget frames.
    for (final locale in appLocales) {
      for (final delegate in L10n.localizationsDelegates) {
        if (delegate.isSupported(locale)) await delegate.load(locale);
      }
    }
  });
  testWidgets(
      'manual picker contains every language and a localized system option',
      (tester) async {
    await Prefs().saveLocaleToPrefs('en');
    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(
              onPressed: () => showLanguagePickerDialog(context),
              child: const Text('choose'),
            ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('choose'));
    await tester.pumpAndSettle();
    expect(find.text('Follow system'), findsOneWidget);
    for (final choice in languageOptions) {
      expect(find.byKey(ValueKey('app-language-${choice.values.first}')),
          findsOneWidget);
    }
    final japanese = find.byKey(const ValueKey('app-language-ja'));
    await tester.ensureVisible(japanese);
    await tester.tap(japanese);
    await tester.pumpAndSettle();
    expect(Prefs().locale, const Locale('ja'));
    expect(find.byKey(const ValueKey('app-language-picker')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system changes update UI and manual selection stays fixed',
      (tester) async {
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ja')];
    await tester.pumpWidget(app(Builder(
        builder: (context) => Text(
            '${Localizations.localeOf(context).languageCode} ${ModuStrings.text(context, '跟随系统', 'Follow system')}'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('ja '), findsOneWidget);
    tester.binding.platformDispatcher.localesTestValue = [const Locale('fr')];
    tester.binding.handleLocaleChanged();
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('fr '), findsOneWidget);
    await Prefs().saveLocaleToPrefs('en');
    await tester.pumpAndSettle();
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ko')];
    tester.binding.handleLocaleChanged();
    await tester.pumpAndSettle();
    expect(find.text('en Follow system'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open appearance page title updates immediately with language',
      (tester) async {
    await Prefs().saveLocaleToPrefs('zh-CN');
    await tester.pumpWidget(app(SettingsPageBody(
      title: '外观',
      titleBuilder: (context) => L10n.of(context).settingsAppearance,
      isMobile: true,
      sections: const AppearanceSetting(),
    )));
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsWidgets);
    await Prefs().saveLocaleToPrefs('en');
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pumpAndSettle();
    expect(find.text('外观'), findsNothing);
    expect(find.text('Appearance'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['fr', 'ja', 'ar']) {
    testWidgets('$language AI history settings use the chosen language',
        (tester) async {
      await Prefs().saveLocaleToPrefs(language);
      // Also exercise first-use migration with an obsolete selected provider.
      Prefs().selectedAiService = 'removed-provider';
      final locale = Prefs().effectiveLocale;
      await tester.pumpWidget(app(const AISettings()));
      await tester.pumpAndSettle();
      final history = ModuStrings.label(locale, '保留对话历史', 'Keep chat history');
      await tester.scrollUntilVisible(find.text(history), 250,
          scrollable: find.byType(Scrollable).first, maxScrolls: 25);
      await tester.pumpAndSettle();
      expect(find.text(history), findsOneWidget);
      expect(find.text('保留对话历史'), findsNothing);
      expect(find.text('Keep chat history'), findsNothing);
      expect(Prefs().selectedAiService, 'openai');
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['en', 'ja', 'fr', 'ar', 'zh-TW']) {
    testWidgets(
        '$language reading skills and editor use chosen language without saving defaults',
        (tester) async {
      final locale = parseAppLocale(language)!;
      await Prefs().saveLocaleToPrefs(language);
      await tester.pumpWidget(app(const AiReadingSkillsSettings()));
      await tester.pumpAndSettle();
      final skill = readAnySkills.first;
      expect(find.text(skill.localizedName(locale)), findsOneWidget);
      if (language == 'ar') {
        expect(
            Directionality.of(
                tester.element(find.text(skill.localizedName(locale)))),
            TextDirection.rtl);
      }
      await tester.tap(find.byKey(ValueKey('reading-skill-${skill.id}')));
      await tester.pumpAndSettle();
      final editor = tester.widget<TextField>(
          find.byKey(const ValueKey('reading-skill-prompt-editor')));
      expect(editor.controller!.text, skill.localizedPrompt(locale));
      final context = tester.element(find.byType(AlertDialog));
      final save = ModuStrings.text(context, '保存', 'Save');
      await tester.tap(find.widgetWithText(FilledButton, save));
      await tester.pumpAndSettle();
      expect(Prefs().readAnySkillPrompts, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'Japanese selection template editor displays localized defaults and saves only edits',
      (tester) async {
    await Prefs().saveLocaleToPrefs('ja');
    await tester.pumpWidget(app(const SelectionToolbarSettings()));
    await tester.pumpAndSettle();
    final item = SelectionToolbarConfig.templateItems.first;
    final target = find.byKey(ValueKey('toolbar-edit-${item.id}'));
    await tester.scrollUntilVisible(target, 180,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('selection-toolbar-scroll')),
                matching: find.byType(Scrollable))
            .first,
        maxScrolls: 50);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('toolbar-name')))
            .controller!
            .text,
        item.localizedName(const Locale('ja')));
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('toolbar-prompt')))
            .controller!
            .text,
        item.localizedPrompt(const Locale('ja')));
    final context = tester.element(find.byType(AlertDialog));
    await tester.tap(find.widgetWithText(
        FilledButton, ModuStrings.text(context, '保存', 'Save')));
    await tester.pumpAndSettle();
    final stored = Prefs()
        .selectionToolbar
        .items
        .firstWhere((entry) => entry.id == item.id)
        .toJson();
    expect(stored.containsKey('name'), false);
    expect(stored.containsKey('prompt'), false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('translated toolbar names preserve user names', (tester) async {
    await Prefs().saveLocaleToPrefs('fr');
    final template = SelectionToolbarConfig.templateItems.first;
    await tester.pumpWidget(app(Builder(
        builder: (context) => Column(children: [
              Text(selectionToolbarLabel(context, template)),
              Text(selectionToolbarLabel(
                  context, template.copyWith(name: '我的自定义名称'))),
            ]))));
    await tester.pumpAndSettle();
    expect(
        find.text(template.localizedName(const Locale('fr'))), findsOneWidget);
    expect(find.text('我的自定义名称'), findsOneWidget);
  });

  for (final save in [false, true]) {
    testWidgets(
        'feature and custom editors survive ${save ? 'save' : 'cancel'} transitions',
        (tester) async {
      await Prefs().saveLocaleToPrefs('en');
      await tester.pumpWidget(app(const AiReadingSkillsSettings()));
      await tester.pumpAndSettle();
      Future<void> reveal(Finder target) async {
        await tester.scrollUntilVisible(target, 200,
            scrollable: find.byType(Scrollable).first, maxScrolls: 60);
        await tester.pumpAndSettle();
      }

      Future<void> closeEditor() async {
        final context = tester.element(find.byType(AlertDialog));
        final label = ModuStrings.text(
            context, save ? '保存' : '取消', save ? 'Save' : 'Cancel');
        await tester.tap(save
            ? find.widgetWithText(FilledButton, label)
            : find.widgetWithText(TextButton, label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
      }

      final feature = find.byKey(const ValueKey('reading-feature-test'));
      await reveal(feature);
      await tester.tap(feature);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('reading-skill-prompt-editor')),
          'MY FEATURE PROMPT');
      await closeEditor();
      expect(
          Prefs().getAiPrompt(AiPrompts.test),
          save
              ? 'MY FEATURE PROMPT'
              : AiPrompts.test.localizedPrompt(const Locale('en')));
      final create = find.byKey(const ValueKey('add-custom-reading-skill'));
      // The feature section is below the custom section.
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await reveal(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('custom-skill-name-editor')), 'MY SKILL');
      await tester.enterText(
          find.byKey(const ValueKey('custom-skill-prompt-editor')),
          'MY CUSTOM PROMPT');
      await closeEditor();
      expect(Prefs().userPrompts.length, save ? 1 : 0);
      if (save) expect(Prefs().userPrompts.single.content, 'MY CUSTOM PROMPT');
    });
  }
}
