import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/search_repository.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/search_result_data.dart';
import 'package:anx_reader/page/search/search_page.dart';
import 'package:anx_reader/providers/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchFixture extends SearchRepository {
  final queries = <String>[];
  final scopes = <int?>[];
  @override
  Future<SearchResultData> search(String keyword,
      {int? bookId, DateTime? from, DateTime? to, int? limit}) async {
    queries.add(keyword);
    scopes.add(bookId);
    return SearchResultData.empty;
  }
}

void main() {
  testWidgets('notes search hides books and clearing cancels pending search',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final repository = SearchFixture();
    await tester.pumpWidget(ProviderScope(
      overrides: [searchRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            ...GlobalMaterialLocalizations.delegates
          ],
          home: const SearchPage(notesOnly: true, bookId: 42)),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '关键词');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repository.queries, ['关键词']);
    expect(repository.scopes, [42]);
    final context = tester.element(find.byType(SearchPage));
    expect(find.text(L10n.of(context).books), findsNothing);
    expect(find.text(L10n.of(context).notes), findsOneWidget);
    await tester.enterText(find.byType(TextField), '取消搜索');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repository.queries, ['关键词']);
    expect(repository.scopes, [42]);
    expect(find.text(L10n.of(context).startTypingToSearch), findsOneWidget);
  });
}
