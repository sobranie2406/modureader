import 'dart:convert';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/reading_request_snapshot.dart';
import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  for (final policy in readingSkillPolicies.values) {
    test(
        '${policy.id} replays original source and tool policy after history roundtrip',
        () {
      final request = buildReadingSkillRequest(
          policy: policy,
          prompt: '测试技能',
          sourceContent: '原书的序言或选中原文',
          sourceDescription: '原始范围',
          bookTitle: '原书',
          chapterTitle: '序言',
          chapterHref: 'preface.xhtml');
      final entry = AiChatHistoryEntry(
          id: 'fixture',
          scope: 'reader',
          serviceId: 'fake',
          model: 'fake',
          createdAt: 1,
          updatedAt: 1,
          completed: true,
          messages: [ChatMessage.humanText('测试技能'), ChatMessage.ai('旧答案')],
          readingRequest: ReadingRequestSnapshot(
              request: request,
              skillId: policy.id,
              bookId: 1,
              chapterHref: 'preface.xhtml'));
      final restored =
          AiChatHistoryEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())));
      final replay = restored.readingRequest!
          .replay(currentBookId: 99, currentChapterHref: 'other.xhtml');
      expect(replay.messages.map((m) => m.toMap()),
          request.messages.map((m) => m.toMap()));
      expect(replay.useAgent, request.useAgent);
      expect(replay.allowedToolIds, request.allowedToolIds);
      expect(restored.copyWith().readingRequest, isNotNull);
      expect(restored.copyWith(readingRequest: null).readingRequest, isNull);
    });
  }

  test('generic agent replay cannot access a different book or chapter', () {
    final saved = ReadingRequestSnapshot(
        bookId: 1,
        chapterHref: 'preface',
        request: ReadingSkillRequest(
            messages: [ChatMessage.humanText('继续')], useAgent: true));
    expect(() => saved.replay(currentBookId: 2, currentChapterHref: 'preface'),
        throwsStateError);
    expect(() => saved.replay(currentBookId: 1, currentChapterHref: 'chapter2'),
        throwsStateError);
    expect(saved.replay(currentBookId: 1, currentChapterHref: 'preface'),
        same(saved.request));
  });

  test('malformed snapshot preserves conversation but cannot be replayed', () {
    final entry = AiChatHistoryEntry.fromJson({
      'id': 'fixture',
      'scope': 'reader',
      'messages': [ChatMessage.humanText('原问题').toMap()],
      'readingRequest': {'version': 999}
    });
    expect(entry.messages.single.contentAsString, '原问题');
    expect(entry.readingRequest, isNull);
  });
}
