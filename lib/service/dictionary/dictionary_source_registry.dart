import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/service/registry/host_registry.dart';

/// A dictionary the lookup UI can offer.
///
/// Built-in sources keep their historical tokens (`online:wiktionaryZh`,
/// `local:<uuid>`), so no stored selection needs migrating. P3 plugin sources
/// enter the same registry with the token
/// `online:plugin:<pluginId>:<sourceId>` and `kind: DictionarySourceKind.plugin`.
enum DictionarySourceKind { local, online, plugin }

class DictionarySourceEntry implements RegistryEntry {
  const DictionarySourceEntry({
    required this.id,
    required this.labelZh,
    required this.labelEn,
    required this.kind,
    this.aliases = const [],
    this.license,
    this.attribution,
    this.lookup,
    this.owner = const RegistryOwner.builtIn(),
  });

  /// The bare id, without the `local:` / `online:` prefix.
  @override
  final String id;

  final String labelZh;
  final String labelEn;
  final DictionarySourceKind kind;

  @override
  final List<String> aliases;

  @override
  final RegistryOwner owner;

  /// Built-ins carry the licence of their source; plugin sources must declare
  /// one before they can be installed.
  final String? license;
  final String? attribution;

  /// Null for plugin sources until their handler is installed.
  final Future<List<DictionaryEntry>> Function(String word)? lookup;

  @override
  RegistryDomain get domain => RegistryDomain.dictionary;

  /// The token written to `dictionaryLookupSources`.
  String get token => switch (kind) {
        DictionarySourceKind.local => 'local:$id',
        DictionarySourceKind.online => 'online:$id',
        DictionarySourceKind.plugin => 'online:plugin:$id',
      };

  bool get isOnline => kind != DictionarySourceKind.local;
}

/// Built-in dictionary sources.
class DictionarySourceRegistry {
  DictionarySourceRegistry(Iterable<DictionarySourceEntry> entries) {
    for (final entry in entries) {
      registry.register(entry);
    }
  }

  static final DictionarySourceRegistry instance =
      DictionarySourceRegistry(_builtIn);

  static DictionarySourceRegistry _current = instance;

  static DictionarySourceRegistry get current => _current;

  static void useForTesting(DictionarySourceRegistry? value) =>
      _current = value ?? instance;

  final HostRegistry<DictionarySourceEntry> registry =
      HostRegistry<DictionarySourceEntry>(RegistryDomain.dictionary);

  /// Online sources offered in settings, in registration order.
  List<DictionarySourceEntry> get onlineSources => [
        for (final entry in registry.all)
          if (entry.isOnline && entry.owner is BuiltInOwner) entry,
      ];

  DictionarySourceEntry? byId(String id) => registry.byId(id);

  /// Resolves a stored token (`online:wiktionaryZh`). Returns null for tokens
  /// this build does not know; callers keep them in storage instead of dropping
  /// them, so reinstalling a plugin restores the selection.
  DictionarySourceEntry? fromToken(String token) {
    if (token.startsWith('online:plugin:')) {
      return registry.byId(token.substring('online:plugin:'.length));
    }
    if (token.startsWith('online:')) {
      return registry.byId(token.substring('online:'.length));
    }
    return null;
  }

  static final List<DictionarySourceEntry> _builtIn = const [
    DictionarySourceEntry(
      id: 'wiktionaryZh',
      labelZh: '维基词典 · 中文',
      labelEn: 'Wiktionary · Chinese',
      kind: DictionarySourceKind.online,
      license: 'CC BY-SA 4.0',
      attribution: 'Wiktionary contributors',
    ),
    DictionarySourceEntry(
      id: 'wiktionaryEn',
      labelZh: '维基词典 · 英文',
      labelEn: 'Wiktionary · English',
      kind: DictionarySourceKind.online,
      license: 'CC BY-SA 4.0',
      attribution: 'Wiktionary contributors',
    ),
  ];
}
