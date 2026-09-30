import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'dart:ui';

/// Keeps built-in reading skills and the existing AI prompt settings backed by
/// one source of truth, so edits are reflected everywhere the prompt is used.
class ReadingSkillPromptStore {
  const ReadingSkillPromptStore._();

  static String promptFor(ReadAnySkill skill, {Locale? locale}) {
    final aiPrompt = skill.aiPrompt;
    if (aiPrompt != null) return Prefs().getAiPrompt(aiPrompt, locale: locale);
    final saved = Prefs().readAnySkillPrompts[skill.id];
    return saved == null || saved.trim().isEmpty || skill.isDefaultPrompt(saved)
        ? skill.localizedPrompt(locale ?? Prefs().effectiveLocale)
        : saved;
  }

  static void save(ReadAnySkill skill, String prompt) {
    final aiPrompt = skill.aiPrompt;
    if (aiPrompt != null) {
      Prefs().saveAiPrompt(aiPrompt, prompt);
      return;
    }
    Prefs().setReadAnySkillPrompt(skill.id, prompt);
  }

  static void reset(ReadAnySkill skill) {
    final aiPrompt = skill.aiPrompt;
    if (aiPrompt != null) {
      Prefs().deleteAiPrompt(aiPrompt);
      return;
    }
    Prefs().resetReadAnySkillPrompt(skill.id);
  }
}
