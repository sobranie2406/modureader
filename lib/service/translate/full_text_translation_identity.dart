import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';

import 'classical_translation.dart';
import 'index.dart';

String fullTextTranslationIdentity({
  ClassicalTranslation? classical,
  TranslateServiceProvider? provider,
}) {
  if (classical != null) return 'classical/${classical.identity}';

  final prefs = Prefs();
  final service = prefs.fullTextTranslateService;
  final selected = provider ?? service.provider;
  final aiId = selected.service == TranslateService.ai
      ? prefs.translationAiService
      : null;
  final aiProvider = aiId == null
      ? null
      : prefs
          .getAiProviders()
          .whereType<Map>()
          .where((item) => item['id'] == aiId)
          .firstOrNull;
  final aiConfig = aiId == null
      ? null
      : aiProvider == null
          ? prefs.getAiConfig(aiId)
          : (Map<String, dynamic>.from(aiProvider)
            ..remove('keyIndex')
            ..remove('updatedAt'));
  return sha256
      .convert(utf8.encode(jsonEncode([
        service.name,
        selected.service.name,
        prefs.fullTextTranslateFrom.code,
        prefs.fullTextTranslateTo.code,
        selected.getConfig(),
        if (aiId != null)
          [aiId, aiConfig, prefs.aiTemperature, prefs.aiMaxTokens],
      ])))
      .toString();
}
