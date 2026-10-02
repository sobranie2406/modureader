import 'dart:convert';

import 'package:anx_reader/l10n/modu_catalogs.g.dart';
import 'package:anx_reader/service/ai/dictionary_confirmation.dart';
import 'package:anx_reader/service/ai/reading_request_snapshot.dart';
import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  for (final entry in moduCatalogs.entries) {
    final command = entry.value['ui_dictionary_web_confirm_command']!;
    test('${entry.key} typed confirmation matches its displayed instruction',
        () {
      expect(isDictionaryWebConfirmation(command), true);
      expect(isDictionaryWebConfirmation(' $command。 '), true);
      expect(entry.value['ui_dictionary_web_follow_up'], contains(command));
      // The persistent hint owns consent instructions; bundled task prompts
      // stay concise and do not repeat the UI's follow-up instructions.
      expect(entry.value['skill_ai_dictionary_prompt']!.length, lessThan(500));
      expect(entry.value['selection_custom-preset-dictionary_prompt'],
          contains('{selection}'));
    });
  }
  for (final text in [
    '',
    '不用联网搜索',
    '不确认联网搜索',
    '确认联网搜索？',
    '“确认联网搜索”',
    '这句话是什么意思：确认联网搜索',
    '是否需要确认联网搜索',
    '确认联网搜索并发送全书'
  ]) {
    test('does not infer consent from $text', () {
      expect(isDictionaryWebConfirmation(text), false);
    });
  }
  for (final skillId in [aiDictionarySkillId, aiDictionaryWebSkillId]) {
    test('$skillId history roundtrip recovers only original selected term', () {
      final snapshot = ReadingRequestSnapshot(
          skillId: skillId,
          bookId: 1,
          chapterHref: 'private-chapter',
          request: buildReadingSkillRequest(
              policy: readingSkillPolicyFor(skillId)!,
              prompt: '解释词语',
              sourceContent: '师利',
              sourceDescription: 'private-description',
              bookTitle: 'private-book'));
      final restored = ReadingRequestSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())));
      expect(dictionarySelectionFromRequest(restored), '师利');
      expect(restored.request.useAgent, false);
    });
  }
  test('does not guess missing words from chat or chapter contents', () {
    expect(dictionarySelectionFromRequest(null), isNull);
    for (final skillId in [
      null,
      selectionToolbarSkillId,
      aiDictionarySkillId
    ]) {
      final snapshot = ReadingRequestSnapshot(
          skillId: skillId,
          request: ReadingSkillRequest(
              messages: [ChatMessage.humanText('whole chapter')],
              useAgent: false));
      expect(dictionarySelectionFromRequest(snapshot), isNull);
    }
    for (final text in ['待解释词语：{bad json', '待解释词语：42', '待解释词语：" "']) {
      expect(
          dictionarySelectionFromRequest(ReadingRequestSnapshot(
              skillId: aiDictionarySkillId,
              request: ReadingSkillRequest(
                  messages: [ChatMessage.humanText(text)], useAgent: false))),
          isNull);
    }
  });
}
