import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_layout.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/settings_modules.dart';
import 'package:anx_reader/service/config_transfer/settings_value_validation.dart';
import 'package:anx_reader/widgets/ai/reading_skill_chips.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

UserPrompt customSkill(String id, {int order = 0, bool enabled = true}) =>
    UserPrompt(
        id: id,
        name: 'Custom $id',
        content: 'Prompt $id',
        enabled: enabled,
        order: order,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test(
      'default visibility and legacy order are preserved without a saved layout',
      () {
    expect(Prefs().aiReadingSkillsVisible, isTrue);
    final entries = orderedReadingSkills(
        [customSkill('b', order: 1), customSkill('a')], []);
    expect(entries.take(readAnySkills.length).map((e) => e.builtIn!.id),
        readAnySkills.map((e) => e.id));
    expect(entries.skip(readAnySkills.length).map((e) => e.custom!.id),
        ['a', 'b']);
  });

  test('custom skills may be first or between built-ins', () {
    final entries = orderedReadingSkills([customSkill('a'), customSkill('b')],
        ['custom:a', 'builtin:mindmap', 'custom:b', 'builtin:smart_summary']);
    expect(entries.take(4).map((e) => e.id),
        ['custom:a', 'builtin:mindmap', 'custom:b', 'builtin:smart_summary']);
    expect(entries, hasLength(readAnySkills.length + 2));
  });

  test(
      'deleted unknown and repeated IDs do not duplicate or hide remaining skills',
      () {
    final entries = orderedReadingSkills([
      customSkill('new')
    ], [
      'custom:deleted',
      'builtin:future',
      'builtin:mindmap',
      'builtin:mindmap'
    ]);
    expect(entries.first.id, 'builtin:mindmap');
    expect(entries.last.id, 'custom:new');
    expect(entries.map((e) => e.id).toSet(), hasLength(entries.length));
    expect(entries, hasLength(readAnySkills.length + 1));
  });

  test('namespaced IDs avoid custom versus built-in collisions', () {
    final entries = orderedReadingSkills(
        [customSkill('mindmap')], ['custom:mindmap', 'builtin:mindmap']);
    expect(entries[0].custom, isNotNull);
    expect(entries[1].builtIn, isNotNull);
  });

  test('retired knowledge preset stays hidden even with saved order and edits',
      () async {
    final custom = customSkill('ai_dictionary');
    Prefs().userPrompts = [custom];
    Prefs().readAnySkillOrder = [
      'builtin:ai_dictionary',
      'custom:ai_dictionary',
      'builtin:mindmap',
    ];
    Prefs().setReadAnySkillEnabled('ai_dictionary', true);
    Prefs().setReadAnySkillPrompt('ai_dictionary', '以前修改的提示词');
    await Prefs().initPrefs();
    final entries =
        orderedReadingSkills(Prefs().userPrompts, Prefs().readAnySkillOrder);
    expect(entries.first.id, 'custom:ai_dictionary');
    expect(entries.map((entry) => entry.id),
        isNot(contains('builtin:ai_dictionary')));
    final chips = configuredReadingSkillChips(const Locale('zh'));
    expect(chips.any((chip) => chip.skillId == 'ai_dictionary'), isFalse);
    expect(chips.first.label, custom.name);
    expect(chips.first.prompt, custom.content);
    expect(Prefs().readAnySkillPrompts['ai_dictionary'], '以前修改的提示词');
  });

  test('chips use mixed order, filter both types and honor edited prompts', () {
    Prefs().userPrompts = [
      customSkill('a'),
      customSkill('off', enabled: false)
    ];
    Prefs().readAnySkillOrder = [
      'custom:a',
      'builtin:mindmap',
      'builtin:smart_summary',
      'custom:off'
    ];
    Prefs().setReadAnySkillEnabled('smart_summary', false);
    ReadingSkillPromptStore.save(
        readAnySkills.singleWhere((s) => s.id == 'mindmap'), 'Changed prompt');
    final chips = configuredReadingSkillChips(const Locale('en'));
    expect(chips.first.label, 'Custom a');
    expect(chips[1].skillId, 'mindmap');
    expect(chips[1].prompt, 'Changed prompt');
    expect(
        chips.any(
            (c) => c.skillId == 'smart_summary' || c.label == 'Custom off'),
        isFalse);
    expect(chips, hasLength(readAnySkills.length));
  });

  test('all skills can be disabled without fallback to other skill collections',
      () {
    for (final skill in readAnySkills)
      Prefs().setReadAnySkillEnabled(skill.id, false);
    Prefs().userPrompts = [customSkill('off', enabled: false)];
    expect(configuredReadingSkillChips(const Locale('zh')), isEmpty);
  });

  test('mixed order and visibility persist across preference reload', () async {
    Prefs().aiReadingSkillsVisible = false;
    Prefs().readAnySkillOrder = ['custom:a', 'builtin:mindmap'];
    await Prefs().initPrefs();
    expect(Prefs().aiReadingSkillsVisible, isFalse);
    expect(Prefs().readAnySkillOrder, ['custom:a', 'builtin:mindmap']);
  });

  test(
      'layout survives global file and modu link import without backing up defaults',
      () async {
    Prefs().aiReadingSkillsVisible = false;
    Prefs().readAnySkillOrder = ['custom:a', 'builtin:mindmap'];
    Prefs().userPrompts = [customSkill('a')];
    final text = await GlobalSettingsTransfer.export(Prefs());
    for (final input in [text, GlobalSettingsTransfer.link(text)]) {
      Prefs().aiReadingSkillsVisible = true;
      Prefs().readAnySkillOrder = [];
      final backup = await GlobalSettingsTransfer.decode(input);
      await GlobalSettingsTransfer.apply(Prefs(), backup);
      expect(Prefs().aiReadingSkillsVisible, isFalse);
      expect(Prefs().readAnySkillOrder, ['custom:a', 'builtin:mindmap']);
      expect(backup['readAnySkillPrompts']['type'], 'reset');
    }
  });

  test('new layout keys belong to the reading skills sync module', () {
    expect(settingsModuleKeys['ai-skills']!.split(RegExp(r'\s+')),
        containsAll(['readAnySkillOrder', 'aiReadingSkillsVisible']));
  });

  for (final order in [
    <String>['bad'],
    ['builtin:'],
    ['builtin:mindmap', 'builtin:mindmap'],
    ['custom:with space']
  ]) {
    test('invalid imported order is rejected: $order', () {
      expect(() => validateSettingsValue('readAnySkillOrder', order),
          throwsFormatException);
    });
  }
}
