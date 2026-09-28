import 'dart:async';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/tb_group.dart';
import 'package:anx_reader/providers/book_list.dart';
import 'package:anx_reader/providers/tb_groups.dart';
import 'package:anx_reader/widgets/bookshelf/book_folder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Books extends BookList {
  List<int>? moved;
  String? name;
  int? destination;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<List<List<Book>>> build() async {
    // The real bookshelf watches this provider throughout the dialog's life.
    ref.keepAlive();
    return [];
  }

  @override
  Future<void> moveBooksToFolder(Iterable<int> bookIds,
      {int? groupId, String? newFolderName}) async {
    if (fail) throw StateError('fixture');
    moved = bookIds.toList();
    name = newFolderName;
    destination = groupId;
    await pending?.future;
  }
}

class _Groups extends GroupDao {
  List<TbGroup> groups = [
    const TbGroup(id: 0, name: 'root'),
    const TbGroup(id: 3, name: '已有夹')
  ];
  bool fail = false;
  @override
  Future<List<TbGroup>> build() async {
    if (fail) throw StateError('fixture');
    return groups;
  }
}

void main() {
  late _Books books;
  late _Groups groups;
  bool? result;
  setUp(() {
    books = _Books();
    groups = _Groups();
    result = null;
  });

  Future<void> mount(WidgetTester tester, {bool create = true}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          bookListProvider.overrideWith(() => books),
          groupDaoProvider.overrideWith(() => groups),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () async {
                            result = await showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => BookFolderDialog(
                                    bookIds: const [1, 2], createNew: create));
                          },
                          child: const Text('打开'),
                        ))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'create validates name, keeps text editable and moves selected IDs',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text('创建并移入'));
    await tester.pumpAndSettle();
    expect(find.text('请输入文件夹名称'), findsOneWidget);
    expect(books.moved, isNull);
    await tester.enterText(find.byType(TextField), ' 文学 ');
    await tester.tap(find.text('创建并移入'));
    await tester.pumpAndSettle();
    expect(books.name, '文学');
    expect(books.moved, [1, 2]);
    expect(result, true);
  });

  testWidgets('pick existing folder excludes root and submits destination',
      (tester) async {
    await mount(tester, create: false);
    expect(find.text('root'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.text('已有夹'));
    await tester.pump();
    await tester.tap(find.text('移入'));
    await tester.pumpAndSettle();
    expect(books.destination, 3);
    expect(books.name, isNull);
    expect(result, true);
  });

  testWidgets('cancel never moves books', (tester) async {
    await mount(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(books.moved, isNull);
    expect(result, false);
  });

  testWidgets('empty folder list explains how to create one', (tester) async {
    groups.groups = [];
    await mount(tester, create: false);
    expect(find.textContaining('暂无已有文件夹'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
  });

  testWidgets('failed save keeps dialog and selection for retry',
      (tester) async {
    books.fail = true;
    await mount(tester);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.text('创建并移入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('操作失败'), findsOneWidget);
    expect(result, isNull);
    books.fail = false;
    await tester.tap(find.text('创建并移入'));
    await tester.pumpAndSettle();
    expect(result, true);
  });

  testWidgets(
      'pending transaction disables duplicate submission and cancellation',
      (tester) async {
    books.pending = Completer<void>();
    await mount(tester);
    await tester.enterText(find.byType(TextField), '测试');
    await tester.tap(find.text('创建并移入'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull);
    books.pending!.complete();
    await tester.pumpAndSettle();
    expect(result, true);
  });

  testWidgets('long destination list scrolls on narrow screens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    groups.groups = List.generate(30, (i) => TbGroup(id: i + 1, name: '文件夹$i'));
    await mount(tester, create: false);
    await tester.scrollUntilVisible(find.text('文件夹29'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('文件夹29'));
    await tester.pump();
    await tester.tap(find.text('移入'));
    await tester.pumpAndSettle();
    expect(books.destination, 30);
    expect(tester.takeException(), isNull);
  });
}
