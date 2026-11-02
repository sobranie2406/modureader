/// Extension-point registries shared by the app and by plugins.
///
/// Each domain owns one [HostRegistry]. Entries are either built in (shipped
/// with the app) or owned by an installed plugin; a plugin may never replace a
/// built-in entry, so registering a duplicate id fails instead of silently
/// redirecting a default entry point such as translation or speech.
library;

enum RegistryDomain { translate, tts, dictionary, aiTool, readingSkill, toolbar }

/// Who registered an entry. Only the matching owner may unregister it.
sealed class RegistryOwner {
  const RegistryOwner();

  const factory RegistryOwner.builtIn() = BuiltInOwner;
  const factory RegistryOwner.plugin(String pluginId) = PluginOwner;
}

final class BuiltInOwner extends RegistryOwner {
  const BuiltInOwner();

  @override
  bool operator ==(Object other) => other is BuiltInOwner;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'builtIn';
}

final class PluginOwner extends RegistryOwner {
  const PluginOwner(this.pluginId);

  final String pluginId;

  @override
  bool operator ==(Object other) =>
      other is PluginOwner && other.pluginId == pluginId;

  @override
  int get hashCode => pluginId.hashCode;

  @override
  String toString() => 'plugin($pluginId)';
}

/// One registered extension point.
abstract interface class RegistryEntry {
  String get id;

  RegistryDomain get domain;

  RegistryOwner get owner;

  /// Old persisted tokens this entry still answers to. Empty for most entries;
  /// only renamed built-ins need them, which keeps existing settings working.
  List<String> get aliases;
}

/// A single domain's table of entries.
///
/// Lookups are by exact id first, then by alias, so callers can keep writing
/// the old token while the registry normalises it.
class HostRegistry<T extends RegistryEntry> {
  HostRegistry(this.domain);

  final RegistryDomain domain;

  final Map<String, T> _byId = {};
  final Map<String, String> _aliases = {};
  final List<void Function()> _listeners = [];

  List<T> get all => List<T>.unmodifiable(_byId.values);

  bool get isEmpty => _byId.isEmpty;

  T? byId(String id) => _byId[id];

  /// Exact id first, then alias. Returns null when nothing matches; callers
  /// decide whether to fall back, keep the raw value or hide it.
  T? resolve(String id) {
    final direct = _byId[id];
    if (direct != null) return direct;
    final canonical = _aliases[id];
    return canonical == null ? null : _byId[canonical];
  }

  void register(T entry) {
    if (entry.domain != domain) {
      throw ArgumentError(
          "Entry '${entry.id}' belongs to ${entry.domain.name}, not ${domain.name}.");
    }
    if (_byId.containsKey(entry.id)) {
      throw StateError("Duplicate ${domain.name} id: ${entry.id}");
    }
    final seen = <String>{};
    for (final alias in entry.aliases) {
      if (alias == entry.id || !seen.add(alias)) {
        throw StateError("Invalid ${domain.name} alias: $alias");
      }
      if (_byId.containsKey(alias) || _aliases.containsKey(alias)) {
        throw StateError("Duplicate ${domain.name} alias: $alias");
      }
    }
    _byId[entry.id] = entry;
    for (final alias in entry.aliases) {
      _aliases[alias] = entry.id;
    }
    _notify();
  }

  /// Only the owning party may unregister. A plugin can never remove a
  /// built-in entry or another plugin's entry.
  bool unregister(String id, {required RegistryOwner owner}) {
    final entry = _byId[id];
    if (entry == null || entry.owner != owner) return false;
    _byId.remove(id);
    _aliases.removeWhere((_, canonical) => canonical == id);
    _notify();
    return true;
  }

  void removeAllOwnedBy(RegistryOwner owner) {
    final owned = _byId.entries
        .where((entry) => entry.value.owner == owner)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in owned) {
      unregister(id, owner: owner);
    }
  }

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }
}
