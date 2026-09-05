import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  group('reading skill policies', () {
    test('cover every built-in reading skill', () {
      expect(
        readingSkillPolicies.keys.toSet(),
        readAnySkills.map((skill) => skill.id).toSet(),
      );
    });

    test('assign safe source scopes to specialized skills', () {
      expect(
        readingSkillPolicies[bookSummarySkillId]!.scope,
        ReadingSkillSourceScope.wholeBook,
      );
      expect(
        readingSkillPolicies[characterTrackerSkillId]!.scope,
        ReadingSkillSourceScope.throughCurrentPosition,
      );
      expect(
        readingSkillPolicies[smartTranslatorSkillId]!.scope,
        ReadingSkillSourceScope.selectionRequired,
      );
      expect(
        readingSkillPolicies[quoteCollectorSkillId]!.scope,
        ReadingSkillSourceScope.selectionOrCurrentChapter,
      );
    });

    test('only mind maps may invoke their dedicated rendering tool', () {
      for (final policy in readingSkillPolicies.values) {
        if (policy.id == mindmapSkillId) {
          expect(policy.useAgent, isTrue);
          expect(policy.allowedToolIds, {'mindmap_draw'});
        } else {
          expect(policy.useAgent, isFalse);
          expect(policy.allowedToolIds, isNull);
        }
      }
    });
  });

  group('current chapter summary request', () {
    test('contains only the exact chapter context and current prompt', () {
      final messages = buildCurrentChapterSummaryMessages(
        prompt: '总结当前章节',
        chapterContent: '序\n这是序言正文。',
        bookTitle: '测试书籍',
        chapterTitle: '序',
        chapterHref: 'Text/preface.xhtml',
      );

      expect(messages, hasLength(2));
      expect(messages.first, isA<SystemChatMessage>());
      expect(messages.last, isA<HumanChatMessage>());
      expect(messages.first.contentAsString, contains('书名：测试书籍'));
      expect(messages.first.contentAsString, contains('当前章节：序'));
      expect(
        messages.first.contentAsString,
        contains('章节位置：Text/preface.xhtml'),
      );
      expect(messages.first.contentAsString, contains('这是序言正文。'));
      expect(messages.first.contentAsString, contains('唯一允许使用'));
      expect(messages.last.contentAsString, '总结当前章节');
    });

    test('rejects an empty chapter instead of allowing a hallucinated answer',
        () {
      expect(
        () => buildCurrentChapterSummaryMessages(
          prompt: '总结当前章节',
          chapterContent: '   ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('scoped skill request', () {
    test('isolates selected text from previous chat and other chapters', () {
      final request = buildReadingSkillRequest(
        policy: readingSkillPolicies[conceptExplainerSkillId]!,
        prompt: '解析概念',
        sourceContent: '只允许分析这一段。',
        sourceDescription: '用户选中的原文',
        chapterTitle: '序',
      );

      expect(request.messages, hasLength(2));
      expect(request.useAgent, isFalse);
      expect(request.messages.first.contentAsString, contains('只允许分析这一段'));
      expect(request.messages.first.contentAsString, contains('不得使用其他章节补全'));
      expect(request.messages.last.contentAsString, '解析概念');
    });

    test('falls back to markdown when the mind-map tool is disabled', () {
      final request = buildReadingSkillRequest(
        policy: readingSkillPolicies[mindmapSkillId]!,
        prompt: '生成导图',
        sourceContent: '第一点。第二点。',
        sourceDescription: '当前章节正文',
        agentAvailable: false,
      );

      expect(request.useAgent, isFalse);
      expect(request.allowedToolIds, {'mindmap_draw'});
    });
  });
}
