import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_network.dart';

/// Validation and encoding for the per-plugin `pluginConfig_<id>` preference.
///
/// Only values the user changed are stored; absent keys keep the manifest
/// default. Settings are primitive values, never credentials: `secret` entries
/// are rejected outright and live under `pluginSecret_<id>` instead, so this
/// object can keep travelling in settings backups without credential handling.
class PluginConfig {
  const PluginConfig._();

  static const String prefix = 'pluginConfig_';
  static const String devicePrefix = 'pluginDeviceConfig_';
  static const String secretPrefix = 'pluginSecret_';
  static const int maxEntries = 40;
  static const int maxKeyLength = 40;
  static const int maxTextLength = 8000;

  static String keyFor(String pluginId) => '$prefix$pluginId';
  static String deviceKeyFor(String pluginId) => '$devicePrefix$pluginId';
  static String secretKeyFor(String pluginId) => '$secretPrefix$pluginId';

  static Map<String, dynamic> forStorage(PluginManifest manifest,
      Map<String, dynamic> values, PluginSettingStorage storage) {
    final specs = {for (final spec in manifest.settings) spec.key: spec};
    return {
      for (final entry in sanitize(manifest, values).entries)
        if (specs[entry.key]?.binding == null &&
            (specs[entry.key]?.storage ?? PluginSettingStorage.sync) == storage)
          entry.key: entry.value,
    };
  }

  static Map<String, dynamic> decode(Object? raw) {
    if (raw is String) {
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        throw const FormatException('Plugin settings are not valid JSON');
      }
      return decode(decoded);
    }
    if (raw is! Map) {
      throw const FormatException('Plugin settings must be an object');
    }
    if (raw.length > maxEntries) {
      throw const FormatException('Plugin settings have too many entries');
    }
    final values = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String ||
          key.length > maxKeyLength ||
          !settingKeyPattern.hasMatch(key)) {
        throw const FormatException('Invalid plugin setting key');
      }
      final value = entry.value;
      if (value is String) {
        if (value.runes.length > maxTextLength) {
          throw const FormatException('Plugin setting text is too long');
        }
      } else if (value is! num && value is! bool) {
        throw const FormatException('Invalid plugin setting value');
      }
      values[key] = value;
    }
    return values;
  }

  /// Validates shape and, when the package is installed, the declared types.
  /// Unknown keys are preserved for forward compatibility with newer packages.
  static void validate(String pluginId, Object? raw,
      {PluginManifest? manifest}) {
    if (!pluginIdPattern.hasMatch(pluginId)) {
      throw const FormatException('Invalid plugin id');
    }
    final values = decode(raw);
    if (manifest == null) return;
    for (final spec in manifest.settings) {
      if (!values.containsKey(spec.key)) continue;
      final value = values[spec.key];
      switch (spec.type) {
        case PluginSettingType.text:
          if (value is! String) {
            throw const FormatException('Invalid plugin text setting');
          }
          break;
        case PluginSettingType.number:
          if (value is! num) {
            throw const FormatException('Invalid plugin number setting');
          }
          break;
        case PluginSettingType.toggle:
          if (value is! bool) {
            throw const FormatException('Invalid plugin toggle setting');
          }
          break;
        case PluginSettingType.select:
          if (value is! String || !spec.options.contains(value)) {
            throw const FormatException('Invalid plugin select setting');
          }
          break;
        case PluginSettingType.tip:
          throw const FormatException(
              'Plugin tip settings cannot store values');
        case PluginSettingType.secret:
          // Secrets live under pluginSecret_<id>; encountering one here means a
          // backup or a hand-edited payload tried to smuggle a credential into
          // the ordinary configuration object.
          throw const FormatException(
              'Plugin secrets cannot be stored in plugin settings');
      }
    }
  }

  /// Drops stored values that no longer match the current manifest, so a
  /// package update cannot crash the settings form or block an export.
  static Map<String, dynamic> sanitize(
      PluginManifest manifest, Map<String, dynamic> saved) {
    final values = Map<String, dynamic>.from(saved);
    for (final spec in manifest.settings) {
      final value = values[spec.key];
      if (value == null && !values.containsKey(spec.key)) continue;
      final valid = switch (spec.type) {
        PluginSettingType.text => value is String,
        PluginSettingType.number => value is num,
        PluginSettingType.toggle => value is bool,
        PluginSettingType.select =>
          value is String && spec.options.contains(value),
        PluginSettingType.tip => false,
        // Secrets are never part of this map, even if an old payload has one.
        PluginSettingType.secret => false,
      };
      if (!valid) values.remove(spec.key);
    }
    return values;
  }
}

/// Authenticated request settings are resolved only by the native host.
class PluginRequestSettings {
  PluginRequestSettings(PluginManifest manifest, Map<String, dynamic> values) {
    final request = manifest.network?.request;
    if (request == null) throw const FormatException('No plugin request rules');
    final defaults = {
      for (final spec in manifest.settings) spec.key: spec.defaultValue
    };
    Object? read(String key) => values[key] ?? defaults[key];
    final url = read(request.baseUrlSetting);
    if (url is! String) throw const FormatException('Missing plugin server');
    base = PluginAuthenticatedRequest.baseUri(url);
    for (final entry in request.headers.entries) {
      final reference = PluginAuthenticatedRequest.credentialReference
          .firstMatch(entry.value);
      if (reference == null) {
        headers[entry.key] = entry.value;
      } else if (reference.group(1) == 'secret') {
        secretHeaders[entry.key] = reference.group(2)!;
      } else {
        final value = read(reference.group(2)!);
        if (value is! String ||
            !validHeaderValue(value) ||
            value.length > 256) {
          throw const FormatException('Invalid plugin authentication setting');
        }
        headers[entry.key] = value;
      }
    }
    scope = sha256
        .convert(
            utf8.encode(jsonEncode([base.toString(), headers, secretHeaders])))
        .toString();
  }

  late final Uri base;
  late final String scope;
  final headers = <String, String>{};
  final secretHeaders = <String, String>{};

  static bool validHeaderValue(String value) =>
      value.isNotEmpty &&
      value == value.trim() &&
      RegExp(r'^[\x20-\x7e]+$').hasMatch(value);
}
