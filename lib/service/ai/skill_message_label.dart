import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'dart:ui';
import 'package:anx_reader/l10n/modu_strings.dart';

/// Presentation only: never replaces the prompt sent to the model.
/// Exact matching also recognizes older conversations without saved labels.
String? skillMessageLabel(String content, {String? skillId, Locale? locale}) {
  final language = locale ?? Prefs().effectiveLocale;
  final prompt = content.trim();
  if (prompt.isEmpty) return null;
  if (skillId == 'selection_toolbar')
    return ModuStrings.label(language, '划词 AI', 'Selection AI');
  for (final skill in readingSkillPromptDefinitions) {
    if (skill.id == skillId ||
        skill.isDefaultPrompt(prompt) ||
        prompt == ReadingSkillPromptStore.promptFor(skill).trim()) {
      return skill.localizedName(language);
    }
  }
  for (final skill in Prefs().userPrompts) {
    if (prompt == skill.content.trim()) return skill.name;
  }
  return null;
}
