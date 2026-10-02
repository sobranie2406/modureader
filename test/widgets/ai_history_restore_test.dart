import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/providers/ai_history.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  for (final scope in AiChatScope.values) {
    testWidgets(
        '${scope.name} live and restored follow-ups send prior turns and update one history entry',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      await Prefs().initPrefs();
      Prefs().enabledAiToolIds = [];
      const provider = AiProvider(
          id: 'fixture',
          title: 'Fixture',
          url: 'https://example.test/v1',
          protocol: AiProtocol.openai,
          model: 'GLM-4-Flash',
          apiKeys: [AiApiKey(id: 'fixture', key: 'not-a-real-key')]);
      Prefs().saveAiProviders([provider]);
      Prefs().selectedAiService = provider.id;
      final directory =
          Directory.systemTemp.createTempSync('modu-history-restore-');
      final oldPaths = PathProviderPlatform.instance;
      final oldDocumentPath = documentPath;
      PathProviderPlatform.instance = _Paths(directory.path);
      documentPath = directory.path;
      addTearDown(() {
        documentPath = oldDocumentPath;
        PathProviderPlatform.instance = oldPaths;
        directory.deleteSync(recursive: true);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        await container.read(aiChatProvider(scope).future);
        await container.read(aiHistoryProvider.notifier).refresh();
      });
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate
            ],
            home: Consumer(builder: (context, widgetRef, _) {
              ref = widgetRef;
              return AiChatStream(scope: scope);
            }),
          )));
      await tester.pumpAndSettle();
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.leading, isNull);
      expect(appBar.automaticallyImplyLeading, isFalse);
      final historyButton = find.byKey(const ValueKey('ai-chat-history'));
      final optionsButton = find.byKey(const ValueKey('ai-chat-options'));
      expect(
          find.descendant(
              of: historyButton, matching: find.byIcon(Icons.history)),
          findsOneWidget);
      expect(tester.getRect(historyButton).right,
          tester.getRect(optionsButton).left);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await ref.read(aiChatProvider(scope).future);
        await ref.read(aiHistoryProvider.notifier).refresh();
        String event(String text) => 'data: ${jsonEncode({
                  'id': 'fixture',
                  'object': 'chat.completion.chunk',
                  'created': 1,
                  'model': 'GLM-4-Flash',
                  'choices': [
                    {
                      'index': 0,
                      'delta': {'content': text},
                      'finish_reason': null
                    }
                  ],
                })}\n\n';
        final runner = CancelableLangchainRunner();
        final replies = await http.runWithClient(
            () => ref
                .read(aiChatProvider(scope).notifier)
                .sendMessageStream('历史问题', ref, false, requestRunner: runner)
                .toList(),
            () => MockClient((_) async => http.Response(
                '${event('你好！我是你的阅读助手，后来泛指所有')}${event('房屋或房间。')}data: [DONE]\n\n',
                200,
                headers: {'content-type': 'text/event-stream; charset=utf-8'})));
        expect(runner.isCancelled, isFalse);
        expect(replies.last.last.contentAsString, '你好！我是你的阅读助手，后来泛指所有房屋或房间。');
        final disk = await AiHistoryStore.readHistory();
        expect(disk, hasLength(1));
        expect(disk.single.completed, isTrue);
        expect(disk.single.messages.last.contentAsString,
            replies.last.last.contentAsString);
      });
      await tester.pumpAndSettle();
      final sessionId =
          container.read(aiChatProvider(scope).notifier).currentSessionId;
      Future<void> followUp(String question, String answer, int count) async {
        await tester.enterText(find.byType(TextField), question);
        final requests = <Map<String, dynamic>>[];
        await tester.runAsync(() => http.runWithClient(() async {
              await tester.tap(find.byKey(const ValueKey('ai-send-message')));
              final timeout = DateTime.now().add(const Duration(seconds: 5));
              while (DateTime.now().isBefore(timeout)) {
                final entries = await AiHistoryStore.readHistory();
                if (entries.length == 1 &&
                    entries.single.completed &&
                    entries.single.messages.length == count) break;
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
              final entries = await AiHistoryStore.readHistory();
              expect(entries, hasLength(1));
              expect(entries.single.id, sessionId);
              expect(entries.single.completed, true);
              expect(entries.single.messages, hasLength(count));
              expect(entries.single.messages.last.contentAsString, answer);
            },
                () => MockClient((request) async {
                      requests.add(
                          jsonDecode(request.body) as Map<String, dynamic>);
                      return http.Response(
                          'data: ${jsonEncode({
                                'id': 'follow-up',
                                'object': 'chat.completion.chunk',
                                'created': 1,
                                'model': 'GLM-4-Flash',
                                'choices': [
                                  {
                                    'index': 0,
                                    'delta': {'content': answer},
                                    'finish_reason': null
                                  }
                                ]
                              })}\n\ndata: [DONE]\n\n',
                          200,
                          headers: {
                            'content-type': 'text/event-stream; charset=utf-8'
                          });
                    })));
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        final turns = (requests.single['messages'] as List)
            .where((m) => m['role'] == 'user' || m['role'] == 'assistant')
            .toList();
        expect(turns, hasLength(count - 1));
        expect(turns.first['content'], '历史问题');
        expect(turns[1]['content'], '你好！我是你的阅读助手，后来泛指所有房屋或房间。');
        expect(turns.last['content'], question);
        if (count == 6) {
          expect(turns[2]['content'], '请进一步解释');
          expect(turns[3]['content'], '这是第一轮追问的回答。');
        }
        expect(container.read(aiChatProvider(scope).notifier).currentSessionId,
            sessionId);
        expect(tester.takeException(), isNull);
      }

      await followUp('请进一步解释', '这是第一轮追问的回答。', 4);
      await tester.runAsync(() async {
        ref.read(aiChatProvider(scope).notifier).clear();
        await ref.read(aiHistoryProvider.notifier).refresh();
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(
          L10n.of(tester.element(find.byType(AiChatStream))).history));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(Drawer), matching: find.text('历史问题')));
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((widget) =>
              widget is StyledMarkdown &&
              widget.data.contains('你好！我是你的阅读助手，后来泛指所有房屋或房间。')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await followUp('接着上面的内容继续', '这是调阅历史后的回答。', 6);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
