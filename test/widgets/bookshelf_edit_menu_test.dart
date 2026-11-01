import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/sync_status.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/providers/sync_status.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/widgets/bookshelf/book_folder.dart';
import 'package:anx_reader/widgets/bookshelf/book_opened_folder.dart';
import 'package:flutter/material.dart';
import 'package:anx_reader/widgets/common/app_scroll_behavior.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

class _SyncStatus extends SyncStatus {
  @override
  Future<SyncStatusModel> build() async => const SyncStatusModel(
      localOnly: [],
      remoteOnly: [],
      both: [],
      nonExistent: [],
      downloading: [],
      uploading: []);
}

class _Groups extends GroupDao {
  @override
  Future<List<TbGroup>> build() async => [const TbGroup(id: 2, name: 'Folder')];
}

Widget app(Widget child, {BookList? books}) => ProviderScope(
      overrides: [
        if (books != null) bookListProvider.overrideWith(() => books),
        syncStatusProvider.overrideWith(_SyncStatus.new),
        groupDaoProvider.overrideWith(_Groups.new),
      ],
      child: provider.ChangeNotifierProvider.value(
        value: Prefs(),
        child: MaterialApp(
          scrollBehavior: const AppScrollBehavior().copyWith(
              physics: const BouncingScrollPhysics()),
          locale: const Locale('en'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: const [
            L10n.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  for (final grouped in [false, true]) {
    testWidgets('shelf ${grouped ? 'folder' : 'book'} menu requires editing',
        (tester) async {
      final book = Book.mock().copyWith(
          title: 'Example',
          filePath: 'file/example.epub',
          coverPath: 'cover/missing.png',
          groupId: grouped ? 2 : 0);
      var editing = false;
      final selectedIds = <int>{};
      await tester.pumpWidget(app(StatefulBuilder(
        builder: (context, setState) => Column(children: [
          TextButton(
            onPressed: () => setState(() {
              editing = false;
              selectedIds.clear();
            }),
            child: const Text('Done'),
          ),
          SizedBox(
            width: 160,
            height: 320,
            child: BookFolder(
              books: [book],
              selectionMode: editing,
              selectedBookIds: selectedIds,
              onSelectionChanged: (book, selected) => setState(() {
                editing = true;
                if (selected) {
                  selectedIds.add(book.id);
                } else {
                  selectedIds.remove(book.id);
                }
              }),
            ),
          ),
        ]),
      )));
      await tester.pumpAndSettle();
      final menu = find.byTooltip(grouped ? 'Folder actions' : 'Book actions');
      expect(menu, findsNothing);
      await tester.longPress(find.byType(BookFolder));
      await tester.pumpAndSettle();
      expect(editing, true);
      expect(selectedIds, {book.id});
      expect(menu, findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(tester.getCenter(menu).dx,
          greaterThan(tester.getCenter(find.byType(BookFolder)).dx));
      expect(tester.getCenter(menu).dy,
          greaterThan(tester.getCenter(find.byType(BookFolder)).dy));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Pin to top'), findsOneWidget);
      // Dismiss the popup without changing the selected books.
      await tester.tapAt(const Offset(780, 580));
      await tester.pumpAndSettle();
      expect(find.text('Pin to top'), findsNothing);
      expect(selectedIds, {book.id});
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(menu, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('inside folder long press reveals batch actions and cover menu',
      (tester) async {
    final book = Book.mock().copyWith(
        filePath: 'file/example.epub',
        coverPath: 'cover/missing.png',
        groupId: 2);
    await tester
        .pumpWidget(app(BookOpenedFolder(books: [book], groupName: 'Folder')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Book actions'), findsNothing);
    await tester.longPress(find.text(book.title).last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Book actions'), findsOneWidget);
    expect(find.text('New folder'), findsOneWidget);
    expect(find.text('Move to folder'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Book actions'), findsNothing);
    expect(find.text('New folder'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
