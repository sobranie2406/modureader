import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/l10n/modu_catalogs.g.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/service/ai/home_ai_execution.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
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
  final streams = <StreamController<List<ChatMessage>>>[];
  final requests = <({
    String message,
    String? skill,
    String? source,
    String? context,
    String? home,
    bool selection,
    bool web,
    bool regenerate
  })>[];

  @override
  Stream<List<ChatMessage>> sendMessageStream(
      String message, WidgetRef ref, bool isRegenerate,
      {String? skillId,
      String? sourceText,
      String? sourceContext,
      bool selectionRequest = false,
      bool webSearch = false,
      String? homePromptId,
      CancelableLangchainRunner? requestRunner}) {
    requests.add((
      message: message,
      skill: skillId,
      source: sourceText,
      context: sourceContext,
      home: homePromptId,
      selection: selectionRequest,
      web: webSearch,
      regenerate: isRegenerate
    ));
    final stream = StreamController<List<ChatMessage>>();
    streams.add(stream);
    return stream.stream;
  }

  Future<void> finish() async {
    final messages = [
      ChatMessage.humanText(requests.last.message),
      ChatMessage.ai('本次回答的第一段。')
    ];
    state = AsyncData(messages);
    streams.last.add(messages);
    await streams.last.close();
  }
}

void main() {
  const original = '选中的原文';
  const template = '按章节概述规范总结内容。';
  const custom = '用自己的规范说明。';
  final key = GlobalKey<AiChatStreamState>();
  late _Chat chat;
  final draftSwitch =
      find.byKey(const ValueKey('ai-skill-template-draft-switch'));
  final send = find.byKey(const ValueKey('ai-send-message'));
  Finder skill(int index) => find.byKey(ValueKey('reader-skill-$index'));

  Future<void> mount(WidgetTester tester,
      {bool draft = false,
      bool initial = false,
      bool popup = false,
      AiChatScope scope = AiChatScope.reader,
      Size size = const Size(390, 800),
      double scale = 1,
      Locale locale = const Locale('zh', 'CN')}) async {
    SharedPreferences.setMockInitialValues({'aiSkillTemplateDraft': draft});
    await Prefs().initPrefs();
    final directory =
        Directory.systemTemp.createTempSync('modu-template-draft-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      directory.deleteSync(recursive: true);
      for (final stream in chat.streams) {
        if (!stream.isClosed) unawaited(stream.close());
      }
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => lookupL10n(locale));
    chat = _Chat();
    Widget conversation() => AiChatStream(
          key: key,
          scope: scope,
          initialMessage: initial ? '说明选中文字的知识。' : null,
          initialSourceText: original,
          initialSourceContext: initial ? '选区附近的上下文' : null,
          initialSkillId: initial ? 'ai_dictionary' : null,
          initialSelectionRequest: initial,
          initialWebSearch: initial,
          newConversation: initial,
          sendImmediate: initial,
          quickPromptChips: scope == AiChatScope.reader
              ? const [
                  AiQuickPromptChip(
                      icon: Icons.summarize,
                      label: '章节概述规范',
                      prompt: template,
                      skillId: 'smart_summary'),
                  AiQuickPromptChip(
                      icon: Icons.person, label: '自定义模板', prompt: custom),
                ]
              : const [],
        );
    await tester.pumpWidget(ProviderScope(
      overrides: [aiChatProvider(scope).overrideWith(() => chat)],
      child: MaterialApp(
        locale: locale,
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          ...GlobalMaterialLocalizations.delegates
        ],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: popup
            ? Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showReaderPopup(context,
                            builder: (_) => conversation()),
                        child: const Text('打开对话'))))
            : conversation(),
      ),
    ));
    await tester.pumpAndSettle();
    if (popup) {
      await tester.tap(find.text('打开对话'));
      await tester.pumpAndSettle();
    }
  }

  test('all app languages contain the option and its explanation', () {
    for (final catalog in moduCatalogs.values) {
      expect(catalog['ai_skill_template_draft'], isNotEmpty);
      expect(catalog['ai_skill_template_draft_help'], isNotEmpty);
    }
  });

  testWidgets(
      'default stays immediate; dialog switch tracks the shared preference',
      (tester) async {
    await mount(tester);
    expect(tester.widget<SwitchListTile>(draftSwitch).value, false);
    await tester.tap(skill(0));
    await tester.pump();
    expect(chat.requests.single.message, template);
    expect(chat.requests.single.skill, 'smart_summary');
    await chat.finish();
    await tester.pumpAndSettle();
    await tester
        .tap(find.descendant(of: draftSwitch, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(Prefs().aiSkillTemplateDraft, true);
    Prefs().aiSkillTemplateDraft = false;
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(draftSwitch).value, false);
    expect(chat.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final index in [0, 1]) {
    testWidgets(
        'draft ${index == 0 ? 'built-in' : 'custom'} retains edits until manual send',
        (tester) async {
      await mount(tester, draft: true);
      await tester.tap(skill(index));
      await tester.pumpAndSettle();
      expect(chat.requests, isEmpty);
      final base = index == 0 ? template : custom;
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, base);
      expect(field.controller!.selection.baseOffset, base.length);
      expect(field.focusNode!.hasFocus, true);
      final revised = '$base\n范围：5-10章';
      await tester.enterText(find.byType(TextField), revised);
      await tester.pumpAndSettle();
      expect(chat.requests, isEmpty);
      await tester.tap(send);
      await tester.pump();
      expect(chat.requests.single.message, revised);
      expect(chat.requests.single.skill, index == 0 ? 'smart_summary' : null);
      expect(chat.requests.single.source, original);
      expect(chat.requests.single.selection, false);
      expect(field.controller!.text, isEmpty);
      await chat.finish();
      await tester.pumpAndSettle();
      // Reopening a template uses the stored original, not the temporary edit.
      await tester.tap(skill(index));
      await tester.pumpAndSettle();
      expect(field.controller!.text, base);
      expect(chat.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'changing templates and turning draft mode off never submits an existing draft',
      (tester) async {
    await mount(tester, draft: true);
    await tester.tap(skill(0));
    await tester.pumpAndSettle();
    await tester.tap(skill(1));
    await tester.pumpAndSettle();
    expect(chat.requests, isEmpty);
    await tester.enterText(find.byType(TextField), '$custom\n用列表说明');
    Prefs().aiSkillTemplateDraft = false;
    await tester.pumpAndSettle();
    expect(chat.requests, isEmpty);
    expect(key.currentState!.inputController.text, '$custom\n用列表说明');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(chat.requests.single.skill, isNull);
    expect(chat.requests.single.message, '$custom\n用列表说明');
    await chat.finish();
    await tester.pumpAndSettle();
    await tester.tap(skill(0));
    await tester.pump();
    expect(chat.requests.last.skill, 'smart_summary');
    expect(chat.requests, hasLength(2));
    await chat.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'toolbar template opens a draft in shared popup and keeps selection/context/web options',
      (tester) async {
    await mount(tester, draft: true, initial: true, popup: true);
    expect(find.byType(ReaderPopup), findsOneWidget);
    expect(chat.requests, isEmpty);
    expect(key.currentState!.inputController.text, '说明选中文字的知识。');
    await tester.enterText(find.byType(TextField), '说明选中文字的知识。\n简洁一点');
    await tester.tap(send);
    await tester.pump();
    final request = chat.requests.single;
    expect(request.message, endsWith('简洁一点'));
    expect(request.skill, 'ai_dictionary');
    expect(request.source, original);
    expect(request.context, '选区附近的上下文');
    expect(request.selection, true);
    expect(request.web, true);
    await chat.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a fresh selection in an existing panel respects draft mode and discards old draft metadata',
      (tester) async {
    await mount(tester, draft: true, initial: true);
    key.currentState!.beginSelectionQuestion(
        message: '分析新选区',
        sourceText: '新的原文',
        skillId: 'selection_toolbar',
        selectionRequest: true,
        sourceContext: '新的上下文');
    await tester.pumpAndSettle();
    expect(chat.requests, isEmpty);
    await tester.tap(send);
    await tester.pump();
    expect(chat.requests.single.message, '分析新选区');
    expect(chat.requests.single.skill, 'selection_toolbar');
    expect(chat.requests.single.source, '新的原文');
    expect(chat.requests.single.context, '新的上下文');
    expect(chat.requests.single.web, false);
    await chat.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new chat clears pending template and does not misclassify the next ordinary question',
      (tester) async {
    await mount(tester, draft: true);
    await tester.tap(skill(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_document));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '这是一个普通问题');
    await tester.tap(send);
    await tester.pump();
    expect(chat.requests.single.skill, isNull);
    expect(chat.requests.single.source, isNull);
    expect(chat.requests.single.selection, false);
    await chat.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'regenerate replays the sent task while retaining a different unsent template',
      (tester) async {
    await mount(tester, draft: true);
    await tester.tap(skill(0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '$template\n精简概述');
    await tester.tap(send);
    await tester.pump();
    await chat.finish();
    await tester.pumpAndSettle();
    await tester.tap(skill(1));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('重新生成'));
    await tester.tap(find.text('重新生成'));
    await tester.pump();
    expect(chat.requests.last.regenerate, true);
    expect(chat.requests.last.skill, 'smart_summary');
    expect(chat.requests.last.message, '$template\n精简概述');
    expect(key.currentState!.inputController.text, custom);
    await chat.finish();
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pump();
    expect(chat.requests.last.skill, isNull);
    expect(chat.requests.last.message, custom);
    expect(chat.requests.last.regenerate, false);
    await chat.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('home templates preserve their policy when edited before sending',
      (tester) async {
    await mount(tester, draft: true, scope: AiChatScope.library);
    await tester.tap(find.byKey(const ValueKey('ai-skill-prompts-toggle')));
    await tester.pumpAndSettle();
    final prompt =
        find.byKey(const ValueKey('home-prompt-$homePromptRecentBooks'));
    await tester.ensureVisible(prompt);
    await tester.tap(prompt);
    await tester.pumpAndSettle();
    expect(chat.requests, isEmpty);
    final base = key.currentState!.inputController.text;
    await tester.enterText(find.byType(TextField), '$base\n只列出书名');
    await tester.tap(send);
    await tester.pump();
    expect(chat.requests.single.home, homePromptRecentBooks);
    expect(chat.requests.single.message, '$base\n只列出书名');
    await chat.finish();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'draft input and option remain usable in a small dialog with large text',
      (tester) async {
    await mount(tester,
        draft: true,
        size: const Size(360, 500),
        scale: 1.5,
        locale: const Locale('en'));
    await tester.ensureVisible(skill(1));
    await tester.tap(skill(1));
    await tester.pumpAndSettle();
    expect(find.text('Edit skill templates before sending'), findsOneWidget);
    expect(send.hitTestable(), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(chat.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
