import 'dart:async';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/widgets/bookshelf/book_folder.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/widgets/bookshelf/book_opened_folder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bookshelf_edit_menu_test.dart' show app;

class _Books extends BookList {
  final moves = <List<int>>[];
  List<List<Book>> entries = [];
  int? destination;
  String? name;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<List<List<Book>>> build() async {
    ref.keepAlive();
    return entries;
  }

  @override
  Future<void> moveBooksToFolder(Iterable<int> bookIds,
      {int? groupId, String? newFolderName}) async {
    if (fail) throw StateError('fixture');
    moves.add(bookIds.toList());
    destination = groupId;
    name = newFolderName;
    await pending?.future;
  }
}

Book book(int id, {int group = 0}) => Book.mock().copyWith(
    id: id,
    title: 'Book $id',
    groupId: group,
    filePath: 'file/$id.epub',
    coverPath: 'cover/$id.png');
Finder item(int id) =>
    find.byWidgetPredicate((w) => w is BookItem && w.book.id == id);

Future<TestGesture> startDrag(WidgetTester tester, int id) async {
  final gesture = await tester
      .startGesture(tester.getTopLeft(item(id)) + const Offset(40, 40));
  await tester.pump(const Duration(milliseconds: 600));
  return gesture;
}

Future<void> drop(
    WidgetTester tester, TestGesture gesture, Offset target) async {
  await gesture.moveTo(target);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  late _Books store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    store = _Books();
  });

  Future<void> shelf(WidgetTester tester,
      {bool list = false,
      bool folder = false,
      Set<int> selected = const {}}) async {
    final entries = [book(1), book(2), book(3, group: folder ? 2 : 0)];
    final selectedIds = {...selected};
    var editing = selected.isNotEmpty;
    await tester.pumpWidget(app(
        StatefulBuilder(
            builder: (context, setState) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: entries
                      .map((entry) => SizedBox(
                            width: 200,
                            height: 320,
                            child: BookFolder(
                              key: ValueKey(entry.id),
                              books: [entry],
                              listMode: list,
                              selectionMode: editing,
                              selectedBookIds: selectedIds,
                              selectedBooks: entries
                                  .where((b) => selectedIds.contains(b.id))
                                  .toList(),
                              onSelectionChanged: (b, value) => setState(() {
                                editing = true;
                                value
                                    ? selectedIds.add(b.id)
                                    : selectedIds.remove(b.id);
                              }),
                            ),
                          ))
                      .toList(),
                )),
        books: store));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'long-press drag creates a named folder; cancelling writes nothing',
      (tester) async {
    await shelf(tester);
    await drop(tester, await startDrag(tester, 1), tester.getCenter(item(3)));
    expect(find.text('New folder'), findsWidgets);
    expect(store.moves, isEmpty);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(store.moves, isEmpty);
    await drop(tester, await startDrag(tester, 1), tester.getCenter(item(3)));
    await tester.enterText(find.byType(TextField), 'Literature');
    await tester.tap(find.text('Create and move'));
    await tester.pumpAndSettle();
    expect(store.moves, [
      [1, 3]
    ]);
    expect(store.name, 'Literature');
    expect(tester.takeException(), isNull);
  });

  for (final list in [false, true]) {
    testWidgets('batch drag into folder, list=$list', (tester) async {
      await shelf(tester, list: list, folder: true, selected: {1, 2});
      final gesture = await startDrag(tester, 1);
      expect(find.byType(Badge), findsOneWidget);
      await drop(
          tester, gesture, tester.getCenter(find.byKey(const ValueKey(3))));
      expect(store.moves, [
        [1, 2]
      ]);
      expect(store.destination, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('batch onto an unselected book includes that book once',
      (tester) async {
    await shelf(tester, selected: {1, 2});
    await drop(tester, await startDrag(tester, 1), tester.getCenter(item(3)));
    await tester.enterText(find.byType(TextField), 'Batch');
    await tester.tap(find.text('Create and move'));
    await tester.pumpAndSettle();
    expect(store.moves, [
      [1, 2, 3]
    ]);
  });

  testWidgets('dragging unselected book never moves unrelated checked books',
      (tester) async {
    await shelf(tester, folder: true, selected: {2});
    await drop(tester, await startDrag(tester, 1),
        tester.getCenter(find.byKey(const ValueKey(3))));
    expect(store.moves, [
      [1]
    ]);
  });

  testWidgets('self/selected target and ordinary swipe never move books',
      (tester) async {
    await shelf(tester, selected: {1, 2});
    await drop(tester, await startDrag(tester, 1), tester.getCenter(item(2)));
    expect(find.byType(TextField), findsNothing);
    expect(store.moves, isEmpty);
    await tester.drag(item(1), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(store.moves, isEmpty);
  });

  Future<void> openFolder(WidgetTester tester) async {
    store.entries = [
      [book(1, group: 2), book(2, group: 2)]
    ];
    await tester.pumpWidget(app(
        Builder(
            builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => BookOpenedFolder(
                          books: [book(1, group: 2), book(2, group: 2)],
                          groupName: 'Folder')),
                  child: const Text('Open'),
                )),
        books: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('folder with many books can scroll to its last book',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await Prefs().prefs.setString('sortField', 'title');
    await Prefs().prefs.setString('sortOrder', 'ascending');
    final books = List.generate(9, (index) => book(index + 1, group: 2));
    store.entries = [books];
    await tester.pumpWidget(app(
        Center(
          child: SizedBox(
            width: 160,
            height: 320,
            child: BookFolder(books: books),
          ),
        ),
        books: store));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BookFolder));
    await tester.pumpAndSettle();
    // Flutter OH otherwise wraps this already-scrollable grid in another view.
    expect(tester.widget<AlertDialog>(find.byType(AlertDialog)).scrollable, false);
    final scrollable = find.descendant(
            of: find.byType(BookOpenedFolder),
            matching: find.byType(Scrollable))
        .first;
    await tester.drag(scrollable, const Offset(0, -500));
    await tester.pumpAndSettle();
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, greaterThan(0));
    expect(item(9).hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(item(9)).dy,
        lessThanOrEqualTo(tester.getBottomLeft(scrollable).dy + 1));
    expect(tester.takeException(), isNull);
    expect(store.moves, isEmpty);
  });

  testWidgets(
      'drop outside moves out, final drop on shelf target closes folder',
      (tester) async {
    await openFolder(tester);
    await drop(tester, await startDrag(tester, 1), const Offset(5, 5));
    expect(store.moves, [
      [1]
    ]);
    expect(store.destination, 0);
    expect(item(1), findsNothing);
    expect(item(2), findsOneWidget);
    final gesture = await startDrag(tester, 2);
    await drop(tester, gesture,
        tester.getCenter(find.byKey(const ValueKey('folder-shelf-drop'))));
    expect(store.moves, [
      [1],
      [2]
    ]);
    expect(find.byType(BookOpenedFolder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch out failure retains selection and allows retry',
      (tester) async {
    await openFolder(tester);
    await tester.longPress(item(1));
    await tester.pumpAndSettle();
    // In the compact folder the lower half may scroll under the action area.
    await tester.tapAt(tester.getTopLeft(item(2)) + const Offset(40, 40));
    await tester.pumpAndSettle();
    store.fail = true;
    await drop(tester, await startDrag(tester, 1), const Offset(5, 5));
    expect(find.textContaining('Could not move the book'), findsOneWidget);
    expect(item(1), findsOneWidget);
    expect(item(2), findsOneWidget);
    store.fail = false;
    await drop(tester, await startDrag(tester, 1), const Offset(5, 5));
    expect(store.moves.single.toSet(), {1, 2});
    expect(find.byType(BookOpenedFolder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow folder keeps batch drop target reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await openFolder(tester);
    await tester.longPress(item(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    final gesture = await startDrag(tester, 1);
    await drop(tester, gesture,
        tester.getCenter(find.byKey(const ValueKey('folder-shelf-drop'))));
    expect(store.moves.single.toSet(), {1, 2});
    expect(find.byType(BookOpenedFolder), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending folder move rejects duplicate drop', (tester) async {
    await shelf(tester, folder: true, selected: {1, 2});
    store.pending = Completer<void>();
    final destination = tester.getCenter(find.byKey(const ValueKey(3)));
    await drop(tester, await startDrag(tester, 1), destination);
    await drop(tester, await startDrag(tester, 2), destination);
    expect(store.moves, [
      [1, 2]
    ]);
    store.pending!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
