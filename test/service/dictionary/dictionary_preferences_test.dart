import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/dictionary/dictionary_preferences.dart';
import 'package:anx_reader/service/dictionary/online_dictionary.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  test('default is offline with all enabled local dictionaries', () async {
    final p = await DictionaryPreferences.load();
    expect(p.localIds, isNull);
    expect(p.online, isEmpty);
  });
  test(
      'removed online source is ignored without changing local or wiki choices',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(dictionaryPreferencesKey,
        ['local:one', 'online:freeEnglish', 'online:wiktionaryZh']);
    final loaded = await DictionaryPreferences.load();
    expect(loaded.localIds, {'one'});
    expect(loaded.online, {OnlineDictionary.wiktionaryZh});
    await loaded.save();
    expect(prefs.getStringList(dictionaryPreferencesKey),
        ['local:one', 'online:wiktionaryZh']);
    await prefs.setStringList(
        dictionaryPreferencesKey, ['local:*', 'online:freeEnglish']);
    final removedOnly = await DictionaryPreferences.load();
    expect(removedOnly.localIds, isNull);
    expect(removedOnly.online, isEmpty);
  });
  test('empty, single and multiple local selections survive reload', () async {
    for (final ids in [
      <String>{},
      {'one'},
      {'one', 'two'}
    ]) {
      await DictionaryPreferences(
          localIds: ids, online: {OnlineDictionary.wiktionaryEn}).save();
      final p = await DictionaryPreferences.load();
      expect(p.localIds, ids);
      expect(p.online, {OnlineDictionary.wiktionaryEn});
    }
  });
  test('dictionary IDs and network opt-in are not exported or imported',
      () async {
    await DictionaryPreferences(
        localIds: {'one'}, online: {OnlineDictionary.wiktionaryEn}).save();
    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup.containsKey(dictionaryPreferencesKey), false);
    await Prefs().applyPrefsBackupMap({
      dictionaryPreferencesKey: {
        'type': 'stringList',
        'value': ['online:wiktionaryZh']
      }
    });
    expect((await DictionaryPreferences.load()).online,
        {OnlineDictionary.wiktionaryEn});
  });
}
