import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/service/ai/reading_skill_layout.dart';
import 'package:anx_reader/service/ai/reading_skill_prompt_store.dart';
import 'package:flutter/material.dart';

IconData readingSkillIcon(String id) => switch (id) {
      'smart_summary' => Icons.summarize_outlined,
      'book_summary' => Icons.menu_book_rounded,
      'concept_explainer' => Icons.lightbulb_outline,
      'argument_analyzer' => Icons.account_tree_outlined,
      'character_tracker' => Icons.groups_outlined,
      'quote_collector' => Icons.format_quote_outlined,
      'reading_guide' => Icons.explore_outlined,
      'smart_translator' => Icons.translate_outlined,
      'vocabulary_helper' => Icons.spellcheck_outlined,
      'ai_dictionary' => Icons.menu_book_outlined,
      'mindmap' => Icons.account_tree_outlined,
      _ => Icons.extension_outlined,
    };

List<AiQuickPromptChip> configuredReadingSkillChips(Locale locale) {
  final prefs = Prefs();
  final chips = <AiQuickPromptChip>[];
  for (final entry
      in orderedReadingSkills(prefs.userPrompts, prefs.readAnySkillOrder)) {
    if (entry.builtIn case final skill?) {
      if (prefs.isReadAnySkillEnabled(skill.id)) {
        chips.add(AiQuickPromptChip(
          icon: readingSkillIcon(skill.id),
          label: skill.localizedName(locale),
          prompt: ReadingSkillPromptStore.promptFor(skill, locale: locale),
          skillId: skill.id,
        ));
      }
    } else if (entry.custom case final skill?) {
      if (skill.enabled) {
        chips.add(AiQuickPromptChip(
            icon: Icons.person_outline,
            label: skill.name,
            prompt: skill.content));
      }
    }
  }
  return chips;
}
