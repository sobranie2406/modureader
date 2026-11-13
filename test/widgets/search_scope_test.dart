import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/dao/search_repository.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/models/search_result_data.dart';
import 'package:modu_reader/page/search/search_page.dart';
import 'package:modu_reader/providers/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScopeCall {
  const ScopeCall(this.books, this.notes, this.bookId);

  final bool books;
  final bool notes;
  final int? bookId;
}

class ScopeFixture extends SearchRepository {
  final calls = <ScopeCall>[];
  @override
  Future<SearchResultData> search(String keyword,
      {int? bookId,
      DateTime? from,
      DateTime? to,
      int? limit,
      bool includeBooks = true,
      bool includeNotes = true}) async {
    calls.add(ScopeCall(includeBooks, includeNotes, bookId));
    return SearchResultData.empty;
  }
}

void main() {
  late ScopeFixture repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    repository = ScopeFixture();
  });

  Future<void> pumpSearch(WidgetTester tester,
      {bool notesOnly = false, int? bookId}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [searchRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: SearchPage(notesOnly: notesOnly, bookId: bookId),
      ),
    ));
    await tester.pumpAndSettle();
  }

  bool chipSelected(WidgetTester tester, String key) =>
      tester.widget<FilterChip>(find.byKey(ValueKey(key))).selected;

  testWidgets('both sources default on and can be narrowed independently',
      (tester) async {
    await pumpSearch(tester);
    expect(chipSelected(tester, 'search-scope-books'), isTrue);
    expect(chipSelected(tester, 'search-scope-notes'), isTrue);

    await tester.enterText(find.byType(TextField), '关键词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repository.calls.last.books, isTrue);
    expect(repository.calls.last.notes, isTrue);
    expect(repository.calls.last.bookId, isNull);
    expect(find.byKey(const ValueKey('search-section-books')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-section-notes')), findsOneWidget);

    // Notes only: the books source is not even queried.
    await tester.tap(find.byKey(const ValueKey('search-scope-books')));
    await tester.pumpAndSettle();
    expect(chipSelected(tester, 'search-scope-books'), isFalse);
    expect(repository.calls.last.books, isFalse);
    expect(repository.calls.last.notes, isTrue);
    expect(find.byKey(const ValueKey('search-section-books')), findsNothing);
    expect(find.byKey(const ValueKey('search-section-notes')), findsOneWidget);

    // Books only.
    await tester.tap(find.byKey(const ValueKey('search-scope-books')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-scope-notes')));
    await tester.pumpAndSettle();
    expect(repository.calls.last.books, isTrue);
    expect(repository.calls.last.notes, isFalse);
    expect(find.byKey(const ValueKey('search-section-books')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-section-notes')), findsNothing);

    // Nothing selected is announced instead of silently searching everything.
    final callsBefore = repository.calls.length;
    await tester.tap(find.byKey(const ValueKey('search-scope-books')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-scope-empty')), findsOneWidget);
    expect(repository.calls.length, callsBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-book search stays notes-only without a scope bar',
      (tester) async {
    await pumpSearch(tester, notesOnly: true, bookId: 42);
    expect(find.byKey(const ValueKey('search-scope-books')), findsNothing);
    expect(find.byKey(const ValueKey('search-scope-notes')), findsNothing);
    await tester.enterText(find.byType(TextField), '关键词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repository.calls.single.books, isFalse);
    expect(repository.calls.single.notes, isTrue);
    expect(repository.calls.single.bookId, 42);
    expect(tester.takeException(), isNull);
  });
  for (final mode in [(true, null), (false, 42)]) {
    testWidgets('note search scope stays consistent for $mode', (tester) async {
      await pumpSearch(tester, notesOnly: mode.$1, bookId: mode.$2);
      await tester.enterText(find.byType(TextField), 'keyword');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(repository.calls.single.books, isFalse);
      expect(repository.calls.single.notes, isTrue);
      expect(repository.calls.single.bookId, mode.$2);
      expect(find.byKey(const ValueKey('search-section-books')), findsNothing);
      expect(
          find.byKey(const ValueKey('search-section-notes')), findsOneWidget);
      expect(find.byType(FilterChip), findsNothing);
    });
  }
}
