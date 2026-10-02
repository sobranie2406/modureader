import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/l10n/app_language.dart';
import 'package:anx_reader/l10n/modu_catalogs.g.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  tearDown(() => binding.platformDispatcher.clearLocalesTestValue());

  test('parses legacy choices, system, country and script subtags', () {
    expect(parseAppLocale('System'), isNull);
    expect(parseAppLocale('system'), isNull);
    expect(parseAppLocale(null), isNull);
    expect(parseAppLocale('zh-LZH'), const Locale('zh', 'LZH'));
    expect(
        parseAppLocale('zh_Hant_HK'),
        const Locale.fromSubtags(
            languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK'));
    expect(appLocaleKey(parseAppLocale('fr-FR')!), 'fr');
  });

  test(
      'resolution handles regional Chinese, unsupported languages and preference order',
      () {
    expect(
        resolveAppLocale([const Locale('zh', 'HK')]), const Locale('zh', 'TW'));
    expect(
        resolveAppLocale([const Locale('zh', 'SG')]), const Locale('zh', 'CN'));
    expect(
        resolveAppLocale(
            [const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')]),
        const Locale('zh', 'TW'));
    expect(resolveAppLocale([const Locale('zh', 'LZH')]),
        const Locale('zh', 'LZH'));
    expect(resolveAppLocale([const Locale('pl'), const Locale('ja')]),
        const Locale('ja'));
    expect(resolveAppLocale([const Locale('pl')]), const Locale('en'));
    expect(resolveAppLocale(null), const Locale('en'));
  });

  test('manual language overrides system and following system tracks changes',
      () async {
    binding.platformDispatcher.localesTestValue = [const Locale('ja')];
    expect(Prefs().effectiveLocale, const Locale('ja'));
    await Prefs().saveLocaleToPrefs('fr');
    expect(Prefs().effectiveLocale, const Locale('fr'));
    binding.platformDispatcher.localesTestValue = [const Locale('ko')];
    expect(Prefs().effectiveLocale, const Locale('fr'));
    await Prefs().saveLocaleToPrefs('System');
    expect(Prefs().effectiveLocale, const Locale('ko'));
  });

  test('all supported languages have complete UI and prompt catalogs', () {
    final source =
        jsonDecode(File('lib/l10n/modu_source.json').readAsStringSync()) as Map;
    expect(moduCatalogs.keys.toSet(), appLocales.map(appLocaleKey).toSet());
    for (final locale in appLocales) {
      final catalog = moduCatalogs[appLocaleKey(locale)]!;
      expect(catalog.keys.toSet(), source.keys.toSet());
      expect(catalog.values.every((value) => value.trim().isNotEmpty), isTrue);
      for (final skill in readAnySkills) {
        expect(skill.localizedName(locale), isNotEmpty);
        expect(skill.localizedDescription(locale), isNotEmpty);
        expect(skill.localizedPrompt(locale), isNotEmpty);
        if (locale.languageCode != 'zh') {
          expect(skill.localizedName(locale), isNot(skill.name));
          expect(skill.localizedPrompt(locale).trim(),
              isNot(skill.defaultPrompt.trim()));
        }
      }
      for (final prompt in AiPrompts.values) {
        final tokens = RegExp(r'\{\{\w+\}\}')
            .allMatches(prompt.getPrompt())
            .map((match) => match[0]);
        for (final token in tokens) {
          expect(prompt.localizedPrompt(locale), contains(token!));
        }
      }
    }
  });

  test('localized and legacy defaults never become saved overrides', () async {
    for (final locale in appLocales) {
      await Prefs().saveLocaleToPrefs(appLocaleKey(locale));
      for (final skill in readAnySkills) {
        final text = skill.localizedPrompt(locale);
        ReadingSkillPromptStore.save(skill, text);
        expect(ReadingSkillPromptStore.promptFor(skill), text);
      }
      for (final prompt in AiPrompts.values) {
        Prefs().saveAiPrompt(prompt, prompt.localizedPrompt(locale));
        expect(Prefs().getAiPrompt(prompt), prompt.localizedPrompt(locale));
      }
      final backup = await Prefs().buildPrefsBackupMap();
      expect(backup.containsKey('readAnySkillPrompts'), false);
      for (final prompt in AiPrompts.values) {
        expect(backup.containsKey('aiPrompt_${prompt.name}'), false);
      }
    }
    await Prefs().prefs.setString(
        'aiPrompt_summaryTheChapter', AiPrompts.summaryTheChapter.getPrompt());
    await Prefs().saveLocaleToPrefs('ja');
    expect(Prefs().getAiPrompt(AiPrompts.summaryTheChapter),
        AiPrompts.summaryTheChapter.localizedPrompt(const Locale('ja')));
  });

  test(
      'user prompt edits remain exact across language changes and global backup',
      () async {
    const custom = '  My own bilingual prompt\n请保持这个自定义要求  ';
    Prefs().saveAiPrompt(AiPrompts.summaryTheChapter, custom);
    final skill = readAnySkills.singleWhere((s) => s.id == 'concept_explainer');
    ReadingSkillPromptStore.save(skill, custom);
    for (final locale in appLocales) {
      await Prefs().saveLocaleToPrefs(appLocaleKey(locale));
      expect(Prefs().getAiPrompt(AiPrompts.summaryTheChapter), custom);
      expect(ReadingSkillPromptStore.promptFor(skill), custom);
    }
    final exported = await GlobalSettingsTransfer.export(Prefs());
    final restored = await GlobalSettingsTransfer.decode(exported);
    expect(restored['aiPrompt_summaryTheChapter']['value'], custom);
    expect(
        jsonDecode(restored['readAnySkillPrompts']['value'])[skill.id], custom);
  });

  test(
      'selection templates localize without backing up defaults or changing user edits',
      () {
    for (final locale in appLocales) {
      for (final item in SelectionToolbarConfig.templateItems) {
        final localized = item.copyWith(
            name: item.localizedName(locale),
            prompt: item.localizedPrompt(locale),
            enabled: true);
        expect(localized.toJson(),
            {'id': item.id, 'action': item.action, 'enabled': true});
        final imported = SelectionToolbarItem.fromJson(localized.toJson());
        expect(imported.localizedName(locale), localized.name);
        expect(imported.localizedPrompt(locale), localized.prompt);
        expect(imported.promptForSelection('a "quoted" word', locale: locale),
            contains(jsonEncode('a "quoted" word')));
      }
    }
    final custom = SelectionToolbarConfig.templateItems.first
        .copyWith(name: 'MY NAME', prompt: 'MY PROMPT {selection}');
    for (final locale in appLocales) {
      expect(custom.localizedName(locale), 'MY NAME');
      expect(custom.localizedPrompt(locale), 'MY PROMPT {selection}');
    }
    expect(custom.toJson()['prompt'], 'MY PROMPT {selection}');
  });
}
