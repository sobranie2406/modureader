import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_strings.dart';
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
    final previous = (state.value ?? const <ChatMessage>[])
        .take(requests.last.previousCount)
        .toList();
    if (requests.last.regenerate) {
      final index = previous.lastIndexWhere((m) => m is HumanChatMessage);
      if (index >= 0) previous.removeRange(index, previous.length);
    }
    final messages = [
      ...previous,
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
      bool inlineResults = false,
      bool selection = false,
      String? sourceContext,
      bool webSearch = false,
      Locale locale = const Locale('zh'),
      Size size = const Size(390, 800)}) async {
    await tester.runAsync(() => lookupL10n(locale));
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final directory = Directory.systemTemp.createTempSync('modu-selection-ai-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      directory.deleteSync(recursive: true);
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    chat = _Chat();
    final template = SelectionToolbarConfig.templateItems[1];
    Widget conversation() => AiChatStream(
        key: key,
        scope: AiChatScope.reader,
        embedded: inlineResults,
        inlineResults: inlineResults,
        initialDraftOnly: inlineResults ? false : null,
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
            locale: locale,
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
                : inlineResults
                    ? Scaffold(
                        body: SingleChildScrollView(child: conversation()))
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
      'inline automatic AI results grow with streamed content and accept follow-up',
      (tester) async {
    await mount(tester, immediate: true, inlineResults: true, selection: true);
    expect(chat.requests, hasLength(1));
    chat.emit('简短释义。');
    await tester.pump();
    final shortHeight = tester.getSize(find.byType(AiChatStream)).height;
    chat.emit(List.filled(25, '这是需要完整展示的较长释义，不应该被固定高度截断。').join('\n\n'));
    await tester.pump();
    expect(tester.getSize(find.byType(AiChatStream)).height,
        greaterThan(shortHeight + 500));
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('ai-message-input')));
    await tester.enterText(
        find.byKey(const ValueKey('ai-message-input')), '请举例');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(chat.requests, hasLength(2));
    expect(chat.requests.last.message, '请举例');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    unawaited(chat.streams.last.close());
  });

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
        find.byKey(const ValueKey('dictionary-web-follow-up')), findsOneWidget);
    expect(find.text('如需联网补查，请点击下方的联网搜索按钮。'), findsOneWidget);
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

  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
        'online search button retains session, term and draft (${locale.languageCode})',
        (tester) async {
      await mount(tester, locale: locale);
      chat.restoreDictionary();
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('dictionary-web-follow-up'));
      final context = tester.element(button);
      final regenerate = find.text(L10n.of(context).aiRegenerate);
      final copy = find.text(L10n.of(context).commonCopy);
      bool precedes(Finder first, Finder next) {
        final a = tester.getTopLeft(first);
        final b = tester.getTopLeft(next);
        return a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx);
      }

      expect(precedes(button, regenerate), isTrue);
      expect(precedes(regenerate, copy), isTrue);
      await tester.enterText(find.byType(TextField), '尚未发送的追问');
      final clears = chat.clears;
      final click = tester.widget<TextButton>(button).onPressed!;
      await tester.ensureVisible(button);
      await tester.tap(button);
      click(); // A second tap before the rebuild must not send twice.
      await tester.pump();
      expect(chat.requests, hasLength(1));
      expect(
          chat.requests.single.message,
          ModuStrings.value(
              locale, 'ui_dictionary_web_confirm_command', '确认联网搜索'));
      expect(chat.currentSessionId, 'restored-dictionary');
      expect(chat.currentDictionarySelection, '行藏');
      expect(chat.clears, clears);
      expect(chat.requests.single.previousCount, 2);
      expect(chat.requests.single.skill, isNull);
      expect(chat.requests.single.source, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '尚未发送的追问');
      chat.emit('联网补查后的回答及来源。');
      await tester.pump();
      await tester.pump();
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await chat.streams.last.close();
      await tester.pumpAndSettle();
      expect(chat.currentSessionId, 'restored-dictionary');
      expect(find.byKey(const ValueKey('dictionary-web-follow-up')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'no search button in unrelated conversations; narrow reply footer wraps',
      (tester) async {
    await mount(tester, size: const Size(280, 800));
    chat.restore([ChatMessage.humanText('问题'), ChatMessage.ai('普通回答')]);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('dictionary-web-follow-up')), findsNothing);
    chat.restoreDictionary();
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('dictionary-web-follow-up')), findsOneWidget);
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
      'ordinary reader follow-ups keep the conversation; regenerate replaces only the last answer',
      (tester) async {
    await mount(tester, immediate: true);
    chat.emit('旧回答');
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    chat.restore([ChatMessage.humanText('旧问题'), ChatMessage.ai('旧回答')],
        sessionId: 'old-session');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '这次的问题');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(chat.requests.last.previousCount, 2);
    expect(chat.currentSessionId, 'old-session');
    chat.emit('这次的回答');
    await chat.streams.last.close();
    await tester.pumpAndSettle();
    final clears = chat.clears;
    await tester.ensureVisible(find.text('重新生成'));
    await tester.tap(find.text('重新生成'));
    await tester.pump();
    expect(chat.clears, clears);
    expect(chat.requests.last.regenerate, true);
    expect(chat.requests.last.previousCount, 4);
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
