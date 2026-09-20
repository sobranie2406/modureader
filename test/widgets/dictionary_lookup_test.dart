import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/settings_page/dictionaries.dart';
import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:anx_reader/widgets/dictionary/dictionary_lookup.dart';
import 'package:anx_reader/widgets/reading_page/reader_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<List<DictionaryEntry>> lookup(String word) async {
    queries.add(word);
    if (delayed != null) return delayed!.future;
    return items.any((d) => d.enabled) && word == 'apple'
        ? [DictionaryEntry(items.first.name, word, '苹果\n${'文字释义。' * 300}')]
        : [];
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('zh'));
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
      expect(definition.style!.fontSize, 16);
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
