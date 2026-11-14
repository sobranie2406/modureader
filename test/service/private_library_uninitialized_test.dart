import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/private_library.dart';

void main() {
  test('ordinary data access never initializes preferences or a widget binding',
      () async {
    expect(Prefs.isReady, false);
    final library = PrivateLibrary();
    addTearDown(library.dispose);
    expect(library.canRead(Book.mock()), true);
    expect(library.bookPredicate(), '1');
    expect(library.canReadHistory('ordinary'), true);
    library.setPluginActive(false);
    await Future<void>.delayed(Duration.zero);
    expect(Prefs.isReady, false);
  });

  test('an enabled feature stays closed until local preferences are ready',
      () async {
    final library = PrivateLibrary();
    addTearDown(library.dispose);
    library.setPluginActive(true);
    expect(library.canRead(Book.mock()), false);
    expect(library.bookPredicate(), '0');
    expect(await library.unlock(), false);
    expect(Prefs.isReady, false);
    library.setPluginActive(false);
    expect(library.canRead(Book.mock()), true);
  });
}
