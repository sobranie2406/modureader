import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/service/book_player/document_reading_mode_store.dart';
import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:anx_reader/widgets/bookshelf/book_type_badges.dart';
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
  });
}
