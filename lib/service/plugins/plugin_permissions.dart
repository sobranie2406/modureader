import 'dart:convert';

import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_permissions.dart';

/// Device-local runtime permission grants for installed plugins.
///
/// Stored as one JSON map under [prefsKey]:
///
/// ```json
/// {"com.example.plugin": ["ai:invoke", "book:content"]}
/// ```
///
/// Deliberately **not** exported: a grant is a consent decision that belongs to
/// this device, exactly like [Prefs.experimentalPluginsEnabled]. Copying a
/// backup onto another phone must not silently hand a plugin new powers.
///
/// The map only stores *granted* runtime capabilities. Absence means denied, so
/// a capability added by a package update starts denied instead of inheriting
/// its neighbours.
class PluginPermissions {
  const PluginPermissions._();

  static const String prefsKey = 'pluginPermissions';

  /// Plugin ids whose grants have already been decided once.
  ///
  /// Needed because "no grants stored" means both "the user revoked everything"
  /// and "this plugin never ran under the permission system", and those two must
  /// not be treated the same.
  static const String seededKey = 'pluginPermissionsSeeded';

  /// Upper bound on plugins with grants; matches [PluginState.maxRecords].
  static const int maxPlugins = 100;

  /// Static helpers so callers do not need a Prefs instance.
  static Set<String> grantedFrom(
      Map<String, Set<String>> store, String pluginId) {
    return Set.unmodifiable(store[pluginId] ?? const <String>{});
  }

  /// Capabilities the manifest declares **and** that require a user grant.
  static Set<String> requestedRuntime(PluginManifest manifest) => {
        for (final capability in manifest.capabilities)
          if (isRuntimePermission(capability)) capability,
      };

  /// Capabilities declared by the manifest that install alone grants.
  static Set<String> installTier(PluginManifest manifest) => {
        for (final capability in manifest.capabilities)
          if (!isRuntimePermission(capability)) capability,
      };

  /// True when [capability] is both declared and granted for [pluginId].
  static bool allows(
      Map<String, Set<String>> store, String pluginId, String capability) {
    if (!isRuntimePermission(capability)) return true;
    return store[pluginId]?.contains(capability) ?? false;
  }

  /// Grants that [manifest] already implies for a package that **shipped
  /// before** manual grants existed, so an upgrade does not break a working
  /// plugin.
  ///
  /// Only ever applied to a plugin that was already installed, never to a fresh
  /// one: a new plugin must ask for everything, otherwise the grandfather list
  /// becomes a quiet way to skip the permission screen.
  static Set<String> legacyGrants(PluginManifest manifest) {
    final runtime = requestedRuntime(manifest);
    return {
      for (final capability in runtime)
        if (kLegacyRuntimeCapabilities.contains(capability)) capability,
    };
  }

  static Map<String, Set<String>> decode(Object? raw) {
    if (raw == null) return {};
    if (raw is! Map) {
      throw const FormatException('Plugin permissions must be an object');
    }
    if (raw.length > maxPlugins) {
      throw const FormatException('Too many plugin permission records');
    }
    final result = <String, Set<String>>{};
    for (final entry in raw.entries) {
      final id = entry.key;
      final values = entry.value;
      if (id is! String || !pluginIdPattern.hasMatch(id)) {
        throw const FormatException('Invalid plugin id in permissions');
      }
      if (values is! List || values.length > kKnownCapabilities.length) {
        throw const FormatException('Invalid permission list');
      }
      final granted = <String>{};
      for (final value in values) {
        if (value is! String || !kKnownCapabilities.contains(value)) {
          throw const FormatException('Unknown capability in permissions');
        }
        if (!isRuntimePermission(value)) {
          throw const FormatException(
              'Install-tier capability cannot be granted at runtime');
        }
        granted.add(value);
      }
      if (granted.isNotEmpty) result[id] = granted;
    }
    return result;
  }

  static String encode(Map<String, Set<String>> grants) {
    final sorted = <String, List<String>>{};
    final ids = grants.keys.toList()..sort();
    for (final id in ids) {
      final values = grants[id];
      if (values == null || values.isEmpty) continue;
      sorted[id] = values.toList()..sort();
    }
    return jsonEncode(sorted);
  }

  /// Drops capabilities that a new package version no longer declares.
  ///
  /// Keeping a stale grant would re-authorise the capability if the package
  /// ever re-added it without the user seeing a fresh request.
  static Map<String, Set<String>> prune(
      Map<String, Set<String>> grants, PluginManifest manifest) {
    final runtime = requestedRuntime(manifest);
    final current = grants[manifest.id] ?? const <String>{};
    final kept = {
      for (final capability in current)
        if (runtime.contains(capability)) capability,
    };
    final next = Map<String, Set<String>>.from(grants);
    if (kept.isEmpty) {
      next.remove(manifest.id);
    } else {
      next[manifest.id] = kept;
    }
    return next;
  }
}
