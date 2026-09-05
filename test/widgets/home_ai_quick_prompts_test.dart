import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
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
    yield const [];
  }
}

void main() {
  Future<_RecordingAiChat> mount(WidgetTester tester, Size size,
      {double textScale = 1}) async {
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
        home: const AiChatStream(),
      ),
    ));
    await tester.pumpAndSettle();
    return chat;
  }

  Finder prompt(String id) => find.byKey(ValueKey('home-prompt-$id'));

  testWidgets(
      'shows every home prompt in stable order, including after new chat',
      (tester) async {
    await mount(tester, const Size(1100, 760));
    final ids = homeAiPromptPolicies.keys.toList();
    for (final id in ids) {
      expect(prompt(id), findsOneWidget);
    }
    final chips = find.descendant(
        of: find.byKey(const ValueKey('home-quick-prompts')),
        matching: find.byType(ActionChip));
    expect(tester.widgetList<ActionChip>(chips).map((chip) => chip.key),
        ids.map((id) => ValueKey('home-prompt-$id')));
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
}
