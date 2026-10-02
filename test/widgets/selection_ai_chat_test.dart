import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/service/ai/reading_skill_execution.dart';
import 'package:anx_reader/service/ai/reading_request_snapshot.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationCachePath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Chat extends AiChat {
  int clears = 0;
  final streams = <StreamController<List<ChatMessage>>>[];
  final requests = <({
    String message,
    String? source,
    String? skill,
    String? context,
    bool selectionRequest,
    bool webSearch,
    bool regenerate,
    int previousCount,
    CancelableLangchainRunner? runner
  })>[];
  @override
  void clear() {
    clears++;
    super.clear();
  }

  @override
  Stream<List<ChatMessage>> sendMessageStream(
      String message, WidgetRef widgetRef, bool isRegenerate,
      {String? skillId,
      String? sourceText,
      String? sourceContext,
      bool selectionRequest = false,
      bool webSearch = false,
      String? homePromptId,
      CancelableLangchainRunner? requestRunner}) {
    requests.add((
      message: message,
      source: sourceText,
      skill: skillId,
      context: sourceContext,
      selectionRequest: selectionRequest,
      webSearch: webSearch,
      regenerate: isRegenerate,
      previousCount: state.value?.length ?? 0,
      runner: requestRunner
    ));
    final controller = StreamController<List<ChatMessage>>();
    streams.add(controller);
    return controller.stream;
  }

  void emit(String answer) {
    final messages = [
      ChatMessage.humanText(requests.last.message),
      ChatMessage.ai(answer)
    ];
    state = AsyncData(messages);
    streams.last.add(messages);
  }

  void restoreDictionary() {
    loadHistoryEntry(AiChatHistoryEntry(
        id: 'restored-dictionary',
        scope: 'reader',
        serviceId: 'fake',
        model: 'fake',
        createdAt: 1,
        updatedAt: 1,
        completed: true,
        messages: [ChatMessage.humanText('解释词语'), ChatMessage.ai('行藏：读音不确定。')],
        readingRequest: ReadingRequestSnapshot(
            skillId: aiDictionarySkillId,
            request: buildReadingSkillRequest(
                policy: readingSkillPolicyFor(aiDictionarySkillId)!,
                prompt: '解释词语',
                sourceContent: '行藏',
                sourceDescription: 'selection'))));
  }
}

void main() {
  late _Chat chat;
  final key = GlobalKey<AiChatStreamState>();
  Future<void> mount(WidgetTester tester,
      {bool immediate = false,
      bool popup = false,
      bool selection = false,
      String? sourceContext,
      bool webSearch = false}) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final directory = Directory.systemTemp.createTempSync('modu-selection-ai-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      directory.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    chat = _Chat();
    final template = SelectionToolbarConfig.templateItems[1];
    Widget conversation() => AiChatStream(
        key: key,
        scope: AiChatScope.reader,
        initialMessage:
            immediate ? template.promptForSelection('原文 {selection}') : '原文',
        initialSourceText: '原文 {selection}',
        initialSourceContext: sourceContext,
        initialSelectionRequest: selection,
        initialWebSearch: webSearch,
        initialSkillId: template.skillId,
        sendImmediate: immediate,
        newConversation: true);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          aiChatProvider(AiChatScope.reader).overrideWith(() => chat)
        ],
        child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              ...GlobalMaterialLocalizations.delegates
            ],
            home: popup
                ? Scaffold(
                    body: Builder(
                        builder: (context) => TextButton(
                            onPressed: () => showReaderPopup(context,
                                builder: (_) => conversation()),
                            child: const Text('打开划词结果'))))
                : conversation())));
    if (immediate && !popup) {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    } else {
      await tester.pumpAndSettle();
    }
    if (popup) {
      await tester.tap(find.text('打开划词结果'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
    }
  }

  testWidgets(
      'template uses the shared reader popup and exact source on first frame',
      (tester) async {
    await mount(tester, immediate: true, popup: true);
    expect(find.byType(ReaderPopup), findsOneWidget);
    expect(find.byType(AiChatStream), findsOneWidget);
    expect(chat.requests, hasLength(1));
    expect(chat.requests.single.skill, 'selection_toolbar');
    expect(chat.requests.single.source, '原文 {selection}');
    expect(chat.requests.single.message, contains('"原文 {selection}"'));
    expect(chat.requests.single.previousCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    unawaited(chat.streams.single.close());
  });

  testWidgets(
      'restored dictionary accepts typed confirmation without clearing context',
      (tester) async {
    await mount(tester);
    chat.restoreDictionary();
    await tester.pumpAndSettle();
    expect(chat.currentDictionarySelection, '行藏');
    expect(
        find.byKey(const ValueKey('dictionary-web-follow-up')), findsNothing);
    expect(find.text('如需联网补查，请在下方输入“确认联网搜索”并发送。'), findsOneWidget);
    expect(chat.requests, isEmpty);
    final clears = chat.clears;
    await tester.enterText(find.byType(TextField), '确认联网搜索');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(chat.clears, clears);
    expect(chat.currentDictionarySelection, '行藏');
    expect(chat.requests, hasLength(1));
    expect(chat.requests.single.message, '确认联网搜索');
    expect(
        chat.requests.single.skill, isNull); // Provider resolves saved request.
    expect(chat.requests.single.source,
        isNull); // Never use current book selection.
    expect(chat.requests.single.previousCount, 2);
    chat.emit('根据检索资料整理的释义。');
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final immediate in [true, false]) {
    testWidgets(
        'selection options reach AI for ${immediate ? 'preset' : 'manual'} send and regeneration',
        (tester) async {
      await mount(tester,
          immediate: immediate,
          selection: true,
          sourceContext: '选区附近的上下文',
          webSearch: true);
      if (!immediate) {
        await tester.testTextInput.receiveAction(TextInputAction.send);
        // A direct button tap also works before the input gains keyboard focus.
        if (chat.requests.isEmpty) {
          await tester.enterText(find.byType(TextField), '介绍相关知识');
          await tester.testTextInput.receiveAction(TextInputAction.send);
        }
        await tester.pump();
      }
      expect(chat.requests, hasLength(1));
      expect(chat.requests.single.context, '选区附近的上下文');
      expect(chat.requests.single.selectionRequest, true);
      expect(chat.requests.single.webSearch, true);
      expect(chat.requests.single.source, '原文 {selection}');
      chat.emit('知识介绍');
      await chat.streams.last.close();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('重新生成'));
      await tester.tap(find.text('重新生成'));
      await tester.pump();
      expect(chat.requests.last.context, '选区附近的上下文');
      expect(chat.requests.last.webSearch, true);
      expect(chat.requests.last.selectionRequest, true);
      await tester.pumpWidget(const SizedBox());
      unawaited(chat.streams.last.close());
    });
  }

  testWidgets(
      'a new selection cancels old output and starts an independent question',
      (tester) async {
    await mount(tester, immediate: true);
    chat.emit('之前的回答');
    await tester.pumpAndSettle();
    final oldRunner = chat.requests.single.runner!;
    key.currentState!.beginSelectionQuestion(
        message: '只概括第二段', sourceText: '第二段', skillId: 'selection_toolbar');
    await tester.pump();
    expect(oldRunner.isCancelled, true);
    expect(chat.streams.first.hasListener, false);
    expect(chat.requests, hasLength(2));
    expect(chat.requests.last.source, '第二段');
    expect(chat.requests.last.previousCount, 0);
    chat.emit('本次回答');
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is StyledMarkdown && w.data.contains('之前的回答')),
        findsNothing);
    expect(
        find.byWidgetPredicate((w) => w is StyledMarkdown && w.data == '本次回答'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    unawaited(chat.streams.first.close());
  });

  testWidgets(
      'ordinary reader questions start fresh; regenerate keeps the same task',
      (tester) async {
    await mount(tester);
    chat.restore([ChatMessage.humanText('旧问题'), ChatMessage.ai('旧回答')],
        sessionId: 'old-session');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '这次的问题');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(chat.requests.last.previousCount, 0);
    expect(chat.currentSessionId, isNull);
    chat.emit('这次的回答');
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    final clears = chat.clears;
    await tester.ensureVisible(find.text('重新生成'));
    await tester.tap(find.text('重新生成'));
    await tester.pump();
    expect(chat.clears, clears);
    expect(chat.requests.last.regenerate, true);
    expect(chat.requests.last.previousCount, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    unawaited(chat.streams.last.close());
  });

  testWidgets('selection answer completion returns to its first paragraph',
      (tester) async {
    await mount(tester, immediate: true, popup: true);
    const first = '# 第一段解释';
    chat.emit('$first\n\n${'这是很长的解释，需要从开头开始阅读。\n\n' * 60}');
    await tester.pumpAndSettle();
    final list = find.byType(ListView);
    final position = tester.widget<ListView>(list).controller!.position;
    expect(position.extentAfter, 0);
    final bottom = position.pixels;
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    final answer = find.byWidgetPredicate(
        (w) => w is StyledMarkdown && w.data.startsWith(first));
    expect(position.pixels, lessThan(bottom));
    expect(
        tester.getTopLeft(answer).dy, closeTo(tester.getTopLeft(list).dy, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
