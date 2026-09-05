import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  test('AI history persists its home or reader scope', () {
    final entry = AiChatHistoryEntry(
      id: 'reader-session',
      scope: 'reader',
      serviceId: 'deepseek',
      model: 'deepseek-v4-flash',
      createdAt: 1,
      updatedAt: 2,
      messages: [ChatMessage.humanText('总结本章')],
      completed: true,
      homePromptId: 'read_next',
    );

    final restored = AiChatHistoryEntry.fromJson(entry.toJson());
    expect(restored.scope, 'reader');
    expect(restored.serviceId, 'deepseek');
    expect(restored.model, 'deepseek-v4-flash');
    expect(restored.homePromptId, 'read_next');
    expect(restored.copyWith(homePromptId: null).homePromptId, isNull);
  });

  test('legacy unscoped history stays in the library instead of the reader',
      () {
    final restored = AiChatHistoryEntry.fromJson({
      'id': 'legacy-session',
      'serviceId': 'openai',
      'model': 'gpt-4o-mini',
      'createdAt': 1,
      'updatedAt': 2,
      'messages': <Map<String, dynamic>>[],
      'completed': true,
    });

    expect(restored.scope, 'library');
  });

  test('legacy reading-skill history is migrated into the reader scope', () {
    final restored = AiChatHistoryEntry.fromJson({
      'id': 'legacy-reader-session',
      'serviceId': 'deepseek',
      'model': 'deepseek-v4-flash',
      'createdAt': 1,
      'updatedAt': 2,
      'messages': [
        ChatMessage.humanText(readAnySkills.first.defaultPrompt).toMap(),
      ],
      'completed': true,
    });

    expect(restored.scope, 'reader');
  });

  test('older short reader prompts are also migrated', () {
    final restored = AiChatHistoryEntry.fromJson({
      'id': 'older-reader-session',
      'serviceId': 'openai',
      'model': 'gpt-4o-mini',
      'createdAt': 1,
      'updatedAt': 2,
      'messages': [
        ChatMessage.humanText(
          '请整理当前内容涉及的人物，说明身份、关系和关键行为。',
        ).toMap(),
      ],
      'completed': true,
    });

    expect(restored.scope, 'reader');
  });
}
