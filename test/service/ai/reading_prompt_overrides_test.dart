import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('saving unmodified built-in prompts records no override', () async {
    for (final skill in readAnySkills) {
      ReadingSkillPromptStore.save(skill, skill.defaultPrompt.trim());
      expect(ReadingSkillPromptStore.promptFor(skill).trim(),
          skill.localizedPrompt(Prefs().effectiveLocale).trim());
    }
    final raw = await Prefs().buildPrefsBackupMap();
    expect(raw, isNot(contains('readAnySkillPrompts')));
    for (final prompt in AiPrompts.values) {
      expect(raw, isNot(contains('aiPrompt_${prompt.name}')));
    }
  });

  test('old redundant defaults are stripped only in the backup snapshot',
      () async {
    for (final prompt in AiPrompts.values) {
      await Prefs()
          .prefs
          .setString('aiPrompt_${prompt.name}', prompt.getPrompt());
    }
    final oldPrompts = jsonEncode(
        {for (final skill in readAnySkills) skill.id: skill.defaultPrompt});
    await Prefs().prefs.setString('readAnySkillPrompts', oldPrompts);
    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup, isNot(contains('readAnySkillPrompts')));
    expect(Prefs().prefs.getString('readAnySkillPrompts'), oldPrompts);
    final full = await GlobalSettingsTransfer.export(Prefs());
    for (final skill in readAnySkills) {
      expect(full, isNot(contains(skill.defaultPrompt.trim())));
    }
    final data = await GlobalSettingsTransfer.decode(full);
    expect(data['readAnySkillPrompts']['type'], 'reset');
    for (final prompt in AiPrompts.values) {
      expect(data['aiPrompt_${prompt.name}']['type'], 'reset');
    }
  });

  test('only changed prompts travel; switches and custom skills survive',
      () async {
    final source =
        readAnySkills.singleWhere((s) => s.id == 'argument_analyzer');
    await Prefs().prefs.setString(
        'readAnySkillPrompts',
        jsonEncode({
          source.id: source.defaultPrompt,
          'concept_explainer': '用例子解释这个概念',
          'future-skill': '保留未知技能的自定义提示词',
        }));
    Prefs().saveAiPrompt(AiPrompts.summaryTheChapter, '本章三点摘要');
    Prefs().setReadAnySkillEnabled(source.id, false);
    await Prefs().prefs.setString('userPrompts',
        '[{"id":"1","name":"自定义","content":"解释 selected","enabled":false,"order":0,"createdAt":"2026-09-30T00:00:00Z","updatedAt":"2026-09-30T00:00:00Z"}]');
    final text = await GlobalSettingsTransfer.export(Prefs());
    final data =
        await GlobalSettingsTransfer.decode(GlobalSettingsTransfer.link(text));
    final overrides = jsonDecode(data['readAnySkillPrompts']['value']);
    expect(overrides,
        {'concept_explainer': '用例子解释这个概念', 'future-skill': '保留未知技能的自定义提示词'});
    expect(data['aiPrompt_summaryTheChapter']['value'], '本章三点摘要');
    expect(data['readAnySkillStates']['value'], contains('false'));
    expect(data['userPrompts']['value'], contains('自定义'));
    await Prefs()
        .prefs
        .setString('readAnySkillPrompts', '{"ai_dictionary":"目标端旧提示词"}');
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().getReadAnySkillPrompt(source.id, source.defaultPrompt),
        source.defaultPrompt);
    expect(Prefs().getReadAnySkillPrompt('concept_explainer', ''), '用例子解释这个概念');
    expect(Prefs().getAiPrompt(AiPrompts.summaryTheChapter), '本章三点摘要');
    expect(Prefs().isReadAnySkillEnabled(source.id), false);
  });

  test(
      'restoring default backup clears target overrides, not built-in defaults',
      () async {
    final backup = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    Prefs().saveAiPrompt(AiPrompts.mindmap, '目标端旧导图提示词');
    Prefs().setReadAnySkillPrompt('ai_dictionary', '目标端旧字典提示词');
    await GlobalSettingsTransfer.apply(Prefs(), backup);
    expect(Prefs().prefs.containsKey('aiPrompt_mindmap'), false);
    expect(Prefs().readAnySkillPrompts, isEmpty);
    expect(Prefs().getAiPrompt(AiPrompts.mindmap),
        AiPrompts.mindmap.localizedPrompt(Prefs().effectiveLocale));
  });

  test('legacy full default prompts import without saving duplicates',
      () async {
    final backup = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    backup['aiPrompt_mindmap'] = {
      'type': 'string',
      'value': AiPrompts.mindmap.getPrompt()
    };
    backup['readAnySkillPrompts'] = {
      'type': 'string',
      'value': jsonEncode(
          {for (final skill in readAnySkills) skill.id: skill.defaultPrompt})
    };
    await GlobalSettingsTransfer.apply(Prefs(), backup);
    expect(Prefs().prefs.containsKey('aiPrompt_mindmap'), false);
    expect(Prefs().prefs.containsKey('readAnySkillPrompts'), false);
  });

  test('retired AI knowledge defaults are still excluded from backup',
      () async {
    Prefs().setReadAnySkillPrompt(
        legacyAiKnowledgeSkill.id, legacyAiKnowledgeSkill.defaultPrompt);
    final backup = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    expect(backup['readAnySkillPrompts']['type'], 'reset');
    expect(readAnySkills.any((skill) => skill.id == legacyAiKnowledgeSkill.id),
        isFalse);
  });
}
