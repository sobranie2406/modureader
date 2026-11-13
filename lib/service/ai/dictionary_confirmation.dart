import 'dart:convert';

import 'package:modu_reader/l10n/modu_catalogs.g.dart';
import 'package:modu_reader/service/ai/reading_request_snapshot.dart';
import 'package:modu_reader/service/ai/reading_skill_execution.dart';
import 'package:langchain_core/chat_models.dart';

/// Only a standalone user confirmation authorizes retrieval. Never infer consent
/// from a model answer, a quoted phrase, or a substring in an ordinary question.
bool isDictionaryWebConfirmation(String message) {
  final command =
      message.trim().replaceFirst(RegExp(r'[。.!！]+$'), '').trim().toLowerCase();
  return command == '确认联网搜索' ||
      moduCatalogs.values.any((catalog) =>
          catalog['ui_dictionary_web_confirm_command']?.toLowerCase() ==
          command);
}

/// Recover the original term from the saved request, not the currently selected
/// book text or ephemeral popup fields. Works after reopening and history replay.
String? dictionarySelectionFromRequest(ReadingRequestSnapshot? snapshot) {
  if (snapshot == null ||
      (snapshot.skillId != aiDictionarySkillId &&
          snapshot.skillId != aiDictionaryWebSkillId)) {
    return null;
  }
  final selection = snapshot.request.selectionText?.trim();
  if (selection != null && selection.isNotEmpty) return selection;
  final messages = snapshot.request.messages.whereType<HumanChatMessage>();
  if (messages.isEmpty) return null;
  const prefix = '待解释词语：';
  final text = messages.last.contentAsString;
  if (!text.startsWith(prefix)) return null;
  try {
    final term = jsonDecode(text.substring(prefix.length));
    return term is String && term.trim().isNotEmpty ? term.trim() : null;
  } on FormatException {
    return null;
  }
}
