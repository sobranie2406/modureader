import 'package:anx_reader/page/home_page/remote_library_page.dart';
import 'package:anx_reader/page/settings_page/remote_library.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/service/remote_library/library_view_options.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Library extends WebdavLibrary {
  _Library()
      : super(const LibraryConnection(url: 'https://example.com/books/'));
  int listings = 0;
  @override
  Future<List<LibraryEntry>> list(Uri directory,
      {CancelToken? cancelToken}) async {
    listings++;
    return [
      LibraryEntry(root.resolve('folder/'), 'folder', true, null),
      LibraryEntry(root.resolve('B.pdf'), 'B.pdf', false, 10,
          createdAt: DateTime.utc(2026, 9, 1)),
      LibraryEntry(root.resolve('A.epub'), 'A.epub', false, 100,
          createdAt: DateTime.utc(2026, 9, 10)),
      LibraryEntry(root.resolve('unknown.txt'), 'unknown.txt', false, null),
    ];
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await LibraryConnectionStore.clear();
  });
  testWidgets('unconfigured remote library links to its own settings',
      (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: RemoteLibraryPage())));
    await tester.pumpAndSettle();
    expect(find.text('Remote library'), findsOneWidget);
    await tester.tap(find.text('Configure library WebDAV'));
    await tester.pumpAndSettle();
    expect(find.byType(RemoteLibrarySettings), findsOneWidget);
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings save does not persist passwords or enable sync',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemoteLibrarySettings())));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).at(0), 'https://example.com/books/');
    await tester.enterText(find.byType(TextField).at(1), 'reader');
    await tester.enterText(find.byType(TextField).at(2), 'session-secret');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {LibraryConnectionStore.key});
    expect(prefs.getString(LibraryConnectionStore.key),
        isNot(contains('session-secret')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'library sorting, filtering, refresh and saved preferences work on a narrow screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await LibraryConnectionStore.save(
        const LibraryConnection(url: 'https://example.com/books/'));
    final library = _Library();
    Widget page() => ProviderScope(
        child: MaterialApp(
            home: RemoteLibraryPage(clientFactory: (_) => library)));
    List<String> names() => tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data!)
        .toList();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(names(), ['folder', 'A.epub', 'B.pdf', 'unknown.txt']);
    await tester.tap(find.byKey(const ValueKey('library-sort-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Date added').last);
    await tester.pumpAndSettle();
    expect(names(), ['folder', 'B.pdf', 'A.epub', 'unknown.txt']);
    expect(find.textContaining('server creation time'), findsOneWidget);
    expect(find.textContaining('Not provided'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('library-sort-direction')));
    await tester.pumpAndSettle();
    expect(names(), ['folder', 'A.epub', 'B.pdf', 'unknown.txt']);
    expect(find.text('Descending'), findsOneWidget);
    expect(library.listings, 1); // Sort is local, not another network request.
    await tester.tap(find.byKey(const ValueKey('library-file-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PDF').last);
    await tester.pumpAndSettle();
    expect(names(), ['folder', 'B.pdf']);
    await tester.enterText(find.byType(TextField), 'b.PDF');
    await tester.pumpAndSettle();
    expect(names(), ['B.pdf']);
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(names(), ['folder', 'B.pdf']);
    expect(library.listings, 2);
    final saved = await LibraryViewOptionsStore.load();
    expect(saved.sort, LibrarySortField.createdAt);
    expect(saved.ascending, isFalse);
    expect(saved.filter, LibraryFileFilter.pdf);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Descending'), findsOneWidget);
    expect(find.text('Date added'), findsOneWidget);
    expect(names(), ['folder', 'B.pdf']);
    expect(tester.takeException(), isNull);
  });
}
