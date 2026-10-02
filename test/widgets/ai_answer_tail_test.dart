import 'dart:convert';

import 'package:anx_reader/service/ai/coalesced_stream.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langchain/langchain.dart';
import 'package:langchain_openai/langchain_openai.dart';

void main() {
  const answer = '## 释义\n指用于办公的屋子（在“办公室”一词中）。\n\n'
      '## 百科\n在古代汉语中，“室”本指堂后之室（内室），与“堂”相对，后来泛指所有房屋或房间。';
  test(
      'SSE through runner and coalescing preserves every final Chinese character',
      () async {
    for (final chunkSize in [1, 6, 17, answer.length]) {
      final events = StringBuffer();
      for (var offset = 0; offset < answer.length; offset += chunkSize) {
        events.writeln('data: ${jsonEncode({
              'id': 'tail-test',
              'object': 'chat.completion.chunk',
              'created': 1,
              'model': 'fixture',
              'choices': [
                {
                  'index': 0,
                  'delta': {
                    'content': answer.substring(
                        offset, (offset + chunkSize).clamp(0, answer.length)),
                  },
                  'finish_reason': null
                }
              ],
            })}\n');
      }
      events.write('data: [DONE]\n\n');
      final model = ChatOpenAI(
          apiKey: 'fixture',
          client: MockClient((_) async => http.Response(events.toString(), 200,
              headers: {'content-type': 'text/event-stream; charset=utf-8'})));
      final snapshots =
          await coalesceSnapshots(CancelableLangchainRunner().stream(
        model: model,
        prompt: PromptValue.string('Explain'),
      )).toList();
      expect(splitReasoningEnvelope(snapshots.last).answerContent, answer);
    }
  });

  testWidgets('streamed multiline Markdown keeps the full last sentence',
      (tester) async {
    late StateSetter update;
    var content = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: SizedBox(
          width: 330,
          child: StatefulBuilder(builder: (context, setState) {
            update = setState;
            return StyledMarkdown(data: content, fontSize: 18);
          })),
    ))));
    for (var end = 1; end <= answer.length; end++) {
      update(() => content = answer.substring(0, end));
      await tester.pump();
    }
    final rendered = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join();
    expect(rendered, contains('后来泛指所有房屋或房间。'));
    expect(tester.takeException(), isNull);
  });

  for (final agent in [false, true]) {
    test('long reasoning response retains its tail (agent=$agent)', () async {
      final longAnswer = '${'相关知识与释义。\n\n' * 600}$answer';
      String event(Map<String, Object?> delta, [String? finish]) =>
          'data: ${jsonEncode({
                'id': 'tail-test',
                'object': 'chat.completion.chunk',
                'created': 1,
                'model': 'fixture',
                'choices': [
                  {'index': 0, 'delta': delta, 'finish_reason': finish}
                ]
              })}\n\n';
      final wire = [
        event({'reasoning_content': '思考内容。'}),
        event({'content': longAnswer.substring(0, longAnswer.length - 6)}),
        event({'content': longAnswer.substring(longAnswer.length - 6)}, 'stop'),
        'data: [DONE]\n\n',
      ].join();
      final model = ChatOpenAI(
          apiKey: 'fixture',
          client: MockClient.streaming((_, __) async => http.StreamedResponse(
              Stream.fromIterable(utf8.encode(wire).map((byte) => [byte])), 200,
              headers: {'content-type': 'text/event-stream'})));
      final runner = CancelableLangchainRunner();
      final stream = agent
          ? runner.streamAgent(
              model: model, tools: [], history: [], input: 'Explain')
          : runner.stream(model: model, prompt: PromptValue.string('Explain'));
      final snapshots = await coalesceSnapshots(stream).toList();
      final parsed = parseReasoningContent(snapshots.last);
      // Direct reasoning envelopes insert a separator newline before the reply.
      expect(
          parsed.answerTimeline
              .map((entry) => entry.text ?? '')
              .join()
              .trimLeft(),
          longAnswer);
      expect(parsed.reasoningTimeline.map((entry) => entry.text ?? '').join(),
          '思考内容。');
    });
  }
}
