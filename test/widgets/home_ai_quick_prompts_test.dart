import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
import 'package:anx_reader/service/ai/readany_skills.dart';
import 'package:anx_reader/service/ai/skill_message_label.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/service/ai/home_ai_execution.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
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
}

class _RecordingAiChat extends AiChat {
  final requests = <({String? id, String text})>[];
  bool showReply = false;

  @override
  Stream<List<ChatMessage>> sendMessageStream(
    String message,
    WidgetRef widgetRef,
    bool isRegenerate, {
    String? skillId,
    String? sourceText,
    String? homePromptId,
    CancelableLangchainRunner? requestRunner,
  }) async* {
    requests.add((id: homePromptId, text: message));
    // Exercise the UI callbacks without networking or writing real history.
    yield showReply
        ? [ChatMessage.humanText(message), ChatMessage.ai('这里是模型回答')]
        : const [];
  }
}

void main() {
  Future<_RecordingAiChat> mount(WidgetTester tester, Size size,
      {double textScale = 1, List<AiQuickPromptChip> chips = const []}) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final directory = Directory.systemTemp.createTempSync('modu-home-prompts-');
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() {
      PathProviderPlatform.instance = originalPaths;
      directory.deleteSync(recursive: true);
    });
    tester.view.reset();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = _RecordingAiChat();
    await tester.pumpWidget(ProviderScope(
      overrides: [aiChatProvider(AiChatScope.library).overrideWith(() => chat)],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: AiChatStream(quickPromptChips: chips),
      ),
    ));
    await tester.pumpAndSettle();
    return chat;
  }

  Finder prompt(String id) => find.byKey(ValueKey('home-prompt-$id'));
  Future<void> togglePrompts(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('ai-skill-prompts-toggle')));
    await tester.pumpAndSettle();
  }

  testWidgets('skill shortcuts are visible by default and after new chat',
      (tester) async {
    await mount(tester, const Size(1100, 760));
    final ids = homeAiPromptPolicies.keys.toList();
    expect(find.byTooltip('收起技能标签'), findsOneWidget);
    for (final id in ids) {
      expect(prompt(id), findsOneWidget);
    }
    final chips = find.descendant(
        of: find.byKey(const ValueKey('home-quick-prompts')),
        matching: find.byType(ActionChip));
    expect(tester.widgetList<ActionChip>(chips).map((chip) => chip.key),
        ids.map((id) => ValueKey('home-prompt-$id')));
    await togglePrompts(tester);
    expect(find.byType(ActionChip), findsNothing);
    await togglePrompts(tester);
    await tester.tap(find.byIcon(Icons.edit_document));
    await tester.pumpAndSettle();
    expect(tester.widgetList<ActionChip>(chips).map((chip) => chip.key),
        ids.map((id) => ValueKey('home-prompt-$id')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('all twelve prompts retain their own request policy on click',
      (tester) async {
    final chat = await mount(tester, const Size(1100, 760));
    for (final id in homeAiPromptPolicies.keys) {
      final chip = tester.widget<ActionChip>(prompt(id));
      final expectedText = (chip.label as Text).data;
      await tester.ensureVisible(prompt(id));
      await tester.tap(prompt(id));
      await tester.pumpAndSettle();
      expect(chat.requests.last.id, id);
      expect(chat.requests.last.text, expectedText);
    }
    expect(chat.requests.length, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'small window and large text scroll to the final prompt without overflow',
      (tester) async {
    final chat = await mount(tester, const Size(360, 640), textScale: 1.5);
    final last = prompt(homePromptOrganizeByProgress);
    expect(last, findsOneWidget);
    await tester.ensureVisible(last);
    await tester.pumpAndSettle();
    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(chat.requests.single.id, homePromptOrganizeByProgress);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skill body is hidden but shortcuts and ordinary messages remain',
      (tester) async {
    final skill = readAnySkills.first;
    final chat = await mount(tester, const Size(390, 800), chips: [
      AiQuickPromptChip(
          icon: Icons.summarize,
          label: skill.name,
          prompt: skill.defaultPrompt,
          skillId: skill.id),
    ]);
    chat.showReply = true;
    expect(find.byKey(const ValueKey('reader-skill-chips')), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, skill.name));
    await tester.pumpAndSettle();
    expect(chat.requests.single.text, skill.defaultPrompt.trim());
    expect(find.byKey(const ValueKey('ai-message-skill-0')), findsOneWidget);
    expect(find.textContaining('你是一名注重准确性'), findsNothing);
    expect(find.widgetWithText(ActionChip, skill.name), findsOneWidget);
    await tester.enterText(find.byType(TextField), '我想问一下主角的动机');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-message-skill-0')), findsNothing);
    expect(find.text('我想问一下主角的动机'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('history retains skill labels without replacing model prompts',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final prompt = readAnySkills.first.defaultPrompt;
    final entry = AiChatHistoryEntry(
        id: 'test',
        scope: 'reader',
        serviceId: 'test',
        model: 'test',
        createdAt: 1,
        updatedAt: 1,
        completed: true,
        messages: [ChatMessage.humanText(prompt), ChatMessage.ai('answer')],
        skillLabels: const {0: '本章总结'});
    final restored = AiChatHistoryEntry.fromJson(entry.toJson());
    expect(restored.skillLabels, {0: '本章总结'});
    expect(restored.messages.first.contentAsString, prompt);
    expect(restored.copyWith(updatedAt: 2).skillLabels, {0: '本章总结'});
    final legacy = entry.toJson()..remove('skillLabels');
    expect(AiChatHistoryEntry.fromJson(legacy).skillLabels, isEmpty);
    expect(skillMessageLabel(prompt), '本章总结');
    expect(skillMessageLabel('请解释本章总结为什么会失败'), isNull);
  });
}
