import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/ai_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/models/current_reading_state.dart';
import 'package:modu_reader/providers/ai_chat.dart';
import 'package:modu_reader/providers/current_reading.dart';
import 'package:modu_reader/service/ai/ai_history.dart';
import 'package:modu_reader/service/ai/reading_skill_execution.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';

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
  for (final (scope, markWhen) in [
    (AiChatScope.knowledge, 'initial'),
    (AiChatScope.library, 'initial'),
    (AiChatScope.library, 'during'),
    (AiChatScope.library, 'after'),
  ]) {
    testWidgets('${scope.name} protects private AI content ($markWhen mark)',
        (tester) async {
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        await Prefs().initPrefs();
      });
      const provider = AiProvider(
          id: 'fixture',
          title: 'Fixture',
          url: 'https://example.test/v1',
          protocol: AiProtocol.openai,
          model: 'GLM-4-Flash',
          apiKeys: [AiApiKey(id: 'test', key: 'fake')]);
      Prefs().saveAiProviders([provider]);
      Prefs().selectedAiService = provider.id;
      Prefs().enabledAiToolIds = [];
      final dir = Directory.systemTemp.createTempSync('modu-private-ai-');
      final oldPaths = PathProviderPlatform.instance,
          oldDocument = documentPath;
      PathProviderPlatform.instance = _Paths(dir.path);
      documentPath = dir.path;
      final container = ProviderContainer();
      final library =
          (await tester.runAsync(() async => PrivateLibrary.instance))!;
      addTearDown(() {
        container.dispose();
        library.setPluginActive(false);
        PathProviderPlatform.instance = oldPaths;
        documentPath = oldDocument;
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
        final book = Book.mock().copyWith(filePath: 'private.epub');
        library.setPluginActive(true);
        await library.unlock();
        if (markWhen == 'initial') await library.setBooksPrivate([book], true);
        container
            .read(currentReadingProvider.notifier)
            .start(CurrentReadingState(book: book));
        await container.read(aiChatProvider(scope).future);
        final chat = container.read(aiChatProvider(scope).notifier);
        List<Map<String, dynamic>>? originalHistory;
        await http.runWithClient(() async {
          await chat
              .sendMessageStream('解释这个词', ref, false,
                  skillId: scope == AiChatScope.knowledge
                      ? aiDictionarySkillId
                      : null,
                  sourceText: scope == AiChatScope.knowledge ? '私密文字' : null)
              .toList();
        },
            () => MockClient((_) async {
                  if (markWhen == 'during') {
                    originalHistory = (await AiHistoryStore.readHistory())
                        .map((e) => e.toJson())
                        .toList();
                    await library.setBooksPrivate([book], true);
                  }
                  return http.Response(
                      'data: ${jsonEncode({
                            'id': 'fixture',
                            'object': 'chat.completion.chunk',
                            'created': 1,
                            'model': 'GLM-4-Flash',
                            'choices': [
                              {
                                'index': 0,
                                'delta': {'content': 'PRIVATE ANSWER'},
                                'finish_reason': null
                              }
                            ]
                          })}\n\ndata: [DONE]\n\n',
                      200,
                      headers: {
                        'content-type': 'text/event-stream; charset=utf-8'
                      });
                }));
        expect(container.read(aiChatProvider(scope)).value, isNotEmpty);
        final id = chat.currentSessionId;
        if (markWhen == 'after') {
          originalHistory = (await AiHistoryStore.readHistory())
              .map((e) => e.toJson())
              .toList();
          await library.setBooksPrivate([book], true);
        }
        if (markWhen == 'initial') {
          expect(await AiHistoryStore.readHistory(), isEmpty);
        } else {
          expect(originalHistory, hasLength(1));
          expect((await AiHistoryStore.readHistory()).map((e) => e.toJson()),
              originalHistory);
        }
        library.lock();
        expect(container.read(aiChatProvider(scope)).value, isEmpty);
        expect(chat.currentSessionId, isNull);
        if (markWhen != 'initial') expect(library.canReadHistory(id!), false);
        await library.unlock();
        expect(container.read(aiChatProvider(scope)).value, isEmpty);
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
