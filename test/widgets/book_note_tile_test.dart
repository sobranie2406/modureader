import 'package:modu_reader/main.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book_note.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/widgets/book_notes/book_note_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  testWidgets(
      'source button works for old PDF notes, not ordinary notes or selection mode',
      (tester) async {
    final page = DocumentReflowPage(page: 4, ocr: true, rawText: '旧笔记');
    final note = BookNote(
        bookId: 1,
        content: '旧笔记',
        cfi: page.anchor(0, 3).encode(),
        chapter: '5',
        type: 'underline',
        color: 'ff0000',
        updateTime: DateTime.now());
    var opened = 0, tapped = 0;
    Future<void> mount({bool selectable = false}) async {
      await tester.pumpWidget(MaterialApp(
          navigatorKey: navigatorKey,
          home: Scaffold(
              body: BookNoteTile(
            note: note,
            onTap: () => tapped++,
            onViewOriginal: selectable ? null : () => opened++,
          ))));
      await tester.pumpAndSettle();
    }

    await mount();
    expect(find.text('View original · 5'), findsOneWidget);
    await tester.tap(find.byType(TextButton));
    expect(opened, 1);
    expect(tapped, 0);
    await mount(selectable: true);
    expect(find.byType(TextButton), findsNothing);
    note.cfi = 'epubcfi(/6/2!/4/2)';
    await mount();
    expect(find.byType(TextButton), findsNothing);
  });
}
