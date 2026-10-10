import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anx_reader/widgets/context_menu/translation_menu.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/unified_query.dart';
import 'package:anx_reader/widgets/dictionary/unified_query.dart';
import 'package:anx_reader/widgets/ai/ai_chat_stream.dart';
import 'package:anx_reader/widgets/ai/skill_template_draft_tile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationCachePath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets(
      'real AI tabs preserve drafts in isolated conversations and fit a keyboard',
      (tester) async {
    await tester.runAsync(() => L10n.delegate.load(const Locale('zh')));
    final directory = Directory.systemTemp.createTempSync('modu-query-ui-');
    final paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
    addTearDown(() {
      PathProviderPlatform.instance = paths;
      directory.deleteSync(recursive: true);
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = UnifiedQueryPreferences()
      ..manualAi = true
      ..included = {QuerySection.knowledge};
    await prefs.save(Prefs().prefs);
    Prefs().aiReadingSkillsVisible = true;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            locale: const Locale('zh'),
            supportedLocales: L10n.supportedLocales,
            localizationsDelegates: const [
              L10n.delegate,
              ...GlobalMaterialLocalizations.delegates
            ],
            home: const Scaffold(body: UnifiedQuery(text: '学而不思则罔')))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-message-input')), findsOneWidget);
    final knowledgeState =
        tester.state<AiChatStreamState>(find.byType(AiChatStream));
    expect(knowledgeState.inputController.text, contains('学而不思则罔'));
    knowledgeState.inputController.text = '等待发送的问题';
    await tester
        .ensureVisible(find.byKey(const ValueKey('query-tab-classical')));
    await tester.tap(find.byKey(const ValueKey('query-tab-classical')));
    await tester.pumpAndSettle();
    final classicalState =
        tester.state<AiChatStreamState>(find.byType(AiChatStream));
    expect(classicalState, isNot(same(knowledgeState)));
    expect(classicalState.inputController.text, contains('现代汉语'));
    expect(find.byKey(const ValueKey('ai-skill-picker')), findsNothing);
    expect(find.byKey(const ValueKey('ai-skill-prompts-toggle')), findsNothing);
    expect(find.byKey(const ValueKey('manage-reading-skills')), findsNothing);
    expect(find.byType(SkillTemplateDraftTile), findsNothing);
    expect(find.textContaining('尚未启用阅读技能'), findsNothing);
    expect(find.byKey(const ValueKey('ai-send-message')), findsOneWidget);
    expect(
        tester
            .widget<AiChatStream>(find.byType(AiChatStream))
            .initialSelectionRequest,
        true);
    await tester.ensureVisible(find.byKey(const ValueKey('query-tab-book')));
    await tester.tap(find.byKey(const ValueKey('query-tab-book')));
    await tester.pumpAndSettle();
    final bookState =
        tester.state<AiChatStreamState>(find.byType(AiChatStream));
    expect(bookState.inputController.text, '学而不思则罔');
    expect(find.byKey(const ValueKey('manage-reading-skills')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('ai-skill-prompts-toggle')), findsOneWidget);
    expect(tester.widget<AiChatStream>(find.byType(AiChatStream)).sendImmediate,
        false);
    bookState.inputController.text = '这句话在本书中是什么意思？';
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester
        .ensureVisible(find.byKey(const ValueKey('query-tab-knowledge')));
    await tester.tap(find.byKey(const ValueKey('query-tab-knowledge')));
    await tester.pumpAndSettle();
    expect(tester.state<AiChatStreamState>(find.byType(AiChatStream)),
        same(knowledgeState));
    expect(knowledgeState.inputController.text, '等待发送的问题');
    await tester.ensureVisible(find.byKey(const ValueKey('query-tab-book')));
    await tester.tap(find.byKey(const ValueKey('query-tab-book')));
    await tester.pumpAndSettle();
    expect(tester.state<AiChatStreamState>(find.byType(AiChatStream)),
        same(bookState));
    expect(bookState.inputController.text, '这句话在本书中是什么意思？');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  test('overview limits, defaults, local ordering and empty selection persist',
      () async {
    var prefs = UnifiedQueryPreferences.load(Prefs().prefs);
    expect(prefs.manualAi, false);
    expect(queryOrder('district', prefs).first, QuerySection.dictionary);
    expect(queryOrder('This is a full sentence to translate.', prefs).first,
        QuerySection.translation);
    expect(queryOrder('沈泽民', prefs), isNot(contains(QuerySection.book)));
    expect(queryOrder('沈泽民', prefs), isNot(contains(QuerySection.classical)));
    expect(queryOrder('沈泽民', prefs), isNot(contains(QuerySection.web)));
    prefs.included.clear();
    prefs.manualAi = true;
    await prefs.save(Prefs().prefs);
    prefs = UnifiedQueryPreferences.load(Prefs().prefs);
    expect(prefs.included, isEmpty);
    expect(prefs.manualAi, true);
    expect(
        (await Prefs().buildPrefsBackupMap())
            .containsKey(UnifiedQueryPreferences.key),
        false);
  });
  testWidgets(
      'encyclopedia queries automatically once and survives tab changes',
      (tester) async {
    await tester.runAsync(() => L10n.delegate.load(const Locale('zh')));
    await (UnifiedQueryPreferences()..included = {QuerySection.encyclopedia})
        .save(Prefs().prefs);
    var calls = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            ...GlobalMaterialLocalizations.delegates
          ],
          home: const Scaffold(body: UnifiedQuery(text: '汉字'))));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('自动查询所得百科摘要'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('query-tab-encyclopedia')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('query-tab-all')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              calls++;
              expect(request.url.host, 'zh.wikipedia.org');
              return http.Response(
                  jsonEncode({
                    'query': {
                      'search': [
                        {'pageid': 1, 'title': '汉字', 'snippet': '自动查询所得百科摘要'}
                      ]
                    }
                  }),
                  200,
                  headers: {'content-type': 'application/json; charset=utf-8'});
            }));
  });

  testWidgets('embedded translation starts automatically and fits long content',
      (tester) async {
    await tester.runAsync(() => L10n.delegate.load(const Locale('zh')));
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          ...GlobalMaterialLocalizations.delegates
        ],
        home: Scaffold(
            body: SingleChildScrollView(
                child: TranslationMenu(
                    content: 'test',
                    embedded: true,
                    resultBuilder: (_, __) {
                      calls++;
                      return Text(List.filled(60, '较长的翻译结果').join('\n'));
                    })))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(
        tester.getSize(find.byType(TranslationMenu)).height, greaterThan(1000));
    expect(tester.takeException(), isNull);
  });
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets(
        'overview/tab switching keeps one panel and its draft at $locale',
        (tester) async {
      await tester.runAsync(() => L10n.delegate.load(locale));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final built = <QuerySection, int>{};
      await tester.pumpWidget(MaterialApp(
          locale: locale,
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            ...GlobalMaterialLocalizations.delegates
          ],
          home: Scaffold(
              body: UnifiedQuery(
                  text: 'district',
                  panelBuilder: (s, q) {
                    built.update(s, (v) => v + 1, ifAbsent: () => 1);
                    return TextField(key: ValueKey('draft-${s.name}'));
                  }))));
      await tester.pumpAndSettle();
      expect(built.keys.toSet(), QuerySection.comprehensive.toSet());
      await tester.enterText(
          find.byKey(const ValueKey('draft-dictionary')), 'keep my draft');
      await tester.tap(find.byKey(const ValueKey('query-tab-dictionary')));
      await tester.pumpAndSettle();
      expect(built[QuerySection.dictionary], 1);
      expect(find.text('keep my draft'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('query-tab-book')));
      await tester.tap(find.byKey(const ValueKey('query-tab-book')));
      await tester.pumpAndSettle();
      expect(built[QuerySection.book], 1);
      await tester.ensureVisible(find.byKey(const ValueKey('query-tab-all')));
      await tester.tap(find.byKey(const ValueKey('query-tab-all')));
      await tester.pumpAndSettle();
      expect(find.text('keep my draft'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('query-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('query-include-translation')));
      await tester.drag(find.byType(ListView).last, const Offset(0, -1300));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(
          FilledButton, locale.languageCode == 'zh' ? '保存' : 'Save'));
      await tester.tap(find.widgetWithText(
          FilledButton, locale.languageCode == 'zh' ? '保存' : 'Save'));
      await tester.pumpAndSettle();
      expect(UnifiedQueryPreferences.load(Prefs().prefs).included,
          isNot(contains(QuerySection.translation)));
      expect(tester.takeException(), isNull);
    });
  }
}
