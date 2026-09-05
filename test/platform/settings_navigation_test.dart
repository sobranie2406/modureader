import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home settings tab opens the complete settings interface directly', () {
    final source =
        File('lib/page/home_page/settings_page.dart').readAsStringSync();

    expect(source, contains('SubMoreSettings(embedded: true)'));
    expect(source, isNot(contains('ChangeThemeMode')));
    expect(source, isNot(contains('webdavSwitch')));
    expect(source, isNot(contains('MoreSettings()')));
    expect(source, isNot(contains('IAPPage')));
  });

  test('moved settings remain in their single canonical sections', () {
    final appearance =
        File('lib/page/settings_page/appearance.dart').readAsStringSync();
    final sync = File('lib/page/settings_page/sync.dart').readAsStringSync();
    final settings = File('lib/page/settings_page/more_settings_page.dart')
        .readAsStringSync();

    expect(appearance, contains('ChangeThemeMode'));
    expect(sync, contains('webdavSwitch(context, setState, ref)'));
    expect(settings, isNot(contains('IAPPage')));

    final aboutIndex = settings.indexOf('const About(leadingColor: true)');
    final developerIndex = settings.indexOf("const Text('Developer Options')");
    expect(aboutIndex, greaterThan(developerIndex));
  });

  test('AI reading skills are merged into their own settings category', () {
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
    expect(settings, contains('AiReadingSkillsSettings'));
    expect(settings, contains('AI 阅读技能'));
    expect(ai, isNot(contains('userPromptsTile()')));
    expect(ai, isNot(contains('AiPrompts.summaryTheChapter')));
    expect(readingSkills, contains('内置阅读技能'));
    expect(readingSkills, contains('自定义技能'));
    expect(readingSkills, contains('功能提示词'));
    expect(aiChat, contains('if (widget.quickPromptChips.isEmpty) ...['));
  });
}
