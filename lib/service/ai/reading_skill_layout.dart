import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';

/// Stable, namespaced IDs allow custom and built-in skills to share one order.
class ReadingSkillEntry {
  ReadingSkillEntry.builtIn(ReadAnySkill skill)
      : id = 'builtin:${skill.id}',
        builtIn = skill,
        custom = null;
  ReadingSkillEntry.custom(UserPrompt skill)
      : id = 'custom:${skill.id}',
        builtIn = null,
        custom = skill;

  final String id;
  final ReadAnySkill? builtIn;
  final UserPrompt? custom;
}

bool isReadingSkillOrderId(String id) =>
    id.length <= 256 && RegExp(r'^(builtin|custom):[^\s:]+$').hasMatch(id);

List<ReadingSkillEntry> orderedReadingSkills(
    List<UserPrompt> customSkills, List<String> order) {
  final custom = [...customSkills]..sort((a, b) => a.order.compareTo(b.order));
  final entries = <ReadingSkillEntry>[
    for (final skill in readAnySkills) ReadingSkillEntry.builtIn(skill),
    for (final skill in custom) ReadingSkillEntry.custom(skill),
  ];
  final remaining = {for (final entry in entries) entry.id: entry};
  final result = <ReadingSkillEntry>[];
  for (final id in order) {
    final entry = remaining.remove(id);
    if (entry != null) result.add(entry);
  }
  // Deleted/unknown IDs do not hide skills; new skills remain discoverable.
  return [...result, ...remaining.values];
}
