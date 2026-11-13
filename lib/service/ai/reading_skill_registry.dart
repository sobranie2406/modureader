import 'package:modu_reader/service/ai/readany_skills.dart';
import 'package:modu_reader/service/registry/host_registry.dart';
import 'package:flutter/foundation.dart';

/// A reading skill registered with the app.
///
/// Built-in only in P2: plugin prompts already surface as UserPrompt entries
/// and are merged through ReadingSkillEntry.custom, so adding a second plugin
/// contribution kind here would give the same manifest field two meanings.
class ReadingSkillEntry implements RegistryEntry {
  const ReadingSkillEntry({
    required this.skill,
    this.visible = true,
    this.owner = const RegistryOwner.builtIn(),
  });

  final ReadAnySkill skill;

  /// Retired skills stay registered so old conversations still recognise their
  /// prompts, but they are not offered as presets.
  final bool visible;

  @override
  String get id => skill.id;

  @override
  RegistryDomain get domain => RegistryDomain.readingSkill;

  @override
  final RegistryOwner owner;

  @override
  List<String> get aliases => const [];
}

/// Built-in reading skills, their ordering and their retired prompts.
class ReadingSkillRegistry {
  ReadingSkillRegistry(Iterable<ReadingSkillEntry> entries) {
    for (final entry in entries) {
      registry.register(entry);
    }
  }

  /// Production table. Ids are persisted in readAnySkillOrder,
  /// readAnySkillStates and readAnySkillPrompts, so they must never change.
  static final ReadingSkillRegistry instance = ReadingSkillRegistry([
    for (final skill in readAnySkills) ReadingSkillEntry(skill: skill),
    const ReadingSkillEntry(skill: legacyAiKnowledgeSkill, visible: false),
  ]);

  static ReadingSkillRegistry _current = instance;

  static ReadingSkillRegistry get current => _current;

  @visibleForTesting
  static void useForTesting(ReadingSkillRegistry registry) => _current = registry;

  @visibleForTesting
  static void resetForTesting() => _current = instance;

  final HostRegistry<ReadingSkillEntry> registry =
      HostRegistry<ReadingSkillEntry>(RegistryDomain.readingSkill);

  ReadingSkillEntry? entry(String id) => registry.resolve(id);

  /// Skills offered in the UI, in registration order.
  List<ReadAnySkill> get visibleSkills => [
        for (final entry in registry.all)
          if (entry.visible && entry.owner is BuiltInOwner) entry.skill,
      ];

  /// Every known definition, including retired ones. Prompt recognition must
  /// keep matching old conversations, so this is a superset of visibleSkills.
  List<ReadAnySkill> get promptDefinitions => [
        for (final entry in registry.all)
          if (entry.owner is BuiltInOwner) entry.skill,
      ];
}
