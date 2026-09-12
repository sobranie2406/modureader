import 'package:anx_reader/dao/book_note.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_note.dart';
import 'package:anx_reader/widgets/context_menu/reader_note_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class ConflictingNoteDao extends BookNoteDao {
  int attempts = 0;
  @override
  Future<BookNote> selectBookNoteById(int id) async => BookNote(
      id: id,
      bookId: 1,
      content: 'Synthetic quote',
      cfi: 'synthetic-cfi',
      chapter: 'Test',
      type: 'highlight',
      color: 'FFFF00',
      readerNote: 'Original comment',
      updateTime: DateTime(2026));
  @override
  Future<void> updateBookNoteById(BookNote note) async {
    attempts++;
    throw const NoteConflictException();
  }
}

void main() {
  testWidgets('conflicting save keeps editor, draft and retry control visible',
      (tester) async {
    final dao = ConflictingNoteDao();
    final key = GlobalKey<ReaderNoteMenuState>();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: L10n.supportedLocales,
        localizationsDelegates: const [
          L10n.delegate,
          ...GlobalMaterialLocalizations.delegates
        ],
        home: Scaffold(
            body: Column(children: [
          ReaderNoteMenu(
            key: key,
            noteId: 1,
            dao: dao,
            decoration: const BoxDecoration(),
            axis: Axis.vertical,
            onVisibilityChange: (_) {},
            onSizeChanged: () {},
          )
        ]))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'My unsaved local draft');
    await key.currentState!.saveNote();
    await tester.pumpAndSettle();
    expect(dao.attempts, 1);
    expect(find.text('My unsaved local draft'), findsOneWidget);
    expect(find.textContaining('未覆盖最新内容'), findsOneWidget);
    expect(key.currentState!.showSaveButton, true);
    expect(tester.takeException(), isNull);
  });
}
