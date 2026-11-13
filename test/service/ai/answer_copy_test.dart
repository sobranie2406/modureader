import 'dart:convert';

import 'package:modu_reader/utils/ai_reasoning_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';

void main() {
  test('copy excludes think envelope but preserves answer Markdown', () {
    final parsed = parseReasoningContent('<think>思考过程</think>\n# 正文\n\n**结论**');
    expect(parsed.copyableAnswer, '# 正文\n\n**结论**');
  });

  test('structured reasoning is excluded from clipboard text', () {
    final content = chatMessageDisplayContent(
        const AIChatMessage(content: '最终答案', reasoningContent: '单独的思考字段'));
    expect(parseReasoningContent(content).copyableAnswer, '最终答案');
  });

  test('copy excludes encoded thinking blocks and tool payloads', () {
    final thought = base64Encode(utf8.encode('不复制的思考'));
    final parsed = parseReasoningContent("<think-block text_b64='$thought'/>"
        "<tool-step name='search' status='done' output='tool output'/>"
        "<reply text='${Uri.encodeComponent('第一段')}'/><reply text='${Uri.encodeComponent('第二段')}'/>");
    expect(parsed.copyableAnswer, '第一段\n\n第二段');
  });

  test('thought-only and tool-only replies never fall back to raw content', () {
    for (final text in [
      '',
      '<think>只有思考</think>',
      "<tool-step name='search' status='done' output='tool output'/>"
    ]) {
      expect(parseReasoningContent(text).copyableAnswer, isEmpty);
    }
  });

  test('plain responses remain copyable', () {
    expect(parseReasoningContent('普通正文').copyableAnswer, '普通正文');
  });
}
