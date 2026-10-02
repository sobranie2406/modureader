import 'dart:convert';

import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';

/// Strip bundled prompt text from a portable snapshot, not from live settings.
/// Null means use the receiving application's built-in default. Unknown IDs
/// and all user-created skills remain unchanged for forward compatibility.
Object? readingPromptOverride(String key, Object? value) {
  if (value is! String) return value;
  for (final prompt in AiPrompts.values) {
    if (key == 'aiPrompt_${prompt.name}') {
      return prompt.isDefaultPrompt(value) ? null : value;
    }
  }
  if (key != 'readAnySkillPrompts') return value;
  try {
    final raw = jsonDecode(value);
    if (raw is! Map || raw.values.any((v) => v is! String)) return value;
    final overrides = Map<String, dynamic>.from(raw);
    for (final skill in readingSkillPromptDefinitions) {
      final saved = overrides[skill.id] as String?;
      if (saved != null && skill.isDefaultPrompt(saved)) {
        overrides.remove(skill.id);
      }
    }
    return overrides.isEmpty ? null : jsonEncode(overrides);
  } catch (_) {
    return value; // Validation, rather than export, rejects malformed data.
  }
}
