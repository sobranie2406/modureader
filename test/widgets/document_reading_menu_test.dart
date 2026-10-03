import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/service/book_player/pdf_reading_state_store.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/pdf_reading_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('only confirmed PDF/image EPUB can expose the document menu', () {
    for (final path in [
      'book.txt',
      'book.md',
      'book.mobi',
      'book.azw3',
      'book.cbz'
    ]) {
      for (final mode in ['pdf', 'image-epub', 'standard', null]) {
        expect(DocumentReadingMode.fromDetection(path, mode).hasDocumentMenu,
            isFalse);
      }
    }
    expect(DocumentReadingMode.fromDetection('book.EPUB', 'image-epub'),
        DocumentReadingMode.imageEpub);
    expect(DocumentReadingMode.fromDetection('book.PDF', 'pdf'),
        DocumentReadingMode.pdf);
    expect(
        DocumentReadingMode.fromDetection('novel.epub', 'standard')
            .hasDocumentMenu,
        isFalse);
    expect(
        DocumentReadingMode.fromDetection('novel.epub', null).hasDocumentMenu,
        isFalse);
    expect(
        DocumentReadingMode.fromDetection('novel.epub', 'pdf').hasDocumentMenu,
        isFalse);
  });

  test('automatic initial mode is per-book; explicit off survives reopening',
      () async {
    final store = PdfReadingStateStore(Prefs().prefs);
    expect(store.hasSavedMode('image'), isFalse);
    await store.setEnabled('image', true);
    expect(store.hasSavedMode('image'), isTrue);
    await store.setEnabled('image', false);
    final reopened = PdfReadingStateStore(Prefs().prefs);
    expect(reopened.hasSavedMode('image'), isTrue);
    expect(reopened.read('image')['enabled'], isFalse);
    expect(reopened.hasSavedMode('other'), isFalse);
  });

  testWidgets(
      'standard style menu retains Preview 3 controls without document additions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: StyleSettings())),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PdfReadingControls), findsNothing);
    for (final label in [
      'Document type inspection',
      'EPUB image pages',
      'PDF crop and panels',
      'Read cropped panels'
    ]) {
      expect(find.text(label), findsNothing);
    }
    // Preview 3 has four StyleSliders plus two margin Sliders in a shared row.
    expect(find.byType(StyleSlider), findsNWidgets(4));
    expect(find.byType(Slider), findsNWidgets(6));
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
