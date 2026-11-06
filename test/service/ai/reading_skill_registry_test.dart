import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_registry.dart';
import 'package:anx_reader/service/registry/host_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ReadingSkillRegistry.resetForTesting);

  test('built-in ids are frozen', () {
    expect(
      ReadingSkillRegistry.instance.visibleSkills.map((skill) => skill.id).toSet(),
      {
        'smart_summary',
        'book_summary',
        'concept_explainer',
        'argument_analyzer',
        'character_tracker',
        'quote_collector',
        'reading_guide',
        'smart_translator',
        'vocabulary_helper',
        'mindmap',
      },
    );
    expect(ReadingSkillRegistry.instance.visibleSkills, hasLength(10));
    expect(
      ReadingSkillRegistry.instance.visibleSkills.map((skill) => skill.id),
      readAnySkills.map((skill) => skill.id),
      reason: 'registration order drives the default UI order',
    );
  });

  test('retired skills stay recognised but hidden', () {
    final registry = ReadingSkillRegistry.instance;
    expect(registry.visibleSkills.map((skill) => skill.id),
        isNot(contains(legacyAiKnowledgeSkill.id)));
    expect(registry.promptDefinitions.map((skill) => skill.id),
        contains(legacyAiKnowledgeSkill.id));
    expect(registry.entry(legacyAiKnowledgeSkill.id)?.visible, isFalse);
    expect(registry.promptDefinitions, hasLength(readAnySkills.length + 1));
  });

  test('resolves a skill by id and reports unknown ids as null', () {
    final registry = ReadingSkillRegistry.instance;
    expect(registry.entry('mindmap')?.skill.name, isNotEmpty);
    expect(registry.entry('removed_by_a_newer_version'), isNull);
  });

  test('a substituted registry is what production reads', () {
    final custom = ReadingSkillRegistry([
      const ReadingSkillEntry(
        skill: ReadAnySkill(id: 'custom_one', name: 'One', description: 'd', prompt: 'p'),
      ),
    ]);
    ReadingSkillRegistry.useForTesting(custom);
    expect(ReadingSkillRegistry.current.visibleSkills.single.id, 'custom_one');
    ReadingSkillRegistry.resetForTesting();
    expect(ReadingSkillRegistry.current.visibleSkills, hasLength(10));
  });

  test('entries declare the readingSkill domain and a built-in owner', () {
    final entry = ReadingSkillRegistry.instance.entry('mindmap')!;
    expect(entry.domain, RegistryDomain.readingSkill);
    expect(entry.owner, const RegistryOwner.builtIn());
    expect(entry.aliases, isEmpty);
  });
}
