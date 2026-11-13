import 'dart:io';
import 'package:modu_reader/service/receive_file/external_book_inbox.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modu_reader/service/book_import_source.dart';
import 'package:modu_reader/widgets/bookshelf/book_import_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'dropping a folder queues books without any confirmation or result dialog',
      (tester) async {
    final root = Directory.systemTemp.createTempSync('modu-drop-ui-');
    addTearDown(() {
      externalBookInbox.detach();
      root.deleteSync(recursive: true);
    });
    File('${root.path}/one.epub').writeAsStringSync('one');
    Directory('${root.path}/nested').createSync();
    File('${root.path}/nested/two.pdf').writeAsStringSync('two');
    final received = <String>[];
    externalBookInbox.attach((paths) async {
      received.addAll(paths);
    });
    late BuildContext dropContext;
    late WidgetRef dropRef;
    await tester.pumpWidget(ProviderScope(child: MaterialApp(home: Consumer(
      builder: (context, ref, _) {
        dropContext = context;
        dropRef = ref;
        return const Scaffold(body: Text('shelf'));
      },
    ))));
    await tester.runAsync(() =>
        pickBooksForImport(dropContext, dropRef, droppedPaths: [root.path]));
    await tester.pumpAndSettle();
    expect(received, hasLength(2));
    expect(find.byType(BookImportSelection), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in-place notice and selection fit a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: BookImportSelection(inPlace: true, entries: [
      BookImportEntry(id: 'a', name: 'book.epub', label: 'book.epub'),
    ]))));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'in-place selection explains scope, backups and conversion limits',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: BookImportSelection(inPlace: true, entries: [
      BookImportEntry(id: 'a', name: 'book.epub', label: 'book.epub'),
    ]))));
    expect(find.textContaining('without uploading'), findsOneWidget);
    expect(find.textContaining('Notes and progress still sync'),
        findsOneWidget);
    expect(find.textContaining('TXT, Markdown or UMD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
