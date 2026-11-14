import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/service/dictionary/online_dictionary.dart';
import 'package:modu_reader/service/dictionary/dictionary_preferences.dart';
import 'package:modu_reader/service/plugins/plugin_dictionary_transform.dart';
import 'package:modu_reader/widgets/dictionary/dictionary_lookup.dart';
import 'dictionary_lookup_test.dart' show FakeDictionaries, app;

class _Transforms extends PluginDictionaryTransform {
  final words = <String>[];
  List<String> result = ['apple', 'appl'];
  Completer<List<String>>? delayed;
  @override
  Future<List<String>> candidates(String word,
      {required bool Function() isContextValid}) {
    words.add(word);
    return delayed?.future ?? Future.value(result);
  }
}

class _Mixed extends FakeDictionaries {
  _Mixed() {
    items
        .add(const LocalDictionary('two', 'Second dictionary', 'MDX', 2, true));
  }
  final selected = <Set<String>?>[];
  @override
  Future<List<DictionaryEntry>> lookup(String word,
      {Set<String>? dictionaryIds}) async {
    queries.add(word);
    selected.add(dictionaryIds?.toSet());
    if (word == 'apples') {
      return [
        const DictionaryEntry('First', 'apples', 'EXACT ORIGINAL',
            dictionaryId: 'one')
      ];
    }
    if (word == 'apple') {
      return [
        const DictionaryEntry('Second', 'apple', 'FALLBACK',
            dictionaryId: 'two')
      ];
    }
    return [];
  }
}

class _Online extends OnlineDictionaryService {
  final words = <String>[];
  @override
  Future<List<DictionaryEntry>> lookup(OnlineDictionary source, String word,
      {CancelToken? cancelToken}) async {
    words.add(word);
    return word == 'apple'
        ? [const DictionaryEntry('Online', 'apple', 'ONLINE FALLBACK')]
        : [];
  }
}

class _ShortLocal extends FakeDictionaries {
  @override
  Future<List<DictionaryEntry>> lookup(String word,
      {Set<String>? dictionaryIds}) async {
    queries.add(word);
    return word == 'apple'
        ? [
            const DictionaryEntry('Local', 'apple', 'LOCAL FALLBACK',
                dictionaryId: 'one')
          ]
        : [];
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    await L10n.delegate.load(const Locale('zh'));
  });
  testWidgets(
      'exact entries do not invoke transformations or rewrite the input',
      (tester) async {
    final store = FakeDictionaries(), transforms = _Transforms();
    await tester.pumpWidget(app(
        DictionaryLookup(word: 'apple', store: store, transforms: transforms)));
    await tester.pumpAndSettle();
    expect(store.queries, ['apple']);
    expect(transforms.words, isEmpty);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'apple');
  });
  testWidgets('a miss tries candidates in order and stops at the first hit',
      (tester) async {
    final store = FakeDictionaries(), transforms = _Transforms();
    await tester.pumpWidget(app(DictionaryLookup(
        word: 'apples', store: store, transforms: transforms)));
    await tester.pumpAndSettle();
    expect(store.queries, ['apples', 'apple']);
    expect(transforms.words, ['apples']);
    expect(find.widgetWithText(SelectableText, 'apple'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'apples');
  });
  testWidgets(
      'each dictionary keeps exact entries and fills only missing sources',
      (tester) async {
    final store = _Mixed();
    await tester.pumpWidget(app(DictionaryLookup(
        word: 'apples', store: store, transforms: _Transforms())));
    await tester.pumpAndSettle();
    expect(store.queries, ['apples', 'apple']);
    expect(store.selected.last, {'two'});
    expect(find.text('EXACT ORIGINAL'), findsOneWidget);
    expect(find.text('FALLBACK'), findsOneWidget);
  });
  testWidgets(
      'original results show while another dictionary awaits candidates',
      (tester) async {
    final transforms = _Transforms()..delayed = Completer<List<String>>();
    await tester.pumpWidget(app(DictionaryLookup(
        word: 'apples', store: _Mixed(), transforms: transforms)));
    for (var frame = 0;
        frame < 10 && find.text('EXACT ORIGINAL').evaluate().isEmpty;
        frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('EXACT ORIGINAL'), findsOneWidget);
    transforms.delayed!.complete(['apple']);
    await tester.pumpAndSettle();
    expect(find.text('FALLBACK'), findsOneWidget);
  });
  testWidgets('a new query ignores delayed candidates from the previous word',
      (tester) async {
    final store = FakeDictionaries();
    final transforms = _Transforms()..delayed = Completer<List<String>>();
    await tester.pumpWidget(app(DictionaryLookup(
        word: 'apples', store: store, transforms: transforms)));
    for (var frame = 0;
        frame < 10 &&
            (transforms.words.isEmpty ||
                find.byType(TextField).evaluate().isEmpty);
        frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.enterText(find.byType(TextField), 'apple');
    await tester.tap(find.byIcon(Icons.search));
    await tester.pump();
    transforms.delayed!.complete(['orange']);
    await tester.pumpAndSettle();
    expect(store.queries, ['apples', 'apple']);
    expect(find.widgetWithText(SelectableText, 'apple'), findsOneWidget);
    expect(find.widgetWithText(SelectableText, 'orange'), findsNothing);
  });
  testWidgets(
      'online and local misses share one transformation and keep source order',
      (tester) async {
    await DictionaryPreferences(online: {OnlineDictionary.wiktionaryEn}).save();
    final store = _ShortLocal(), transforms = _Transforms(), online = _Online();
    addTearDown(online.close);
    await tester.pumpWidget(app(DictionaryLookup(
        word: 'apples',
        store: store,
        transforms: transforms,
        onlineService: online)));
    await tester.pumpAndSettle();
    expect(store.queries, ['apples', 'apple']);
    expect(online.words, ['apples', 'apple']);
    expect(transforms.words, ['apples']);
    expect(find.text('ONLINE FALLBACK'), findsOneWidget);
  });
  testWidgets('without a plugin the original exact-only query is unchanged',
      (tester) async {
    final store = FakeDictionaries();
    await tester
        .pumpWidget(app(DictionaryLookup(word: 'apples', store: store)));
    await tester.pumpAndSettle();
    expect(store.queries, ['apples']);
    expect(find.widgetWithText(SelectableText, 'apple'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
