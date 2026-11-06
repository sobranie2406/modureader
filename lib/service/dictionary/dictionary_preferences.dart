import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/service/dictionary/online_dictionary.dart';
import 'package:anx_reader/service/dictionary/dictionary_source_registry.dart';

// Device-local IDs and explicit network opt-in must not travel in sync backups.
const dictionaryPreferencesKey = 'dictionaryLookupSources';

/// Which dictionary sources the user selected.
///
/// Tokens this build does not recognise are **kept verbatim** in
/// [unknownTokens]: a source may belong to a plugin that is currently
/// uninstalled, and reinstalling it must restore the selection automatically.
class DictionaryPreferences {
  DictionaryPreferences({
    this.localIds,
    Set<OnlineDictionary>? online,
    Set<String>? unknownTokens,
  })  : online = online ?? <OnlineDictionary>{},
        unknownTokens = unknownTokens ?? <String>{};

  final Set<String>? localIds; // null: all enabled local dictionaries
  final Set<OnlineDictionary> online;

  /// Stored tokens with no built-in (or currently installed) source.
  final Set<String> unknownTokens;

  /// Every selected token as written to storage, including unknowns.
  List<String> get tokens => [
        if (localIds == null)
          'local:*'
        else
          ...localIds!.map((id) => 'local:$id'),
        // Built-in online tokens are `online:<enum name>`, which is also the
        // registry id, so no lookup is needed here.
        for (final source in online) 'online:${source.name}',
        ...unknownTokens,
      ];

  static Future<DictionaryPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.get(dictionaryPreferencesKey);
    if (value is! List<String>) return DictionaryPreferences();
    final registry = DictionarySourceRegistry.current;
    final online = <OnlineDictionary>{};
    final unknown = <String>{};
    for (final token in value) {
      if (token.startsWith('local:')) continue;
      final entry = registry.fromToken(token);
      if (entry == null) {
        unknown.add(token);
        continue;
      }
      final source = OnlineDictionary.values
          .where((source) => source.name == entry.id)
          .firstOrNull;
      if (source == null) {
        unknown.add(token);
      } else {
        online.add(source);
      }
    }
    return DictionaryPreferences(
      localIds: value.contains('local:*')
          ? null
          : value
              .where((s) => s.startsWith('local:'))
              .map((s) => s.substring(6))
              .toSet(),
      online: online,
      unknownTokens: unknown,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setStringList(dictionaryPreferencesKey, tokens)) {
      throw StateError('Could not save dictionary sources');
    }
  }
}
