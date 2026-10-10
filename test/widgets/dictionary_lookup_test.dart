import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/selection_toolbar.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/dictionaries.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/service/dictionary/dictionary_preferences.dart';
import 'package:anx_reader/service/dictionary/online_dictionary.dart';
import 'package:dio/dio.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_lookup.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_original.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_common.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dictionary_original_test.dart' show FakeDictionaryBrowser;

class FakeDictionaries extends LocalDictionaryStore {
  FakeDictionaries() : super('unused');
  List<LocalDictionary> items = [
    const LocalDictionary('one', '本地词典', 'MDX', 2, true)
  ];
  final queries = <String>[];
  Completer<List<DictionaryEntry>>? delayed;
  @override
  Future<List<LocalDictionary>> list() async => items;
  @override
  Future<List<DictionaryEntry>> lookup(String word,
      {Set<String>? dictionaryIds}) async {
    queries.add(word);
    if (delayed != null) return delayed!.future;
    final definition = switch (word) {
      'apple' => '苹果\n${'文字释义。' * 300}',
      '苹果' => 'apple; apple tree',
      '中国' => 'China',
      _ => '',
    };
    return definition.isEmpty
        ? []
        : items
            .where((d) =>
                d.enabled &&
                (dictionaryIds == null || dictionaryIds.contains(d.id)))
            .map((d) =>
                DictionaryEntry(d.name, word, definition, dictionaryId: d.id))
            .toList();
  }

  @override
  Future<void> rename(String id, String name) async {
    items = items
        .map((d) => LocalDictionary(d.id, name, d.format, d.count, d.enabled))
        .toList();
  }

  @override
  Future<void> enable(String id, bool enabled) async {
    items = items
        .map((d) => LocalDictionary(d.id, d.name, d.format, d.count, enabled))
        .toList();
  }

  @override
  Future<void> delete(String id) async {
    items = [];
  }
}

class FakeOnlineDictionary extends OnlineDictionaryService {
  final result = Completer<List<DictionaryEntry>>();
  final queries = <String>[];
  CancelToken? token;
  @override
  Future<List<DictionaryEntry>> lookup(OnlineDictionary source, String word,
      {CancelToken? cancelToken}) {
    queries.add(word);
    token = cancelToken;
    return result.future;
  }
}

Widget app(Widget body) => MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      theme: ThemeData(
          textTheme: const TextTheme(headlineLarge: TextStyle(fontSize: 96))),
      home: Scaffold(body: body),
    );

void main() {
  test(
      'Android picker does not disable dictionary files with unknown MIME types',
      () {
    expect(dictionaryPickerType(TargetPlatform.android), FileType.any);
    for (final platform in [
      TargetPlatform.iOS,
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux
    ]) {
      expect(dictionaryPickerType(platform), FileType.custom);
    }
    expect(dictionaryExtensions,
        containsAll(['mdx', 'ifo', 'idx', 'dict', 'syn']));
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('zh'));
  });
  testWidgets('local dictionary selection can choose one or many with sources',
      (tester) async {
    final store = FakeDictionaries()
      ..items.add(const LocalDictionary('two', '第二词典', 'StarDict', 2, true));
    await tester.pumpWidget(app(DictionaryLookup(word: '苹果', store: store)));
    await tester.pumpAndSettle();
    expect(find.text('来源：本地词典 · 本地导入'), findsOneWidget);
    expect(find.text('来源：第二词典 · 本地导入'), findsOneWidget);
    await tester.tap(find.text('查询字典（可单选或多选）'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, '第二词典'));
    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();
    expect(find.text('来源：第二词典 · 本地导入'), findsNothing);
    expect((await DictionaryPreferences.load()).localIds, {'one'});
    await tester.tap(find.text('查询字典（可单选或多选）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选本地'));
    await tester.tap(find.widgetWithText(FilledButton, '查询'));
    await tester.pumpAndSettle();
    expect(find.text('来源：第二词典 · 本地导入'), findsOneWidget);
    expect(store.items.every((d) => d.enabled), true);
    expect(tester.takeException(), isNull);
  });
  testWidgets('selected local misses are shown even alongside matching results',
      (tester) async {
    final store = FakeDictionaries()
      ..items.addAll([
        const LocalDictionary('two', '柯林斯词典', 'MDX', 2, true),
        const LocalDictionary('three', '未勾选词典', 'MDX', 2, true),
        const LocalDictionary('four', '已停用词典', 'MDX', 2, false),
      ])
      ..delayed = Completer<List<DictionaryEntry>>();
    await DictionaryPreferences(localIds: {'one', 'two', 'four'}).save();
    await tester.pumpWidget(app(DictionaryLookup(word: 'apple', store: store)));
    await tester.pump();
    expect(find.textContaining('无条目'), findsNothing);
    store.delayed!.complete(
        [const DictionaryEntry('本地词典', 'apple', '苹果', dictionaryId: 'one')]);
    await tester.pumpAndSettle();
    expect(find.text('柯林斯词典 · 无条目'), findsOneWidget);
    expect(find.text('本地词典 · 无条目'), findsNothing);
    expect(find.text('未勾选词典 · 无条目'), findsNothing);
    expect(find.text('已停用词典 · 无条目'), findsNothing);
    expect(find.text('来源：本地词典 · 本地导入'), findsOneWidget);
    store.delayed = Completer<List<DictionaryEntry>>();
    await tester.tap(find.byTooltip('查询'));
    await tester.pump();
    store.delayed!.completeError(const DictionaryFailure('io'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无条目'), findsNothing);
    expect(find.textContaining('无法读取文件'), findsOneWidget);
  });

  testWidgets('all selected local misses name every queried dictionary',
      (tester) async {
    final store = FakeDictionaries()
      ..items.add(const LocalDictionary('two', '柯林斯词典', 'MDX', 2, true));
    await tester.pumpWidget(app(DictionaryLookup(word: '孝宗', store: store)));
    await tester.pumpAndSettle();
    expect(find.text('本地词典 · 无条目'), findsOneWidget);
    expect(find.text('柯林斯词典 · 无条目'), findsOneWidget);
  });
  testWidgets(
      'local HTML appears inline without a duplicate definition or route button',
      (tester) async {
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = FakeDictionaryBrowser();
    addTearDown(() {
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
    final store = FakeDictionaries()
      ..delayed = Completer<List<DictionaryEntry>>();
    await tester
        .pumpWidget(app(DictionaryLookup(word: 'sample', store: store)));
    store.delayed!.complete([
      const DictionaryEntry('本地词典', 'sample', '',
          dictionaryId: 'one', html: '<script>document.write("动态词条")</script>')
    ]);
    await tester.pumpAndSettle();
    expect(find.byType(DictionaryOriginal), findsOneWidget);
    expect(find.widgetWithText(TextButton, '原版图文 / 音频'), findsNothing);
    expect(find.textContaining('此词条含图文或动态内容'), findsNothing);
    expect(find.text('来源：本地词典 · 本地导入'), findsOneWidget);
    expect(find.textContaining('重新导入 MDX'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('compact local text removes blank rows without dropping examples', () {
    expect(
        compactDictionaryText(
            '新本子\r\n \r\nnew notebook\n\n\n新的绷带\n\nnew bandage'),
        '新本子\nnew notebook\n新的绷带\nnew bandage');
  });
  testWidgets(
      'dictionary results use compact typography and respect text scaling',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final embedded in [false, true]) {
      await tester.pumpWidget(app(MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: DictionaryLookup(
              key: ValueKey(embedded),
              word: '苹果',
              embedded: embedded,
              store: FakeDictionaries()))));
      await tester.pumpAndSettle();
      final definition = tester.widget<SelectableText>(find.byWidgetPredicate(
          (w) => w is SelectableText && w.data == 'apple; apple tree'));
      expect(definition.style?.fontSize, 14);
      expect(definition.style?.height, 1.4);
      expect(
          tester
              .widget<SelectableText>(find.byWidgetPredicate(
                  (w) => w is SelectableText && w.data == '苹果'))
              .style
              ?.fontSize,
          18);
      expect(
          MediaQuery.textScalerOf(
                  tester.element(find.text('apple; apple tree')))
              .scale(14),
          21);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
      'online is opt-in; slow and failed online lookup keeps local results',
      (tester) async {
    final online = FakeOnlineDictionary();
    await tester.pumpWidget(app(DictionaryLookup(
        word: '苹果', store: FakeDictionaries(), onlineService: online)));
    await tester.pumpAndSettle();
    expect(online.queries, isEmpty);
    await DictionaryPreferences(online: {OnlineDictionary.wiktionaryEn}).save();
    await tester.tap(find.byTooltip('查询'));
    await tester.pumpAndSettle();
    expect(online.queries, ['苹果']);
    expect(find.text('apple; apple tree'), findsOneWidget);
    expect(find.textContaining('查询中…'), findsOneWidget);
    online.result.completeError(Exception('private response body'));
    await tester.pumpAndSettle();
    expect(find.text('apple; apple tree'), findsOneWidget);
    expect(find.textContaining('在线查询暂不可用'), findsOneWidget);
    expect(find.textContaining('private response body'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'source picker cancels without changing consent or local selection on mobile',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 740);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
        app(DictionaryLookup(word: '苹果', store: FakeDictionaries())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查询字典（可单选或多选）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空本地'));
    await tester
        .ensureVisible(find.widgetWithText(CheckboxListTile, '维基词典 · 中文'));
    await tester.tap(find.widgetWithText(CheckboxListTile, '维基词典 · 中文'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    final prefs = await DictionaryPreferences.load();
    expect(prefs.localIds, isNull);
    expect(prefs.online, isEmpty);
    expect(find.text('apple; apple tree'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'empty source selection explains how to select instead of requiring another import',
      (tester) async {
    await DictionaryPreferences(localIds: {}).save();
    await tester.pumpWidget(
        app(DictionaryLookup(word: '苹果', store: FakeDictionaries())));
    await tester.pumpAndSettle();
    expect(find.text('尚未选择查询字典，请点击上方「查询字典」选择。'), findsOneWidget);
    expect(find.text('apple; apple tree'), findsNothing);
  });
  testWidgets('online response shows original source and returned license',
      (tester) async {
    await DictionaryPreferences(online: {OnlineDictionary.wiktionaryEn}).save();
    final online = FakeOnlineDictionary();
    online.result.complete([
      DictionaryEntry('Wiktionary · English', 'hello', 'A greeting.',
          sourceUri: Uri.parse('https://en.wiktionary.org/wiki/hello'),
          license: 'CC BY-SA 4.0',
          licenseUri:
              Uri.parse('https://creativecommons.org/licenses/by-sa/4.0'),
          attribution: 'Wiktionary contributors')
    ]);
    await tester.pumpWidget(app(DictionaryLookup(
        word: 'hello', store: FakeDictionaries(), onlineService: online)));
    await tester.pumpAndSettle();
    expect(find.text('来源：Wiktionary · English'), findsOneWidget);
    expect(find.text('CC BY-SA 4.0'), findsOneWidget);
    expect(find.text('原词条 / 贡献者'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('closing cancels outstanding online request', (tester) async {
    await DictionaryPreferences(online: {OnlineDictionary.wiktionaryEn}).save();
    final online = FakeOnlineDictionary();
    await tester.pumpWidget(app(DictionaryLookup(
        word: 'apple', store: FakeDictionaries(), onlineService: online)));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(online.token!.isCancelled, true);
    online.result.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Chinese selection and edited queries reach enabled dictionaries',
      (tester) async {
    final store = FakeDictionaries();
    await tester.pumpWidget(app(DictionaryLookup(word: ' 苹果 ', store: store)));
    await tester.pumpAndSettle();
    expect(store.queries, ['苹果']);
    expect(find.text('apple; apple tree'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '中国');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(store.queries, ['苹果', '中国']);
    expect(find.text('China'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(390, 844), const Size(1200, 900)]) {
    testWidgets('lookup scrolls with normal text and accessible close at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final store = FakeDictionaries();
      await tester.pumpWidget(app(Builder(
          builder: (context) => TextButton(
              onPressed: () => showReaderPopup(context,
                  builder: (_) =>
                      DictionaryLookup(word: 'apple', store: store)),
              child: const Text('Open')))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(store.queries, ['apple']);
      expect(find.text('本地词典'), findsOneWidget);
      final definition =
          tester.widgetList<SelectableText>(find.byType(SelectableText)).last;
      expect(definition.style!.fontSize, 14);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(DictionaryLookup), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('no bundled dictionary, manage shortcut and exact-match feedback',
      (tester) async {
    final store = FakeDictionaries()..items = [];
    await tester.pumpWidget(app(DictionaryLookup(word: 'apple', store: store)));
    await tester.pumpAndSettle();
    expect(find.text('尚无已启用的字典。请先导入或启用本地字典。'), findsOneWidget);
    await tester.tap(find.text('导入 / 管理字典'));
    await tester.pumpAndSettle();
    expect(find.byType(DictionarySettings), findsOneWidget);
    expect(find.text('导入字典'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    store.items = [const LocalDictionary('one', 'Test', 'MDX', 1, true)];
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('未找到完全匹配的词条，可修改词语后重试。'), findsOneWidget);
  });
  testWidgets('dictionary enable, rename and confirmed deletion',
      (tester) async {
    final store = FakeDictionaries();
    await tester.pumpWidget(app(DictionarySettings(store: store)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.items.single.enabled, isFalse);
    await tester.ensureVisible(find.text('改名'));
    await tester.tap(find.text('改名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新名称');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(store.items.single.name, '新名称');
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.items, hasLength(1));
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '删除').last);
    await tester.pumpAndSettle();
    expect(store.items, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('closing during a lookup does not update a disposed widget',
      (tester) async {
    final store = FakeDictionaries()
      ..delayed = Completer<List<DictionaryEntry>>();
    await tester.pumpWidget(app(DictionaryLookup(word: 'apple', store: store)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    store.delayed!.complete([]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'selection overlay closes before opening dictionary from stable context',
      (tester) async {
    await Prefs()
        .saveSelectionToolbar(const SelectionToolbarConfig().copyWith(items: [
      ...SelectionToolbarConfig.initialItems
          .where((i) => i.id == 'dictionary')
          .map((i) => i.copyWith(enabled: true)),
      ...SelectionToolbarConfig.initialItems.where((i) => i.id != 'dictionary')
    ]));
    final temp = Directory.systemTemp.createTempSync('modu-dictionary-menu-');
    final oldPath = documentPath;
    documentPath = temp.path;
    try {
      var show = true;
      await tester.pumpWidget(app(StatefulBuilder(
          builder: (context, setState) => Column(children: [
                if (show)
                  ExcerptMenu(
                      annoCfi: 'epubcfi(/6/2!/4/2/1:0)',
                      annoContent: 'apple',
                      onClose: () => setState(() => show = false),
                      footnote: false,
                      decoration: const BoxDecoration(),
                      toggleTranslationMenu: () {},
                      toggleReaderNoteMenu: ({bool? show}) {},
                      openReaderNoteMenu: (_) async {},
                      onNoteCreated: (_) {},
                      axis: Axis.horizontal,
                      reverse: false)
                else
                  const Text('Reader')
              ]))));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('字典'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(find.byType(ExcerptMenu), findsNothing);
      expect(find.byType(DictionaryLookup), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'apple');
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('Reader'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      documentPath = oldPath;
      temp.deleteSync(recursive: true);
    }
  });
}
