import 'package:anx_reader/service/book_player/document_type_store.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('global settings cannot copy or overwrite another book type map',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    final store = DocumentTypeStore(Prefs().prefs);
    await store.save('local-book', 'text');
    expect(await Prefs().buildPrefsBackupMap(),
        isNot(contains(DocumentTypeStore.key)));
    await Prefs().applyPrefsBackupMap({
      DocumentTypeStore.key: {
        'type': 'string',
        'value': '{"local-book":"scanned"}'
      }
    });
    expect(store.read('local-book'), 'text');
  });
  test('corrections persist separately per book and can return to automatic',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = DocumentTypeStore(prefs);
    await store.save('book-a', 'scanned');
    await store.save('book-b', 'text');
    await prefs.reload();
    expect(DocumentTypeStore(prefs).read('book-a'), 'scanned');
    expect(DocumentTypeStore(prefs).read('book-b'), 'text');
    await store.save('book-a', null);
    expect(store.read('book-a'), isNull);
    expect(store.read('book-b'), 'text');
    await expectLater(store.save('book-a', 'invalid'), throwsArgumentError);
  });
  test('invalid stored types or corrupt data cannot break reading', () async {
    SharedPreferences.setMockInitialValues(
        {DocumentTypeStore.key: '{invalid json'});
    final prefs = await SharedPreferences.getInstance();
    final store = DocumentTypeStore(prefs);
    expect(store.read('book-a'), isNull);
    await store.save('book-a', 'mixed');
    expect(store.read('book-a'), 'mixed');
  });
}
