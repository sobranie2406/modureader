import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/models/tag.dart';
import 'package:anx_reader/providers/tags.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/models/sync_state_model.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/page/home_page/bookshelf_page.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/bookshelf_pins.dart';
import 'package:anx_reader/widgets/bookshelf/folder_pin_menu.dart';
import 'package:anx_reader/widgets/bookshelf/book_folder.dart';
import 'package:anx_reader/widgets/bookshelf/book_opened_folder.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_service.dart';
import 'package:anx_reader/service/knowledge/knowledge_engine.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/bookshelf/book_bottom_sheet.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/bookshelf/book_embedding_model_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart' as legacy;

class _Groups extends GroupDao {
  @override
  Future<List<TbGroup>> build() async => [const TbGroup(id: 42, name: '测试文件夹')];
}

class _IdleSync extends Notifier<SyncStateModel> implements Sync {
  @override
  SyncStateModel build() => const SyncStateModel(
      direction: SyncDirection.both,
      isSyncing: false,
      total: 0,
      count: 0,
      fileName: '');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShelfTags extends TagList {
  @override
  Future<List<Tag>> build() async => [];
}

class _ShelfBooks extends BookList {
  _ShelfBooks(this.books);
  final List<Book> books;
  List<int>? moved;
  String? createdName;
  int? destination;
  @override
  Future<List<List<Book>>> build() async =>
      books.map((book) => [book]).toList();
  @override
  Future<void> moveBooksToFolder(Iterable<int> ids,
      {int? groupId, String? newFolderName}) async {
    moved = ids.toList();
    createdName = newFolderName;
    destination = groupId;
    state = AsyncData(groupBooks(books
        .map((book) => moved!.contains(book.id)
            ? book.copyWith(groupId: groupId ?? 42)
            : book)
        .toList()));
  }
}

class _SyncStatus extends SyncStatus {
  void syncing(bool active) {
    state = AsyncData(SyncStatusModel(
      localOnly: [],
      remoteOnly: [],
      both: active ? [] : [789],
      nonExistent: [],
      downloading: [],
      uploading: active ? [789] : [],
    ));
  }

  @override
  Future<SyncStatusModel> build() async => const SyncStatusModel(
        localOnly: [],
        remoteOnly: [],
        both: [],
        nonExistent: [],
        downloading: [],
        uploading: [],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late String oldPath;
  final book =
      Book.mock().copyWith(id: 789, title: '菜单测试书', filePath: 'file/menu.epub');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    oldPath = documentPath;
    temporary = await Directory.systemTemp.createTemp('modu-book-menu-');
    documentPath = temporary.path;
    await Directory('${temporary.path}/file').create();
    await File(book.fileFullPath).writeAsString('测试书籍');
  });
  tearDown(() async {
    documentPath = oldPath;
    await temporary.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester,
      {bool bottom = false,
      bool folder = false,
      bool singleInFolder = false,
      bool shelf = false,
      bool selection = false,
      void Function(Book, bool)? select}) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          syncProvider.overrideWith(_IdleSync.new),
          syncStatusProvider.overrideWith(_SyncStatus.new),
          groupDaoProvider.overrideWith(_Groups.new),
          tagListProvider.overrideWith(_ShelfTags.new),
          bookListProvider.overrideWith(() => _ShelfBooks([
                book,
                book.copyWith(id: 790, coverPath: 'cover/second.png'),
              ])),
        ],
        child: legacy.ChangeNotifierProvider<Prefs>.value(
            value: Prefs(),
            child: MaterialApp(
              locale: const Locale('zh'),
              supportedLocales: L10n.supportedLocales,
              localizationsDelegates: const [
                L10n.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate
              ],
              home: shelf
                  ? const BookshelfPage()
                  : Scaffold(
                      body: Center(
                          child: bottom
                              ? BookBottomSheet(book: book)
                              : SizedBox(
                                  width: 160,
                                  height: 340,
                                  child: folder
                                      ? BookFolder(
                                          books: [
                                            book.copyWith(groupId: 42),
                                            if (!singleInFolder)
                                              book.copyWith(
                                                  id: 790, groupId: 42)
                                          ],
                                          selectionMode: selection,
                                          onSelectionChanged: select,
                                        )
                                      : BookItem(
                                          book: book,
                                          selectionMode: selection,
                                          onSelectionChanged: select)))),
            )),
      ));
      // Index badges read real file metadata; let that I/O complete outside the
      // widget test's fake clock before taking a menu snapshot.
      for (var i = 0; i < 3; i++) {
        await BookKnowledgeIndexService().hasIndex(book);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();
  }

  List<BookAction> actions(WidgetTester tester) => tester
      .widgetList<PopupMenuItem<BookAction>>(
          find.byType(PopupMenuItem<BookAction>))
      .map((w) => w.value!)
      .toList();

  for (final createNew in [true, false]) {
    testWidgets('narrow bookshelf batch folder action create=$createNew',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await mount(tester, shelf: true);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '新建文件夹'))
              .onPressed,
          isNull);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 本'), findsOneWidget);
      await tester.tap(find.text(createNew ? '新建文件夹' : '移入文件夹'));
      await tester.pumpAndSettle();
      if (createNew) {
        await tester.enterText(find.byType(TextField), '批量新建');
      } else {
        await tester.tap(find.text('测试文件夹'));
        await tester.pump();
      }
      await tester.tap(find.text(createNew ? '创建并移入' : '移入'));
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(BookshelfPage)));
      final books = container.read(bookListProvider.notifier) as _ShelfBooks;
      expect(books.moved, [789, 790]);
      expect(createNew ? books.createdName : books.destination,
          createNew ? '批量新建' : 42);
      expect(find.text('选择'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('one-book folder still opens as folder and exposes folder menu',
      (tester) async {
    await mount(tester, folder: true, singleInFolder: true);
    expect(find.text('测试文件夹'), findsOneWidget);
    expect(find.byTooltip('文件夹操作'), findsOneWidget);
    expect(find.byType(BookItem), findsNothing);
    await tester.tap(find.byType(BookFolder));
    await tester.pumpAndSettle();
    expect(find.byType(BookOpenedFolder), findsOneWidget);
    expect(find.byType(BookItem), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder tile long press offers pin, selection mode hides menu',
      (tester) async {
    await mount(tester, folder: true);
    await tester.longPress(find.byType(BookFolder));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    await tester.tap(find.byTooltip('文件夹操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();
    var selected = 0;
    await mount(tester, folder: true, selection: true, select: (_, value) {
      if (value) selected++;
    });
    expect(find.byTooltip('文件夹操作'), findsNothing);
    await tester.tap(find.byType(BookFolder));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS
  ]) {
    testWidgets(
        '$platform: open menu remains actionable through sync start and completion',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await mount(tester);
        final container =
            ProviderScope.containerOf(tester.element(find.byType(BookItem)));
        final status =
            container.read(syncStatusProvider.notifier) as _SyncStatus;
        await tester.tap(find.byTooltip('书籍操作'));
        await tester.pumpAndSettle();
        status.syncing(true);
        await tester.pump();
        status.syncing(false);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('book-action-vectorModel')));
        await tester.pumpAndSettle();
        expect(find.byType(BookEmbeddingModelDialog), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('cover dots, long press and drag bottom bar share all actions',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('书籍操作'));
    await tester.pumpAndSettle();
    expect(actions(tester), BookAction.values);
    final labels = tester
        .widgetList<PopupMenuItem<BookAction>>(
            find.byType(PopupMenuItem<BookAction>))
        .map((w) => ((w.child as ListTile).title as Text).data)
        .toList();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(BookItem));
    await tester.pumpAndSettle();
    expect(actions(tester), BookAction.values);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await mount(tester, bottom: true);
    await tester.tap(find.byTooltip('书籍操作'));
    await tester.pumpAndSettle();
    expect(actions(tester), BookAction.values);
    expect(
        tester
            .widgetList<PopupMenuItem<BookAction>>(
                find.byType(PopupMenuItem<BookAction>))
            .map((w) => ((w.child as ListTile).title as Text).data)
            .toList(),
        labels);
    expect(find.textContaining('更多操作（'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book menu toggles persistent pin without changing reading data',
      (tester) async {
    await mount(tester);
    final position = book.lastReadPosition;
    final time = book.updateTime;
    final container =
        ProviderScope.containerOf(tester.element(find.byType(BookItem)));
    await tester.tap(find.byTooltip('书籍操作'));
    await tester.pumpAndSettle();
    expect(find.text('置顶'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('book-action-pin')));
    await tester.pumpAndSettle();
    expect(container.read(bookshelfPinsProvider), contains(bookPinKey(book)));
    expect(book.lastReadPosition, position);
    expect(book.updateTime, time);
    await tester.tap(find.byTooltip('书籍操作'));
    await tester.pumpAndSettle();
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('book-action-pin')));
    await tester.pumpAndSettle();
    expect(container.read(bookshelfPinsProvider),
        isNot(contains(bookPinKey(book))));
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder menu can pin and unpin independently of a book',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      home: const Scaffold(body: FolderPinMenu(groupId: 789)),
    )));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(FolderPinMenu)));
    await tester.tap(find.byTooltip('文件夹操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶'));
    await tester.pumpAndSettle();
    expect(container.read(bookshelfPinsProvider), {folderPinKey(789)});
    await tester.tap(find.byTooltip('文件夹操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();
    expect(container.read(bookshelfPinsProvider), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'index status and unavailable file operations are consistent in both entrances',
      (tester) async {
    const chunk = KnowledgeChunk(
        id: 'chunk', bookId: '789', chapterId: '1', text: '测试书籍');
    await tester.runAsync(() async =>
        (await BookKnowledgeIndexService().storeFor(book))
            .save(KnowledgeIndexSnapshot(
          bookId: '789',
          contentHash: 'fixture',
          chunks: [chunk],
          vectors: [
            VectorEntry(chunk: chunk, vector: [1, 0])
          ],
          embeddingMode: 'local',
          embeddingModelId: 'fixture',
          embeddingDimensions: 2,
        )));
    expect(
        await tester.runAsync(() => BookKnowledgeIndexService().hasIndex(book)),
        isTrue);
    for (final bottom in [false, true]) {
      await mount(tester, bottom: bottom);
      await tester.tap(find.byTooltip('书籍操作'));
      await tester.pumpAndSettle();
      expect(find.text('重新向量化'), findsOneWidget,
          reason:
              'bottom=$bottom; ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList()}');
      expect(
          tester
              .widget<PopupMenuItem<BookAction>>(
                  find.byKey(const ValueKey('book-action-release')))
              .enabled,
          isFalse);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
    File(book.fileFullPath).deleteSync();
    for (final bottom in [false, true]) {
      await mount(tester, bottom: bottom);
      await tester.tap(find.byTooltip('书籍操作'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<PopupMenuItem<BookAction>>(
                  find.byKey(const ValueKey('book-action-share')))
              .enabled,
          isFalse);
      expect(
          tester
              .widget<PopupMenuItem<BookAction>>(
                  find.byKey(const ValueKey('book-action-release')))
              .enabled,
          isFalse);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('selection-mode long press selects instead of opening actions',
      (tester) async {
    var selected = false;
    await mount(tester,
        selection: true, select: (_, value) => selected = value);
    await tester.longPress(find.byType(BookItem));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(find.byType(PopupMenuItem<BookAction>), findsNothing);
  });

  testWidgets('delete requires confirmation and cancel preserves the book',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('书籍操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('book-action-delete')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(File(book.fileFullPath).existsSync(), isTrue);
    expect(find.byType(BookItem), findsOneWidget);
  });
}
