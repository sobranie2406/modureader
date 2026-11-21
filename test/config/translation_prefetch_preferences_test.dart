import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailedDisableStore extends InMemorySharedPreferencesStore {
  _FailedDisableStore()
      : super.withData({
          'flutter.languageTranslationPrefetchPages': 4,
          'flutter.languageTranslationPrefetchRememberedPages': 2,
        });

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (key == 'flutter.languageTranslationPrefetchPages' && value == 0) {
      return Future.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('language and classical pretranslation default off independently', () {
    expect(Prefs().languageTranslationPrefetchPages, 0);
    expect(Prefs().classicalTranslationPrefetchPages, 0);
    expect(Prefs().translationPrefetchPageCount(classical: false), 3);
    expect(Prefs().translationPrefetchPageCount(classical: true), 3);
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
    expect(Prefs().translationPrefetchPageCount(classical: false), 2);
    expect(Prefs().classicalTranslationPrefetchPages, 5);
  });

  test('legacy counts persist when disabled and can be enabled again',
      () async {
    SharedPreferences.setMockInitialValues({
      'languageTranslationPrefetchPages': 5,
      'classicalTranslationPrefetchPages': 0,
    });
    final prefs = Prefs();
    await prefs.initPrefs();
    expect(prefs.translationPrefetchPageCount(classical: false), 5);
    expect(prefs.translationPrefetchPageCount(classical: true), 3);
    var notifications = 0;
    void changed() => notifications++;
    prefs.addListener(changed);
    addTearDown(() => prefs.removeListener(changed));

    await prefs.saveTranslationPrefetch(classical: false, pages: 0);
    await prefs.prefs.reload();
    expect(prefs.languageTranslationPrefetchPages, 0);
    expect(prefs.translationPrefetchPageCount(classical: false), 5);
    expect(notifications, 1);
    await prefs.saveTranslationPrefetch(
        classical: false,
        pages: prefs.translationPrefetchPageCount(classical: false));
    await prefs.saveTranslationPrefetch(classical: true, pages: 2);
    await prefs.saveTranslationPrefetch(classical: true, pages: 0);
    expect(prefs.languageTranslationPrefetchPages, 5);
    expect(prefs.classicalTranslationPrefetchPages, 0);
    expect(prefs.translationPrefetchPageCount(classical: true), 2);
    expect(notifications, 4);
    await expectLater(prefs.saveTranslationPrefetch(classical: false, pages: 6),
        throwsArgumentError);
    expect(notifications, 4);
  });

  test('declined save restores both cached counts without notifying', () async {
    final platform = SharedPreferencesStorePlatform.instance;
    addTearDown(() => SharedPreferencesStorePlatform.instance = platform);
    SharedPreferencesStorePlatform.instance = _FailedDisableStore();
    final prefs = Prefs();
    await prefs.prefs.reload();
    var notifications = 0;
    void changed() => notifications++;
    prefs.addListener(changed);
    addTearDown(() => prefs.removeListener(changed));

    await expectLater(prefs.saveTranslationPrefetch(classical: false, pages: 0),
        throwsStateError);
    expect(prefs.languageTranslationPrefetchPages, 4);
    expect(prefs.prefs.getInt('languageTranslationPrefetchRememberedPages'), 2);
    expect(notifications, 0);
    await prefs.saveTranslationPrefetch(classical: false, pages: 1);
    expect(prefs.languageTranslationPrefetchPages, 1);
    expect(notifications, 1);
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
