import 'package:anx_reader/service/ai/home_ai_execution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  group('home AI scope', () {
    test('never exposes reader-only tools', () {
      expect(
        homeAiToolIds,
        isNot(containsAll({
          'current_reading_metadata',
          'current_book_toc',
          'current_chapter_content',
          'chapter_content_by_href',
        })),
      );
    });

    test('covers every fixed home action', () {
      expect(homeAiPromptPolicies.keys, {
        homePromptRecentBooks,
        homePromptLatestSession,
        homePromptHighestProgress,
        homePromptYesterdayNotes,
        homePromptUnreadBooks,
        homePromptRecommendRecent,
        homePromptTodayHighlights,
        homePromptWeeklyReadingTime,
        homePromptNoteQuote,
        homePromptReadNext,
        homePromptOrganizeByGenre,
        homePromptOrganizeByProgress,
      });
    });

    test('fixed actions can only call tools relevant to their data scope', () {
      expect(
        homeAiPromptPolicies[homePromptLatestSession]!.allowedToolIds,
        {'reading_history'},
      );
      expect(
        homeAiPromptPolicies[homePromptYesterdayNotes]!.allowedToolIds,
        {'current_time', 'notes_search'},
      );
      expect(
        homeAiPromptPolicies[homePromptHighestProgress]!.allowedToolIds,
        {'bookshelf_lookup'},
      );
      expect(
        homeAiPromptPolicies[homePromptOrganizeByProgress]!.allowedToolIds,
        {'bookshelf_lookup', 'bookshelf_organize'},
      );
    });

    test('request explicitly rejects stale reader context', () {
      final request = buildHomeAiRequest(
        conversation: [ChatMessage.humanText('接下来读什么？')],
        promptId: homePromptReadNext,
      );

      expect(request.useAgent, isTrue);
      expect(request.messages, hasLength(2));
      expect(request.messages.first, isA<SystemChatMessage>());
      expect(
        request.messages.first.contentAsString,
        contains('not in the reader'),
      );
      expect(
        request.messages.first.contentAsString,
        contains('Never treat the last opened book'),
      );
      expect(
        request.messages.first.contentAsString,
        contains('must come from an available tool'),
      );
      expect(request.messages.last.contentAsString, '接下来读什么？');
      expect(
        request.allowedToolIds,
        homeAiPromptPolicies[homePromptReadNext]!.allowedToolIds,
      );
    });
  });
}
