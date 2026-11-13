import 'dart:convert';
import 'dart:io';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/ai_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/current_reading_state.dart';
import 'package:modu_reader/providers/ai_chat.dart';
import 'package:modu_reader/providers/ai_history.dart';
import 'package:modu_reader/providers/current_reading.dart';
import 'package:modu_reader/service/ai/ai_history.dart';
import 'package:modu_reader/service/ai/reading_request_snapshot.dart';
import 'package:modu_reader/service/ai/reading_skill_execution.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  for (final scope in [AiChatScope.knowledge, AiChatScope.reader]) {
    testWidgets(
        '${scope.name} knowledge never retrieves books on follow-up, restore or retry',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      const provider = AiProvider(
          id: 'fixture',
          title: 'Fixture',
          url: 'https://example.test/v1',
          protocol: AiProtocol.openai,
          model: 'GLM-4-Flash',
          apiKeys: [AiApiKey(id: 'test', key: 'fake')]);
      Prefs().saveAiProviders([provider]);
      Prefs().selectedAiService = provider.id;
      Prefs().enabledAiToolIds = [
        'book_content_search',
        'bookshelf_lookup',
        'reading_history'
      ];
      final dir =
          Directory.systemTemp.createTempSync('modu-knowledge-boundary-');
      final paths = PathProviderPlatform.instance;
      final document = documentPath;
      PathProviderPlatform.instance = _Paths(dir.path);
      documentPath = dir.path;
      final container = ProviderContainer();
      addTearDown(() {
        container.dispose();
        PathProviderPlatform.instance = paths;
        documentPath = document;
        dir.deleteSync(recursive: true);
      });
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: Consumer(builder: (context, widgetRef, _) {
            ref = widgetRef;
            return const SizedBox();
          })));
      await tester.runAsync(() async {
        await container.read(aiChatProvider(scope).future);
        await container.read(aiHistoryProvider.notifier).refresh();
        container.read(currentReadingProvider.notifier).start(
            CurrentReadingState(
                book: Book.mock().copyWith(title: 'PRIVATE_BOOK_SENTINEL'),
                chapterHref: 'private-chapter'));
        final chat = container.read(aiChatProvider(scope).notifier);
        final requests = <Map<String, dynamic>>[];
        await http.runWithClient(() async {
          await chat
              .sendMessageStream('解释孝宗', ref, false,
                  skillId: aiDictionarySkillId, sourceText: '孝宗')
              .toList();
          final id = chat.currentSessionId;
          await chat.sendMessageStream('还有哪些同名皇帝？', ref, false).toList();
          expect(chat.currentDictionarySelection, '孝宗');
          final saved = (await AiHistoryStore.readHistory()).single;
          expect(saved.effectiveHistoryKey, 'skill.ai_dictionary');
          expect(saved.readingRequest!.request.useAgent, false);
          expect(saved.readingRequest!.request.allowedToolIds, isEmpty);
          chat.clear();
          chat.loadHistoryEntry(AiChatHistoryEntry.fromJson(saved.toJson()));
          await chat.sendMessageStream('分别生活在哪些年代？', ref, false).toList();
          await chat.sendMessageStream('分别生活在哪些年代？', ref, true).toList();
          expect(chat.currentSessionId, id);
          expect((await AiHistoryStore.readHistory()).single.messages,
              hasLength(6));
          expect(requests, hasLength(4));
          for (final request in requests) {
            expect(request['tools'], anyOf(isNull, isEmpty));
            expect(
                jsonEncode(request), isNot(contains('PRIVATE_BOOK_SENTINEL')));
            expect(jsonEncode(request), contains('孝宗'));
          }
          expect(jsonEncode(requests[2]), contains('还有哪些同名皇帝'));
          expect(requests[2]['messages'], requests[3]['messages']);
          final legacy = saved.toJson()..remove('historyKey');
          legacy['skillLabels'] = {'0': 'AI 知识'};
          legacy['readingRequest'] = ReadingRequestSnapshot(
              bookId: 999,
              chapterHref: 'old-book',
              request: ReadingSkillRequest(useAgent: true, messages: [
                ChatMessage.system('PRIVATE_BOOK_SENTINEL'),
                ChatMessage.humanText('旧追问')
              ])).toJson();
          chat.clear();
          chat.loadHistoryEntry(AiChatHistoryEntry.fromJson(legacy));
          await chat.sendMessageStream('旧追问', ref, true).toList();
          expect(requests.last['tools'], anyOf(isNull, isEmpty));
          expect(jsonEncode(requests.last),
              isNot(contains('PRIVATE_BOOK_SENTINEL')));
          // A local legacy snapshot cannot re-enable tools in the knowledge scope.
          if (scope == AiChatScope.knowledge) {
            chat.clear();
            chat.loadHistoryEntry(saved.copyWith(
                readingRequest: ReadingRequestSnapshot(
                    skillId: aiDictionarySkillId,
                    request: ReadingSkillRequest(
                        messages: saved.readingRequest!.request.messages,
                        useAgent: true,
                        allowedToolIds: {'book_content_search'}))));
            await chat.sendMessageStream('重试', ref, true).toList();
            expect(requests.last['tools'], anyOf(isNull, isEmpty));
          }
          if (scope == AiChatScope.reader) {
            chat.clear();
            chat.loadHistoryEntry(AiChatHistoryEntry(
                id: 'book-summary',
                scope: 'reader',
                serviceId: provider.id,
                model: provider.model,
                createdAt: 1,
                updatedAt: 1,
                messages: [
                  ChatMessage.humanText('总结本章'),
                  ChatMessage.ai('章节总结')
                ],
                completed: true,
                readingRequest: ReadingRequestSnapshot(
                    skillId: smartSummarySkillId,
                    bookId: 1,
                    chapterHref: 'private-chapter',
                    request: buildReadingSkillRequest(
                        policy: readingSkillPolicyFor(smartSummarySkillId)!,
                        prompt: '总结本章',
                        sourceContent: 'BOOK_SOURCE_SENTINEL',
                        sourceDescription: '当前章节'))));
            await chat.sendMessageStream('这章有什么结论？', ref, false).toList();
            expect(jsonEncode(requests.last), contains('BOOK_SOURCE_SENTINEL'));
            expect(jsonEncode(requests.last), contains('章节总结'));
            final bookEntry = (await AiHistoryStore.readHistory())
                .singleWhere((entry) => entry.id == 'book-summary');
            expect(bookEntry.effectiveHistoryKey, 'skill.smart_summary');
            expect(bookEntry.readingRequest!.skillId, smartSummarySkillId);
            chat.clear();
            chat.loadHistoryEntry(
                AiChatHistoryEntry.fromJson(bookEntry.toJson()));
            await chat.sendMessageStream('再展开说说', ref, false).toList();
            expect(jsonEncode(requests.last), contains('BOOK_SOURCE_SENTINEL'));
          }
        },
            () => MockClient((request) async {
                  requests
                      .add(jsonDecode(request.body) as Map<String, dynamic>);
                  return http.Response(
                      'data: ${jsonEncode({
                            'id': 'fixture',
                            'object': 'chat.completion.chunk',
                            'created': 1,
                            'model': 'GLM-4-Flash',
                            'choices': [
                              {
                                'index': 0,
                                'delta': {'content': '这是通用知识回答。'},
                                'finish_reason': null
                              }
                            ]
                          })}\n\ndata: [DONE]\n\n',
                      200,
                      headers: {
                        'content-type': 'text/event-stream; charset=utf-8'
                      });
                }));
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
