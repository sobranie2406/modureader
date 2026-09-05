import 'dart:io';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_quick_prompt_chip.dart';
import 'package:anx_reader/providers/ai_chat.dart';
import 'package:anx_reader/service/ai/ai_history.dart';
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

void main() {
  testWidgets(
      'empty translation selection shows actionable error and restores prompt',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final directory = Directory.systemTemp.createTempSync('modu-ui-error-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      directory.deleteSync(recursive: true);
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('zh'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      supportedLocales: L10n.supportedLocales,
      home: Builder(
          builder: (context) => Scaffold(
                  body: TextButton(
                child: const Text('打开阅读AI'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AiChatStream(
                            scope: AiChatScope.reader,
                            quickPromptChips: [
                              AiQuickPromptChip(
                                  icon: Icons.translate,
                                  label: '智能翻译',
                                  prompt: '翻译选中原文',
                                  skillId: 'smart_translator'),
                            ]))),
              ))),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开阅读AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('智能翻译'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-request-error')), findsOneWidget);
    expect(find.textContaining('请先在阅读界面选择需要翻译的原文'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '翻译选中原文');
    expect(find.byIcon(Icons.stop), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'legacy reader regenerate preserves old messages when source is unavailable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    late WidgetRef widgetRef;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, ref, _) {
          widgetRef = ref;
          return const SizedBox();
        })));
    await container.read(aiChatProvider(AiChatScope.reader).future);
    final notifier =
        container.read(aiChatProvider(AiChatScope.reader).notifier);
    final messages = [ChatMessage.humanText('旧问题'), ChatMessage.ai('旧答案')];
    notifier.loadHistoryEntry(AiChatHistoryEntry(
        id: 'legacy',
        scope: 'reader',
        serviceId: 'fake',
        model: 'fake',
        createdAt: 1,
        updatedAt: 1,
        messages: messages,
        completed: true));
    await expectLater(
        notifier.sendMessageStream('旧问题', widgetRef, true).toList(),
        throwsStateError);
    expect(container.read(aiChatProvider(AiChatScope.reader)).value, messages);
  });
}
