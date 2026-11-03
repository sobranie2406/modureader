import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS transition workaround is scoped to its renderer configuration',
      () {
    final mac = File('macos/Runner/Info.plist').readAsStringSync();
    expect(mac, matches(RegExp(r'<key>FLTEnableImpeller</key>\s*<false/>')));
    final android =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(android, isNot(contains('EnableImpeller')));
    final ios = File('ios/Runner/Info.plist').readAsStringSync();
    expect(ios, isNot(contains('FLTEnableImpeller')));
  });

  test('feedback is in About instead of a top-level settings category', () {
    final source = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();
    final about = File('lib/widgets/settings/about.dart').readAsStringSync();
    expect(source, isNot(contains('BugReportSettings')));
    expect(about, contains("ValueKey('about-feedback')"));
    expect(about, contains('sections: const BugReportSettings()'));
  });

  test('settings categories consolidate without replacing existing pages', () {
    final settings = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();
    for (final removed in [
      'SelectionSearchSettings',
      'DictionarySettings',
      'GlobalSettingsPage',
      'StorageSettings'
    ]) {
      expect(settings, isNot(contains(removed)));
    }
    expect(settings, contains('同步与备份'));
    expect(settings, isNot(contains('独立于同步')));
    expect(settings, isNot(contains('separate from sync')));
    final toolbar = File('lib/page/settings_page/selection_toolbar.dart')
        .readAsStringSync();
    final sync = File('lib/page/settings_page/sync.dart').readAsStringSync();
    final advanced =
        File('lib/page/settings_page/advanced.dart').readAsStringSync();
    expect(toolbar, contains('const SelectionSearchSettings()'));
    expect(toolbar, contains("'selection-dictionary-settings'"));
    expect(toolbar, contains('const DictionarySettings()'));
    expect(sync, contains('sections: const GlobalSettingsPage()'));
    expect(sync, contains('DatabaseBackupSection('));
    expect(advanced, contains('sections: const StorageSettings()'));
  });
  test('unsupported system speech is disabled with an explicit privacy notice',
      () {
    final settings =
        File('lib/page/settings_page/narrate.dart').readAsStringSync();
    final reader =
        File('lib/widgets/reading_page/tts_widget.dart').readAsStringSync();
    expect(settings, contains('enabled: supportsSystemTts()'));
    expect(
        settings,
        matches(RegExp(
            r'if\s*\(!unsupportedSystem\s*&&\s*!_configDrafts\.containsKey\(ttsServiceId\)\)')));
    expect(settings, contains('systemTtsUnsupportedMessage('));
    expect(reader, contains('if (!_unsupportedSystem &&'));
    expect(reader, contains('if (_unsupportedSystem)'));
  });
  test('home settings tab opens the complete settings interface directly', () {
    final source =
        File('lib/page/home_page/settings_page.dart').readAsStringSync();

    expect(source, contains('return SubMoreSettings('));
    expect(source, contains('embedded: true,'));
    expect(source, contains('controller: controller,'));
    expect(source, contains('HomeNavigationClearance.of(context)'));
    expect(source, isNot(contains('ChangeThemeMode')));
    expect(source, isNot(contains('webdavSwitch')));
    expect(source, isNot(contains('MoreSettings()')));
    expect(source, isNot(contains('IAPPage')));
  });

  test('moved settings remain in their single canonical sections', () {
    final appearance =
        File('lib/page/settings_page/appearance.dart').readAsStringSync();
    final themeColors =
        File('lib/page/settings_page/theme_colors.dart').readAsStringSync();
    final sync = File('lib/page/settings_page/sync.dart').readAsStringSync();
    final settings = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();

    // Theme mode moved into the theme colour page; the appearance page only
    // links to it, so exactly one page owns the selector.
    expect(appearance, contains('ThemeColorsPage'));
    expect(appearance, isNot(contains('ChangeThemeMode')));
    expect(themeColors, contains('ChangeThemeMode'));
    expect(sync, contains('webdavSwitch(context, setState, ref)'));
    expect(settings, isNot(contains('IAPPage')));

    final aboutIndex = settings.indexOf('About(leadingColor: true)');
    final developerIndex = settings.indexOf("const Text('Developer Options')");
    expect(aboutIndex, greaterThan(developerIndex));
  });

  test('AI reading skills live inside AI settings and retain existing controls',
      () {
    final home = File('lib/page/home_page.dart').readAsStringSync();
    final settings = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();
    final ai = File('lib/page/settings_page/ai.dart').readAsStringSync();
    final readingSkills = File('lib/page/settings_page/ai_reading_skills.dart')
        .readAsStringSync();
    final aiChat =
        File('lib/widgets/ai/ai_chat_stream.dart').readAsStringSync();

    expect(home, isNot(contains("'identifier': 'skills'")));
    expect(home, isNot(contains('SkillsPage(')));
    expect(settings, isNot(contains('AiReadingSkillsSettings')));
    expect(ai, contains("ValueKey('ai-reading-skills-settings')"));
    expect(ai, contains('sections: const AiReadingSkillsSettings()'));
    expect(ai, isNot(contains('userPromptsTile()')));
    expect(ai, isNot(contains('AiPrompts.summaryTheChapter')));
    expect(
        readingSkills,
        contains(
            'orderedReadingSkills(customSkills, Prefs().readAnySkillOrder)'));
    expect(readingSkills, contains("ValueKey('reading-skills-order-list')"));
    expect(readingSkills, contains('_builtInSkillTile(entry.builtIn!'));
    expect(readingSkills, contains('_customSkillTile(entry.custom!'));
    expect(readingSkills, contains('功能提示词'));
    expect(aiChat, contains('bool _showSkillPrompts = false;'));
    expect(
        aiChat,
        matches(RegExp(
            r'if\s*\(!compact\s*&&\s*widget\.showSkillControls\s*&&\s*_isReaderSkills\s*&&\s*_showSkillPrompts\)')));
    expect(aiChat, contains('_buildSkillPicker(context)'));
  });

  test('one model category links to unchanged vector and OCR settings', () {
    final settings = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();
    final models =
        File('lib/page/settings_page/models.dart').readAsStringSync();
    expect(settings, contains('"sections": const ModelSettings()'));
    expect(settings, contains('离线本地模型设置'));
    expect(models, contains('离线本地模型设置'));
    expect(settings, isNot(contains('const VectorModelSettings()')));
    expect(settings, isNot(contains('const OcrModelSettings()')));
    expect(models, contains('sections: const VectorModelSettings()'));
    expect(models, contains('sections: const OcrModelSettings()'));
    expect(models, contains("ValueKey('model-settings-vector')"));
    expect(models, contains("ValueKey('model-settings-ocr')"));
  });

  test('CSS management is nested under Reading and reader guidance follows it',
      () {
    final settings = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();
    final reading =
        File('lib/page/settings_page/reading.dart').readAsStringSync();
    final guidance = File(
            'lib/widgets/reading_page/more_settings/css_profile_application.dart')
        .readAsStringSync();
    expect(settings, isNot(contains('const CssSettings()')));
    expect(reading, contains("ValueKey('reading-css-settings')"));
    expect(reading, contains('sections: const CssSettings()'));
    expect(guidance, contains('Settings → Reading → CSS settings'));
  });
}
