import 'dart:convert';
import 'package:anx_reader/service/ai/dictionary_lookup.dart';
import 'package:anx_reader/service/ai/dictionary_web_search.dart';
import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:anx_reader/service/ai/reading_request_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final id in [
    'selection_toolbar',
    'ai_dictionary',
    'concept_explainer',
    'smart_translator',
    'vocabulary_helper',
    'mindmap'
  ]) {
    for (final withContext in [false, true]) {
      test('$id honors selection scope ($withContext) without book metadata',
          () {
        final request = buildReadingSkillRequest(
          policy: readingSkillPolicyFor(id)!,
          prompt: 'Explain clearly',
          sourceContent: 'bank',
          sourceDescription: 'private source',
          bookTitle: 'private book',
          chapterTitle: 'private chapter',
          chapterHref: 'private.xhtml',
          responseLanguage: 'zh-CN',
          selectionRequest: true,
          selectionContext:
              withContext ? 'She sat beside the river bank.' : null,
        );
        final all = request.messages.map((m) => m.contentAsString).join('\n');
        expect(all, isNot(contains('private')));
        expect(all.contains('river bank'), withContext);
        expect(request.selectionText, 'bank');
        expect(request.webSearch, false);
        expect(request.useAgent, id == 'mindmap');
        if (id == 'ai_dictionary') {
          expect(all, contains('使用选中文字的语言回答'));
          expect(all, isNot(contains('Default response language: zh-CN')));
        }
      });
    }
  }
  test('context is bounded and never cuts a surrogate pair', () {
    expect(boundedSelectionContext(' '), isNull);
    expect(boundedSelectionContext('${'a' * 599}😀tail'), 'a' * 599);
    expect(boundedSelectionContext('a' * 800)?.length, 600);
  });
  test('history preserves scope, selection and web setting for regeneration',
      () {
    final request = buildReadingSkillRequest(
      policy: readingSkillPolicyFor('ai_dictionary')!,
      prompt: 'Knowledge',
      sourceContent: 'bank',
      sourceDescription: 'selection',
      selectionContext: 'river bank',
      webSearch: true,
    );
    final saved =
        ReadingRequestSnapshot(request: request, skillId: 'ai_dictionary');
    final restored =
        ReadingRequestSnapshot.fromJson(jsonDecode(jsonEncode(saved.toJson())));
    expect(restored.request.selectionText, 'bank');
    expect(restored.request.selectionContext, 'river bank');
    expect(restored.request.webSearch, true);
    expect(restored.replay().messages.map((m) => m.toMap()),
        request.messages.map((m) => m.toMap()));
  });
  test(
      'custom online task searches selection only and keeps task and context for AI',
      () async {
    final request = buildReadingSkillRequest(
      policy: readingSkillPolicyFor('selection_toolbar')!,
      prompt: 'Find related concepts',
      sourceContent: 'bank',
      sourceDescription: 'selection',
      selectionContext: 'private river context',
      webSearch: true,
      selectionRequest: true,
    );
    var searches = 0, calls = 0;
    final result = await dictionaryWebLookup(
      messages: request.messages,
      selectedText: request.selectionText,
      search: (query) async {
        searches++;
        expect(query, 'bank');
        return DictionarySearchResult([
          DictionarySearchHit('bank', 'A river edge',
              Uri.parse('https://en.wikipedia.org/wiki/Bank'))
        ]);
      },
      generate: (messages) {
        calls++;
        final all = messages.map((m) => m.contentAsString).join();
        expect(all, contains('Find related concepts'));
        expect(all, contains('private river context'));
        expect(all, contains('A river edge'));
        return Stream.value('Related concepts [1]');
      },
      isCancelled: () => false,
    ).toList();
    expect(searches, 1);
    expect(calls, 1);
    expect(result.last, contains('https://en.wikipedia.org/wiki/Bank'));
  });

  test(
      'unavailable optional search still completes the custom model task honestly',
      () async {
    var calls = 0;
    final request = buildReadingSkillRequest(
      policy: readingSkillPolicyFor('selection_toolbar')!,
      prompt: 'Summarize',
      sourceContent: 'Selected passage',
      sourceDescription: 'selection',
      webSearch: true,
    );
    final result = await dictionaryWebLookup(
      messages: request.messages,
      selectedText: request.selectionText,
      search: (_) async => const DictionarySearchResult([], hasFailures: true),
      generate: (input) {
        calls++;
        final all = input.map((m) => m.contentAsString).join();
        expect(all, contains('暂时不可用'));
        expect(all, contains('不编造来源'));
        expect(all, contains('Summarize'));
        return Stream.value('Search unavailable. Summary from supplied text.');
      },
      isCancelled: () => false,
    ).toList();
    expect(calls, 1);
    expect(result.single, contains('Summary'));
    expect(result.single, isNot(contains('https://')));
  });
}
