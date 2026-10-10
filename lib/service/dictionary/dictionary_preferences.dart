import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/service/dictionary/online_dictionary.dart';

// Device-local IDs and explicit network opt-in must not travel in sync backups.
const dictionaryPreferencesKey = 'dictionaryLookupSources';

class DictionaryPreferences {
  DictionaryPreferences({this.localIds, Set<OnlineDictionary>? online})
      : online = online ?? {};
  final Set<String>? localIds; // null: all enabled local dictionaries
  final Set<OnlineDictionary> online;

  static Future<DictionaryPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.get(dictionaryPreferencesKey);
    if (value is! List<String>) return DictionaryPreferences();
    return DictionaryPreferences(
        localIds: value.contains('local:*')
            ? null
            : value
                .where((s) => s.startsWith('local:'))
                .map((s) => s.substring(6))
                .toSet(),
        online: OnlineDictionary.values
            .where((s) => value.contains('online:${s.name}'))
            .toSet());
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(dictionaryPreferencesKey, [
      if (localIds == null)
        'local:*'
      else
        ...localIds!.map((id) => 'local:$id'),
      ...online.map((s) => 'online:${s.name}')
    ])) {
      throw StateError('Could not save dictionary sources');
    }
  }
}
