import 'package:anx_reader/service/ai/answer_presentation.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedReasoningEntry tool(String name, String status, {String? error}) =>
    ParsedReasoningEntry.tool(
        ParsedToolStep(name: name, status: status, error: error),
        section: ParsedReasoningSection.answer);

void main() {
  test('routine context cards hidden while loading and when successful', () {
    final entries = [
      for (final name in [
        'current_reading_metadata',
        'current_chapter_content'
      ])
        for (final status in ['running', 'success']) tool(name, status)
    ];
    expect(visibleAnswerTimeline(entries), isEmpty);
    expect(entries, hasLength(4),
        reason: 'Presentation must not mutate history');
  });
  test('failures and errors stay visible', () {
    final entries = [
      tool('current_reading_metadata', 'failed', error: 'unavailable'),
      tool('current_chapter_content', 'success', error: 'partial error')
    ];
    expect(visibleAnswerTimeline(entries), entries);
  });
  test('generated artifacts and actions remain visible', () {
    final entries = [
      for (final name in [
        'mindmap_draw',
        'bookshelf_organize',
        'apply_book_tags'
      ])
        tool(name, 'success')
    ];
    expect(visibleAnswerTimeline(entries), entries);
  });
  test('answer text and legitimate citations are never arbitrarily stripped',
      () {
    const answer = ParsedReasoningEntry.reply('原文出处：《示例》第三章。词义如下。',
        section: ParsedReasoningSection.answer);
    expect(
        visibleAnswerTimeline(
            [tool('current_chapter_content', 'success'), answer]),
        [answer]);
    expect(conciseAnswerGuidance, contains('不输出准备过程'));
    expect(conciseAnswerGuidance, contains('必要来源'));
  });
}
