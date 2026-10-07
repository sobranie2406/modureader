import 'package:anx_reader/service/book_import_source.dart';
import 'package:anx_reader/widgets/bookshelf/book_import_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'folder defaults to all books, allows individual selection and returns only chosen entries',
      (tester) async {
    const entries = [
      BookImportEntry(id: 'a', name: 'same.epub', label: 'a/same.epub'),
      BookImportEntry(id: 'b', name: 'same.epub', label: 'b/same.epub'),
    ];
    List<BookImportEntry>? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showDialog<List<BookImportEntry>>(
                            context: context,
                            builder: (_) =>
                                const BookImportSelection(entries: entries));
                      },
                      child: const Text('open')),
                ))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<CheckboxListTile>(find.byKey(const ValueKey('a'))).value,
        true);
    await tester.tap(find.byKey(const ValueKey('a')));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(result!.map((e) => e.id), ['b']);
    expect(tester.takeException(), isNull);
  });
}
