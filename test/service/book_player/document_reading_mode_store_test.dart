import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/document_reading_mode.dart';
import 'package:anx_reader/service/book_player/document_reading_mode_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('import result survives restart and reads make no preference changes',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = DocumentReadingModeStore(prefs);
    final book =
        Book.mock().copyWith(filePath: 'file/images.epub', md5: 'content-a');
    expect(store.read(book), DocumentReadingMode.standard);
    expect(prefs.getString(DocumentReadingModeStore.key), isNull);
    await store.save(book, 'image-epub');
    final saved = prefs.getString(DocumentReadingModeStore.key);
    final reopened = DocumentReadingModeStore(prefs);
    for (var i = 0; i < 10; i++) {
      expect(reopened.read(book), DocumentReadingMode.imageEpub);
    }
    expect(prefs.getString(DocumentReadingModeStore.key), saved);
    expect(reopened.read(book.copyWith(md5: 'replacement')),
        DocumentReadingMode.standard);
    expect(reopened.read(book.copyWith(id: 999)), DocumentReadingMode.standard);
  });

  test('legacy EPUB and damaged metadata fall back; PDF needs no page sampling',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = DocumentReadingModeStore(prefs);
    final book = Book.mock();
    for (final json in ['broken', '[]', '{"wrong": {"mode":"image-epub"}}']) {
      await prefs.setString(DocumentReadingModeStore.key, json);
      expect(store.read(book.copyWith(filePath: 'old.epub')),
          DocumentReadingMode.standard);
      expect(store.read(book.copyWith(filePath: 'old.PDF')),
          DocumentReadingMode.pdf);
    }
  });

  test(
      'reimport updates evidence; converted text and wrong formats cannot become image EPUB',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = DocumentReadingModeStore(prefs);
    final book = Book.mock().copyWith(filePath: 'file/a.epub', md5: 'a');
    await store.save(book, 'image-epub');
    await store.save(book, 'standard');
    expect(store.read(book), DocumentReadingMode.standard);
    await store.save(book, null);
    expect(store.read(book), DocumentReadingMode.standard);
    final other = book.copyWith(filePath: 'file/b.txt', md5: 'b', id: 2);
    await store.save(other, 'image-epub');
    expect(store.read(other), DocumentReadingMode.standard);
    await Future.wait([
      store.save(book, 'image-epub'),
      store.save(other, 'standard'),
    ]);
    expect(store.read(book), DocumentReadingMode.imageEpub);
    expect(store.read(other), DocumentReadingMode.standard);
  });

  test('classification cache is excluded from global settings transfer',
      () async {
    await Prefs().initPrefs();
    await DocumentReadingModeStore(Prefs().prefs)
        .save(Book.mock().copyWith(filePath: 'a.epub'), 'image-epub');
    expect(
        (await Prefs().buildPrefsBackupMap())
            .containsKey(DocumentReadingModeStore.key),
        isFalse);
    final previous = Prefs().prefs.getString(DocumentReadingModeStore.key);
    await Prefs().applyPrefsBackupMap({
      DocumentReadingModeStore.key: {'type': 'string', 'value': '{}'}
    });
    expect(Prefs().prefs.getString(DocumentReadingModeStore.key), previous);
  });
}
