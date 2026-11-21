import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('language and classical pretranslation default off independently', () {
    expect(Prefs().languageTranslationPrefetchPages, 0);
    expect(Prefs().classicalTranslationPrefetchPages, 0);
    expect(
        Prefs().prefs.containsKey('languageTranslationPrefetchPages'), false);
    expect(
        Prefs().prefs.containsKey('classicalTranslationPrefetchPages'), false);
  });

  test('independent page windows persist and notify reading controllers',
      () async {
    final changes = <(int, int)>[];
    void changed() => changes.add((
          Prefs().languageTranslationPrefetchPages,
          Prefs().classicalTranslationPrefetchPages
        ));
    Prefs().addListener(changed);
    addTearDown(() => Prefs().removeListener(changed));

    Prefs().languageTranslationPrefetchPages = 2;
    Prefs().classicalTranslationPrefetchPages = 5;
    await Prefs().initPrefs();
    expect(Prefs().languageTranslationPrefetchPages, 2);
    expect(Prefs().classicalTranslationPrefetchPages, 5);
    expect(changes, containsAllInOrder([(2, 0), (2, 5)]));
    Prefs().languageTranslationPrefetchPages = 0;
    expect(Prefs().classicalTranslationPrefetchPages, 5);
  });

  test('both saved and newly selected windows stay within zero to five',
      () async {
    Prefs().languageTranslationPrefetchPages = 99;
    Prefs().classicalTranslationPrefetchPages = -1;
    expect(Prefs().prefs.getInt('languageTranslationPrefetchPages'), 5);
    expect(Prefs().prefs.getInt('classicalTranslationPrefetchPages'), 0);

    await Prefs().prefs.setInt('languageTranslationPrefetchPages', -1);
    await Prefs().prefs.setInt('classicalTranslationPrefetchPages', 99);
    expect(Prefs().languageTranslationPrefetchPages, 0);
    expect(Prefs().classicalTranslationPrefetchPages, 5);
  });
}
