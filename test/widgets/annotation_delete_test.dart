import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/widgets/common/axis_flex.dart';
import 'package:anx_reader/widgets/context_menu/excerpt_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const cfi = 'epubcfi(/6/4!/4/2,/1:0,/1:12)';

BookNote note({int id = 41, String type = 'highlight', String value = cfi}) =>
    BookNote(
      id: id,
      bookId: 7,
      content: '用于测试的正文',
      cfi: value,
      chapter: '测试章节',
      type: type,
      color: '66CCFF',
      readerNote: '保留批注直到用户确认删除',
      updateTime: DateTime(2026, 9, 30),
    );

class _Notes extends BookNoteDao {
  _Notes(BookNote saved) : rows = {saved.id!: saved};
  final Map<int, BookNote> rows;
  final deleted = <int>[];
  bool fail = false;
  Completer<void>? deletion;

  @override
  Future<BookNote> selectBookNoteById(int id) async =>
      rows[id] ?? (throw StateError('Missing note'));

  @override
  Future<void> deleteBookNoteById(int id) async {
    deleted.add(id);
    await deletion?.future;
    if (fail) throw StateError('Database write failed');
    rows.remove(id);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<ExcerptMenuState> mount(WidgetTester tester,
      {required _Notes dao,
      int? id,
      required Future<void> Function(String) remove,
      required VoidCallback close}) async {
    final key = GlobalKey<ExcerptMenuState>();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        ...GlobalMaterialLocalizations.delegates
      ],
      home: Scaffold(
        body: AxisFlex(axis: Axis.horizontal, children: [
          ExcerptMenu(
            key: key,
            id: id,
            dao: dao,
            removeAnnotation: remove,
            annoCfi: cfi,
            annoContent: '用于测试的正文',
            onClose: close,
            footnote: false,
            decoration: const BoxDecoration(),
            toggleTranslationMenu: () {},
            toggleReaderNoteMenu: ({bool? show}) {},
            openReaderNoteMenu: (_) async {},
            onNoteCreated: (_) {},
            axis: Axis.horizontal,
            reverse: false,
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('annotation-action-delete')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('annotation-confirm-delete')));
    await tester.pumpAndSettle();
  }

  for (final type in ['highlight', 'underline']) {
    testWidgets('trash visibly confirms and removes an existing $type',
        (tester) async {
      final dao = _Notes(note(type: type));
      final removed = <String>[];
      var closed = 0;
      await mount(tester,
          dao: dao,
          id: 41,
          remove: (cfi) async => removed.add(cfi),
          close: () => closed++);
      await confirm(tester);
      expect(dao.rows, isEmpty);
      expect(dao.deleted, [41]);
      expect(removed, [cfi]);
      expect(closed, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a mark created in this toolbar uses its new persisted ID',
      (tester) async {
    final dao = _Notes(note(id: 52));
    final removed = <String>[];
    var closed = 0;
    final state = await mount(tester,
        dao: dao,
        remove: (cfi) async => removed.add(cfi),
        close: () => closed++);
    // This is the same runtime ID assigned by _persistNote; widget.id stays
    // null until the parent rebuilds. Deletion must not use that original ID.
    state.noteId = 52;
    await confirm(tester);
    expect(dao.deleted, [52]);
    expect(dao.rows, isEmpty);
    expect(removed, [cfi]);
    expect(closed, 1);
  });

  testWidgets('cancel preserves the mark and its written comment',
      (tester) async {
    final dao = _Notes(note());
    var closed = 0;
    var removed = 0;
    await mount(tester,
        dao: dao,
        id: 41,
        remove: (_) async => removed++,
        close: () => closed++);
    await tester.tap(find.byKey(const ValueKey('annotation-action-delete')));
    await tester.pumpAndSettle();
    expect(dao.deleted, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(dao.deleted, isEmpty);
    expect(dao.rows[41]!.readerNote, '保留批注直到用户确认删除');
    expect(closed, 0);
    expect(removed, 0);
  });

  testWidgets('database and overlay removal finish before closing',
      (tester) async {
    final dao = _Notes(note())..deletion = Completer<void>();
    final rendering = Completer<void>();
    var closed = 0;
    var removed = 0;
    final state = await mount(tester,
        dao: dao,
        id: 41,
        remove: (_) async {
          removed++;
          await rendering.future;
        },
        close: () => closed++);
    await confirm(tester);
    expect(dao.deleted, [41]);
    expect(removed, 0);
    expect(closed, 0);
    await state.deleteHandler(); // A repeated click must not delete twice.
    expect(dao.deleted, [41]);
    dao.deletion!.complete();
    await tester.pump();
    expect(removed, 1);
    expect(closed, 0);
    rendering.complete();
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(dao.rows, isEmpty);
  });

  testWidgets('a failed database deletion retains the mark and can be retried',
      (tester) async {
    final dao = _Notes(note())..fail = true;
    var closed = 0;
    var removed = 0;
    await mount(tester,
        dao: dao,
        id: 41,
        remove: (_) async => removed++,
        close: () => closed++);
    await confirm(tester);
    expect(dao.rows, hasLength(1));
    expect(removed, 0);
    expect(closed, 0);
    expect(find.byType(SnackBar), findsOneWidget);
    dao.fail = false;
    await confirm(tester);
    expect(dao.rows, isEmpty);
    expect(removed, 1);
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'deletion removes the latest stored range, not the stale selection',
      (tester) async {
    final dao = _Notes(note());
    final removed = <String>[];
    await mount(tester,
        dao: dao,
        id: 41,
        remove: (cfi) async => removed.add(cfi),
        close: () {});
    const merged = 'epubcfi(/6/4!/4/2,/1:0,/1:20)';
    dao.rows[41] = note(value: merged);
    await confirm(tester);
    expect(removed, [merged]);
    expect(dao.rows, isEmpty);
  });

  testWidgets(
      'overlay failure can retry the latest range after database deletion',
      (tester) async {
    final dao = _Notes(note());
    var fail = true;
    var closed = 0;
    final removed = <String>[];
    await mount(tester,
        dao: dao,
        id: 41,
        remove: (cfi) async {
          removed.add(cfi);
          if (fail) throw StateError('Transient renderer error');
        },
        close: () => closed++);
    const merged = 'epubcfi(/6/4!/4/2,/1:0,/1:20)';
    dao.rows[41] = note(value: merged);
    await confirm(tester);
    expect(dao.rows, isEmpty);
    expect(closed, 0);
    fail = false;
    await confirm(tester);
    expect(removed, [merged, merged]);
    expect(closed, 1);
    expect(tester.takeException(), isNull);
  });
}
