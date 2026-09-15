import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';

/// Presentation only: never replaces the prompt sent to the model.
/// Exact matching also recognizes older conversations without saved labels.
String? skillMessageLabel(String content, {String? skillId}) {
  final prompt = content.trim();
  if (prompt.isEmpty) return null;
  for (final skill in readAnySkills) {
    if (skill.id == skillId ||
        prompt == skill.defaultPrompt.trim() ||
        prompt == ReadingSkillPromptStore.promptFor(skill).trim()) {
      return skill.name;
    }
  }
  for (final skill in Prefs().userPrompts) {
    if (prompt == skill.content.trim()) return skill.name;
  }
  return null;
}
