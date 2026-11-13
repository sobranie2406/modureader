import 'dart:io';
import 'package:modu_reader/widgets/common/app_scroll_behavior.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:modu_reader/widgets/context_menu/translation_menu.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/unified_query.dart';
import 'package:modu_reader/widgets/dictionary/unified_query.dart';
import 'package:modu_reader/widgets/dictionary/unified_query_settings.dart';
import 'package:modu_reader/widgets/ai/ai_chat_stream.dart';
import 'package:modu_reader/widgets/ai/skill_template_draft_tile.dart';
import 'package:modu_reader/service/ai/ai_history.dart';
import 'package:modu_reader/providers/ai_history.dart';
import 'package:langchain_core/chat_models.dart';
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
  testWidgets('reflow translation opens the translation tab directly',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: UnifiedQuery(
                text: 'OCR result',
                initialSection: QuerySection.translation,
                panelBuilder: (section, text) =>
                    Text('panel:${section.name}:$text')))));
    await tester.pumpAndSettle();
    expect(find.text('panel:translation:OCR result'), findsOneWidget);
    expect(find.text('panel:dictionary:OCR result'), findsNothing);
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
    await tester.runAsync(() async {
      for (final key in [
        'skill.ai_dictionary',
        'screen.lookup.classical',
        'reader'
      ]) {
        await AiHistoryStore.upsertEntry(AiChatHistoryEntry(
            id: key,
            scope: 'reader',
            historyKey: key,
            serviceId: 'fake',
            model: 'fake',
            createdAt: 1,
            updatedAt: 1,
            completed: true,
            messages: [
              ChatMessage.humanText('HISTORY:$key'),
              ChatMessage.ai('Saved answer')
            ]));
      }
    });
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            scrollBehavior: const AppScrollBehavior(),
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
    await tester.runAsync(() =>
        ProviderScope.containerOf(tester.element(find.byType(AiChatStream)))
            .read(aiHistoryProvider.notifier)
            .refresh());
    await tester.tap(find.byKey(const ValueKey('ai-chat-history')));
    await tester.pumpAndSettle();
    expect(find.text('HISTORY:skill.ai_dictionary'), findsOneWidget);
    expect(find.text('HISTORY:screen.lookup.classical'), findsNothing);
    expect(find.text('HISTORY:reader'), findsNothing);
    await tester.tap(find.text('HISTORY:skill.ai_dictionary'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    // Classical translation now has independent settings, not reading skills.
    expect(find.byKey(const ValueKey('manage-reading-skills')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-new-conversation')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-chat-options')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ai-chat-history')));
    await tester.pumpAndSettle();
    expect(find.text('HISTORY:screen.lookup.classical'), findsOneWidget);
    expect(find.text('HISTORY:skill.ai_dictionary'), findsNothing);
    expect(find.text('HISTORY:reader'), findsNothing);
    await tester.tap(find.text('HISTORY:screen.lookup.classical'));
    await tester.pumpAndSettle();
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
  test(
      'custom overview order persists and disabled sources keep their positions',
      () async {
    final custom = [
      QuerySection.knowledge,
      QuerySection.translation,
      QuerySection.encyclopedia,
      QuerySection.dictionary
    ];
    final prefs = UnifiedQueryPreferences()
      ..order = custom
      ..smartOrder = false
      ..included.remove(QuerySection.translation);
    await prefs.save(Prefs().prefs);
    final restored = UnifiedQueryPreferences.load(Prefs().prefs);
    expect(restored.order, custom);
    for (final query in [
      'district',
      '沈泽民',
      'This is a sentence to translate.'
    ]) {
      expect(queryOrder(query, restored),
          custom.where((s) => s != QuerySection.translation).toList());
    }
    restored.included.add(QuerySection.translation);
    expect(queryOrder('沈泽民', restored), custom);
    restored.smartOrder = true;
    expect(queryOrder('沈泽民', restored).first, QuerySection.dictionary);
    restored.smartOrder = false;
    expect(queryOrder('沈泽民', restored), custom);
  });
  test('old and invalid orders restore all four sources without duplicates',
      () async {
    for (final rawOrder in [
      null,
      [],
      'dictionary',
      ['knowledge', 'book', 'knowledge', 1, null, 'unknown', 'dictionary'],
    ]) {
      await Prefs().prefs.setString(
          UnifiedQueryPreferences.key,
          jsonEncode({
            if (rawOrder != null) 'order': rawOrder,
            'smartOrder': false,
            'included': ['dictionary', 'knowledge']
          }));
      final prefs = UnifiedQueryPreferences.load(Prefs().prefs);
      final validCustom = rawOrder is List && rawOrder.isNotEmpty;
      expect(
          prefs.order,
          validCustom
              ? [
                  QuerySection.knowledge,
                  QuerySection.dictionary,
                  QuerySection.encyclopedia,
                  QuerySection.translation
                ]
              : QuerySection.comprehensive);
      expect(prefs.included, {QuerySection.dictionary, QuerySection.knowledge});
      expect(
          queryOrder('词语', prefs),
          validCustom
              ? [QuerySection.knowledge, QuerySection.dictionary]
              : [QuerySection.dictionary, QuerySection.knowledge]);
    }
  });
  for (final locale in [const Locale('zh'), const Locale('en')]) {
    testWidgets('dragging overview order saves and updates cards at $locale',
        (tester) async {
      await tester.runAsync(() => L10n.delegate.load(locale));
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          locale: locale,
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            ...GlobalMaterialLocalizations.delegates
          ],
          home: Scaffold(
              body: UnifiedQuery(
                  text: 'district',
                  panelBuilder: (s, _) =>
                      TextField(key: ValueKey('draft-${s.name}'))))));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('draft-knowledge')));
      await tester.enterText(
          find.byKey(const ValueKey('draft-knowledge')), 'keep');
      await tester.tap(find.byKey(const ValueKey('query-settings')));
      await tester.pumpAndSettle();
      final handle = find.byKey(const ValueKey('query-drag-knowledge'));
      final first = find.byKey(const ValueKey('query-drag-dictionary'));
      final target = tester.getCenter(first) + const Offset(0, 8);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<SwitchListTile>(
                  find.byKey(const ValueKey('query-smart-order')))
              .value,
          false);
      expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('query-order-knowledge')))
              .dy,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('query-order-dictionary')))
              .dy));
      // Reordering persists immediately; disabled rows remain sortable.
      expect(UnifiedQueryPreferences.load(Prefs().prefs).smartOrder, false);
      await tester
          .tap(find.byKey(const ValueKey('query-include-encyclopedia')));
      final orderList = tester.widget<ReorderableListView>(
          find.byKey(const ValueKey('query-section-order')));
      orderList.onReorderItem!(0, 3);
      await tester.pumpAndSettle();
      tester
          .widget<ReorderableListView>(
              find.byKey(const ValueKey('query-section-order')))
          .onReorderItem!(3, 0);
      await tester.pumpAndSettle();
      expect(
          find.widgetWithText(
              FilledButton, locale.languageCode == 'zh' ? '保存' : 'Save'),
          findsNothing);
      Navigator.of(tester.element(find.byType(UnifiedQuerySettings))).pop();
      await tester.pumpAndSettle();
      final prefs = UnifiedQueryPreferences.load(Prefs().prefs);
      expect(prefs.order, [
        QuerySection.knowledge,
        QuerySection.dictionary,
        QuerySection.encyclopedia,
        QuerySection.translation
      ]);
      expect(prefs.included, isNot(contains(QuerySection.encyclopedia)));
      expect(find.byType(UnifiedQuerySettings), findsNothing);
      expect(
          tester
              .getTopLeft(find.byKey(const ValueKey('query-tab-knowledge')))
              .dx,
          lessThan(tester
              .getTopLeft(find.byKey(const ValueKey('query-tab-dictionary')))
              .dx));
      final cards = [
        QuerySection.knowledge,
        QuerySection.dictionary,
        QuerySection.translation
      ];
      for (var i = 1; i < cards.length; i++) {
        expect(
            tester
                .getTopLeft(
                    find.byKey(ValueKey('query-panel-${cards[i - 1].name}-0')))
                .dy,
            lessThan(tester
                .getTopLeft(
                    find.byKey(ValueKey('query-panel-${cards[i].name}-0')))
                .dy));
      }
      expect(find.text('keep'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
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
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(UnifiedQuerySettings))).pop();
      await tester.pumpAndSettle();
      expect(UnifiedQueryPreferences.load(Prefs().prefs).included,
          isNot(contains(QuerySection.translation)));
      expect(tester.takeException(), isNull);
    });
  }
}
