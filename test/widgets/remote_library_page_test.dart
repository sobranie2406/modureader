import 'dart:async';
import 'dart:io';

import 'package:anx_reader/page/home_page/remote_library_page.dart';
import 'package:anx_reader/page/settings_page/remote_library.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/service/remote_library/library_view_options.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _Library extends WebdavLibrary {
  _Library()
      : super(const LibraryConnection(url: 'https://example.com/books/'));
  int listings = 0;
  bool failFolder = false;
  Completer<List<LibraryEntry>>? scan;
  CancelToken? scanToken;
  Uri? scannedDirectory;
  final downloads = <Uri>[];
  @override
  Future<List<LibraryEntry>> discoverBooks(Uri directory,
      {required CancelToken cancelToken}) async {
    scannedDirectory = directory;
    scanToken = cancelToken;
    if (scan != null) {
      cancelToken.whenCancel.then((error) {
        if (!scan!.isCompleted) scan!.completeError(error);
      });
      return scan!.future;
    }
    return [
      LibraryEntry(directory.resolve('one.txt'), 'one.txt', false, 10),
      LibraryEntry(directory.resolve('sub/two.umd'), 'two.umd', false, 10),
      LibraryEntry(directory.resolve('three.pdf'), 'three.pdf', false, 10),
    ];
  }

  @override
  Future<void> download(LibraryEntry entry, File target, CancelToken cancel,
      void Function(int, int) onProgress) async {
    downloads.add(entry.uri);
    throw const FormatException('Synthetic failed download');
  }

  @override
  Future<List<LibraryEntry>> list(Uri directory,
      {CancelToken? cancelToken}) async {
    listings++;
    if (failFolder && directory != root)
      throw const LibraryListingException('tooLarge');
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
  testWidgets(
      'folder import uses multi-select, downloads only after confirmation, and continues after failure',
      (tester) async {
    final temp =
        Directory.systemTemp.createTempSync('modu-remote-folder-test-');
    final oldPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    addTearDown(() {
      PathProviderPlatform.instance = oldPaths;
      temp.deleteSync(recursive: true);
    });
    await LibraryConnectionStore.save(
        const LibraryConnection(url: 'https://example.com/books/'));
    final library = _Library();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: RemoteLibraryPage(clientFactory: (_) => library))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import folder'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(library.scannedDirectory, library.root.resolve('folder/'));
    expect(find.text('Select books to import'), findsOneWidget);
    expect(find.text('sub/two.umd'), findsOneWidget);
    expect(library.downloads, isEmpty);
    await tester.tap(find
        .byKey(ValueKey(library.root.resolve('folder/one.txt').toString())));
    await tester.pump();
    expect(find.text('2 books selected'), findsOneWidget);
    await tester.tap(find.text('Import selected'));
    await tester.pump();
    for (var i = 0;
        i < 100 &&
            find
                .textContaining('Imported 0, skipped 0 duplicates, failed 2.')
                .evaluate()
                .isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(library.downloads.length, 2);
    await tester.pumpAndSettle();
    expect(library.downloads, [
      library.root.resolve('folder/sub/two.umd'),
      library.root.resolve('folder/three.pdf')
    ]);
    expect(find.textContaining('Imported 0, skipped 0 duplicates, failed 2.'),
        findsOneWidget);
    expect(temp.listSync(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('current folder selection can be cancelled without downloading',
      (tester) async {
    await LibraryConnectionStore.save(
        const LibraryConnection(url: 'https://example.com/books/'));
    final library = _Library();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: RemoteLibraryPage(clientFactory: (_) => library))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import current folder'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(library.scannedDirectory, library.root);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Cancel')));
    await tester.pumpAndSettle();
    expect(library.downloads, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(
                IconButton, Icons.drive_folder_upload_outlined))
            .onPressed,
        isNotNull);
  });

  testWidgets('cancelling a folder scan stops work and restores controls',
      (tester) async {
    await LibraryConnectionStore.save(
        const LibraryConnection(url: 'https://example.com/books/'));
    final library = _Library()..scan = Completer<List<LibraryEntry>>();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: RemoteLibraryPage(clientFactory: (_) => library))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Import current folder'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(library.scanToken!.isCancelled, isTrue);
    expect(library.downloads, isEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(
                IconButton, Icons.drive_folder_upload_outlined))
            .onPressed,
        isNotNull);
  });

  testWidgets(
      'failed directory keeps its own breadcrumb and a directory-specific error',
      (tester) async {
    await LibraryConnectionStore.save(
        const LibraryConnection(url: 'https://example.com/books/'));
    final library = _Library()..failFolder = true;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: RemoteLibraryPage(clientFactory: (_) => library))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('folder'));
    await tester.pumpAndSettle();
    expect(find.textContaining('folder/'), findsOneWidget);
    expect(find.textContaining('32 MiB'), findsOneWidget);
    expect(find.textContaining('512 MiB'), findsNothing);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(
                IconButton, Icons.drive_folder_upload_outlined))
            .onPressed,
        isNull);
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
    await tester.scrollUntilVisible(find.text('Test connection'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Test connection'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('settings save persists the password without enabling sync',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemoteLibrarySettings())));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField).at(0), 'https://example.com/books/');
    await tester.enterText(find.byType(TextField).at(1), 'reader');
    await tester.enterText(find.byType(TextField).at(2), 'session-secret');
    await tester.scrollUntilVisible(find.text('Save'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {LibraryConnectionStore.key});
    expect(prefs.getString(LibraryConnectionStore.key),
        contains('session-secret'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RemoteLibrarySettings())));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        'session-secret');
    expect(tester.widget<TextField>(find.byType(TextField).at(2)).obscureText,
        isTrue);
    await tester.scrollUntilVisible(find.text('Clear connection'), 180,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear connection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(prefs.getString(LibraryConnectionStore.key), '');
    expect(await LibraryConnectionStore.load(), isNull);
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
