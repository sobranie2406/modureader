import 'dart:io';
import 'package:flutter/services.dart';
import 'package:anx_reader/service/ios_linked_books.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/service/book_player/document_reading_mode_store.dart';
import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:anx_reader/utils/color_scheme.dart';
import 'package:anx_reader/widgets/bookshelf/book_type_badges.dart';
import 'package:anx_reader/widgets/bookshelf/book_item.dart';
import 'package:anx_reader/service/knowledge/book_knowledge_index_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  Book book(String extension) =>
      Book.mock()..filePath = 'file/example.$extension';
  testWidgets('storage badges distinguish source and availability',
      (tester) async {
    final oldPath = documentPath;
    final dir = Directory.systemTemp.createTempSync('modu-badge-');
    documentPath = dir.path;
    final file = File('${dir.path}/file/internal.pdf')
      ..createSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            IosLinkedBooks.channel,
            (MethodCall call) async => {
                  'file/ios-linked-present.pdf': file.path,
                });
    await IosLinkedBooks.restore();
    Prefs().showBookFormatBadge = false;
    for (final entry in {
      'file/internal.pdf': 'Internal',
      'file/missing.pdf': 'Internal · unavailable',
      'file/ios-linked-present.pdf': 'Linked',
      'file/ios-linked-missing.pdf': 'Linked · unavailable',
    }.entries) {
      await tester.pumpWidget(MaterialApp(
          home: BookTypeBadges(book: Book.mock()..filePath = entry.key)));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('PDF'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            IosLinkedBooks.channel, (_) async => <String, String>{});
    await IosLinkedBooks.restore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IosLinkedBooks.channel, null);
    documentPath = oldPath;
    dir.deleteSync(recursive: true);
  });

  test('book formats retain their semantic colours independently of theme', () {
    const colours = {
      'PDF': Color(0xFF2463CB),
      'EPUB': Color(0xFF087F83),
      'FB2': Color(0xFF7851AF),
      'TXT': Color(0xFF52667A),
      'MOBI': Color(0xFF8A5636),
      'AZW3': Color(0xFF4D55AC),
      'MD': Color(0xFF287A97),
      'UMD': Color(0xFF936536),
    };
    for (final entry in colours.entries) {
      expect(BookTypeBadges.formatColor(entry.key), entry.value);
    }
  });

  testWidgets('indexing states retain semantic colours and E-Ink stays black',
      (tester) async {
    for (final eink in [false, true]) {
      Prefs().eInkMode = eink;
      for (final status in BookKnowledgeQueueStatus.values) {
        await tester.pumpWidget(MaterialApp(
            home: KnowledgeStatusBadge(
          indexed: true,
          item: BookKnowledgeQueueItem(
              book: book('epub'), status: status, requestedAt: DateTime(2026)),
        )));
        final expected = switch (status) {
          BookKnowledgeQueueStatus.queued ||
          BookKnowledgeQueueStatus.cancelling =>
            Colors.orange.shade700,
          BookKnowledgeQueueStatus.extracting ||
          BookKnowledgeQueueStatus.preparing ||
          BookKnowledgeQueueStatus.vectorizing =>
            Colors.blue.shade700,
          BookKnowledgeQueueStatus.failed => Colors.red.shade700,
          BookKnowledgeQueueStatus.cancelled => Colors.grey.shade700,
          BookKnowledgeQueueStatus.completed => Colors.green.shade600,
        };
        final box = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
        expect((box.decoration as BoxDecoration).color,
            eink ? Colors.black : expected,
            reason: status.name);
      }
    }
  });

  testWidgets(
      'format and indexed labels toggle independently and remember choice',
      (tester) async {
    expect(Prefs().showBookIndexBadge, isTrue);
    expect(Prefs().showBookFormatBadge, isTrue);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      BookTypeBadges(book: book('epub')),
      const KnowledgeStatusBadge(indexed: true, item: null),
    ]))));
    await tester.pump();
    expect(find.text('EPUB'), findsOneWidget);
    expect(find.text('Indexed'), findsOneWidget);
    Prefs().showBookIndexBadge = false;
    await tester.pump();
    expect(find.text('Indexed'), findsNothing);
    expect(find.text('EPUB'), findsOneWidget);
    Prefs().showBookFormatBadge = false;
    Prefs().showBookIndexBadge = true;
    await tester.pump();
    expect(find.text('Indexed'), findsOneWidget);
    expect(find.text('EPUB'), findsNothing);
    Prefs().showBookIndexBadge = false;
    await tester.pump();
    await Prefs().initPrefs();
    expect(Prefs().showBookIndexBadge, isFalse);
    expect(Prefs().showBookFormatBadge, isFalse);
  });

  testWidgets('indexed and format labels share font, padding and height',
      (tester) async {
    for (final eink in [false, true]) {
      Prefs().eInkMode = eink;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => Theme(
              data: colorSchema(Prefs(), context, Brightness.light),
              child: child!),
          home: Scaffold(
              body: Column(children: [
            BookTypeBadges(book: book('epub')),
            const KnowledgeStatusBadge(indexed: true, item: null),
          ]))));
      await tester.pump();
      final format = tester.widget<Text>(find.text('EPUB')).style!;
      final indexed = tester.widget<Text>(find.text('Indexed')).style!;
      expect(indexed.fontSize, format.fontSize);
      expect(indexed.height, format.height);
      expect(indexed.fontWeight, format.fontWeight);
      final formatBox = find
          .ancestor(of: find.text('EPUB'), matching: find.byType(DecoratedBox))
          .first;
      final indexBox = find
          .ancestor(
              of: find.text('Indexed'), matching: find.byType(DecoratedBox))
          .first;
      expect(tester.getSize(indexBox).height, tester.getSize(formatBox).height);
      for (final label in ['EPUB', 'Indexed']) {
        final padding = tester.widget<Padding>(find
            .ancestor(of: find.text(label), matching: find.byType(Padding))
            .first);
        expect(padding.padding,
            const EdgeInsets.symmetric(horizontal: 6, vertical: 3));
      }
    }
  });

  testWidgets('hiding indexed labels retains progress and failure notices',
      (tester) async {
    Prefs().showBookIndexBadge = false;
    for (final status in BookKnowledgeQueueStatus.values) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: KnowledgeStatusBadge(
        indexed: true,
        item: BookKnowledgeQueueItem(
            book: book('epub'), status: status, requestedAt: DateTime(2026)),
      ))));
      final hidden = status == BookKnowledgeQueueStatus.completed ||
          status == BookKnowledgeQueueStatus.cancelled;
      expect(find.byType(Text), hidden ? findsNothing : findsOneWidget,
          reason: status.name);
    }
  });
  test('format uses case-insensitive container extension, not title', () {
    for (final extension in [
      'PDF',
      'epub',
      'fb2',
      'txt',
      'mobi',
      'azw3',
      'md',
      'umd'
    ]) {
      expect(
          BookTypeBadges.formatFor(book(extension)), extension.toUpperCase());
    }
    expect(BookTypeBadges.formatFor(book('markdown')), 'MD');
    expect(BookTypeBadges.formatFor(Book.mock()), '');
  });
  test(
      'PDF alone is not proof of scanning; cached evidence and correction decide',
      () async {
    final pdf = book('pdf'), store = DocumentTypeStore(Prefs().prefs);
    final key = customCssBookKey(pdf);
    expect(BookTypeBadges.scanned(pdf), false);
    await store.saveDetected(key, 'scanned');
    expect(BookTypeBadges.scanned(pdf), true);
    await store.save(key, 'text');
    expect(BookTypeBadges.scanned(pdf), false);
    await store.save(key, null);
    expect(BookTypeBadges.scanned(pdf), true);
  });
  test(
      'image EPUB/MOBI/AZW3/FB2 use existing import evidence and manual switch',
      () async {
    for (final extension in ['epub', 'mobi', 'azw3', 'fb2']) {
      final value = book(extension),
          store = DocumentReadingModeStore(Prefs().prefs);
      expect(BookTypeBadges.scanned(value), false);
      await store.setScanned(value, true);
      expect(BookTypeBadges.scanned(value), true,
          reason: 'manual scanned overrides automatic ordinary detection');
      await store.save(value, 'standard');
      expect(BookTypeBadges.scanned(value), true,
          reason: 'later detection must preserve the manual choice');
      await store.save(value, 'image-epub');
      expect(BookTypeBadges.scanned(value), true);
      await store.setScanned(value, false);
      expect(BookTypeBadges.scanned(value), false);
    }
  });
  testWidgets(
      'narrow labels wrap without overflow, use black and white in E-Ink',
      (tester) async {
    final value = book('epub');
    await tester.runAsync(() =>
        DocumentReadingModeStore(Prefs().prefs).save(value, 'image-epub'));
    for (final eink in [false, true]) {
      Prefs().eInkMode = eink;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => Theme(
              data: colorSchema(Prefs(), context, Brightness.light),
              child: child!),
          home: Scaffold(
              body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: SizedBox(
                      width: 65, child: BookTypeBadges(book: value))))));
      await tester.pump();
      expect(find.text('EPUB'), findsOneWidget);
      expect(find.text('Scanned'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.text('Scanned')).dy,
          lessThan(tester.getTopLeft(find.text('EPUB')).dy));
      final label = tester.widget<Text>(find.text('EPUB'));
      expect(label.style!.color, eink ? Colors.black : Colors.white);
    }
    await tester.runAsync(
        () => DocumentReadingModeStore(Prefs().prefs).setScanned(value, false));
    Prefs().notifyExternalChange();
    await tester.pump();
    expect(find.text('Scanned'), findsNothing);
    expect(find.text('EPUB'), findsOneWidget);
    await tester.runAsync(
        () => DocumentReadingModeStore(Prefs().prefs).setScanned(value, true));
    Prefs().notifyExternalChange();
    await tester.pump();
    expect(find.text('Scanned'), findsOneWidget);
    Prefs().showBookFormatBadge = false;
    await tester.pump();
    expect(find.text('EPUB'), findsNothing);
    expect(find.text('Scanned'), findsOneWidget);
    await tester.runAsync(
        () => DocumentReadingModeStore(Prefs().prefs).setScanned(value, false));
    Prefs().notifyExternalChange();
    await tester.pump();
    expect(find.text('EPUB'), findsNothing);
    expect(find.text('Scanned'), findsNothing);
    Prefs().showBookFormatBadge = true;
    await tester.pump();
    expect(find.text('EPUB'), findsOneWidget);
  });
}
