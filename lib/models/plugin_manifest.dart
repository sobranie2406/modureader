import 'dart:convert';

import 'package:modu_reader/models/plugin_network.dart';

import 'package:pub_semver/pub_semver.dart';

/// Structural limits for a v1 plugin package. The package reader enforces the
/// byte limits while unzipping; the manifest keeps its own limits so that a
/// manifest parsed in isolation (tests, future import paths) is still bounded.
class PluginLimits {
  const PluginLimits._();

  static const int maxPackageBytes = 5 * 1024 * 1024;
  static const int maxExtractedBytes = 20 * 1024 * 1024;
  static const int maxEntries = 200;
  static const int maxFileBytes = 1024 * 1024;
  static const int maxCompressionRatio = 200;
  static const int maxManifestBytes = 64 * 1024;
  static const int maxContributions = 40;
  static const int maxPromptsPerPlugin = 30;
  static const int maxPromptLength = 8000;
  static const int maxDisplayNameLength = 40;
  static const int maxSelectionActionNameLength = 30;
  static const int maxSelectionActionsPerPlugin = 24;
  static const int maxDictionarySourcesPerPlugin = 8;
  static const int maxDescriptionLength = 2000;
  static const int maxSettingLabelLength = 80;
  static const int maxIdLength = 64;
}

/// Capability tokens understood by the manifest parser.
///
/// `net:http` is parsed for validation tests, but PluginHost rejects installation
/// until consent, secret storage and dictionary integration are complete.
/// `storage:plugin` is implicit (plugins always own their private directory)
/// but declared packages are accepted for forward compatibility.
const Set<String> kP1SupportedCapabilities = {
  'ai:prompt-pack',
  'ui:selection-action',
  'net:http',
  'storage:plugin',
};

/// Capabilities reserved for later phases. A package declaring one of these is
/// rejected with a "requires a newer version" error rather than silently
/// accepted, which is the fail-closed side of decision D2.
const Set<String> kKnownCapabilities = {
  'ai:prompt-pack',
  'ui:selection-action',
  'net:http',
  'script:run',
  'library:read',
  'storage:plugin',
};

const String kAiPromptPackCapability = 'ai:prompt-pack';
const String kSelectionActionCapability = 'ui:selection-action';
const String kAiSkillContributionKind = 'aiSkill';
const String kSelectionActionContributionKind = 'selectionAction';
const String kDictionarySourceContributionKind = 'dictionarySource';

enum PluginErrorCode {
  untrustedPackage,
  invalidPackage,
  packageTooLarge,
  tooManyEntries,
  suspiciousCompressionRatio,
  invalidPath,
  duplicateEntry,
  missingManifest,
  manifestTooLarge,
  invalidManifest,
  unsupportedSchema,
  invalidPluginId,
  invalidVersion,
  missingLicense,
  invalidLicense,
  unsupportedHostApi,
  appTooOld,
  unknownCapability,
  capabilityUnavailable,
  tooManyContributions,
  invalidContribution,
  duplicateContribution,
  promptTooLong,
  nameTooLong,
  invalidSetting,
  duplicateSetting,
  unsupportedSettingType,
  alreadyInstalled,
  downgradeNotAllowed,
  notInstalled,
  pluginUnavailable,
  promptConflict,
  toolbarConflict,
  noToolbarSlots,
  internal,
}

/// Structured install failure. UI shows [message]; logs record only [code] and
/// [entry] so that prompt text and credentials never reach log files.
class PluginInstallError implements Exception {
  const PluginInstallError(this.code, this.message, {this.entry});

  final PluginErrorCode code;
  final String message;
  final String? entry;

  factory PluginInstallError.invalidPath(String name) => PluginInstallError(
      PluginErrorCode.invalidPath, 'Package entry has an unsafe path.',
      entry: name);

  factory PluginInstallError.tooLarge(String name) => PluginInstallError(
      PluginErrorCode.packageTooLarge, 'Package exceeds the size limit.',
      entry: name);

  factory PluginInstallError.internal(String message) =>
      PluginInstallError(PluginErrorCode.internal, message);

  factory PluginInstallError.noToolbarSlots(int remaining) => PluginInstallError(
      PluginErrorCode.noToolbarSlots,
      'The selection toolbar has only $remaining free slot(s). Remove a custom action and try again.');

  @override
  String toString() => 'PluginInstallError(${code.name}): $message';
}

/// A localised manifest string: either a plain string or `{locale: string}`.
class PluginText {
  const PluginText(this.values);

  final Map<String, String> values;

  bool get isEmpty => values.isEmpty;

  static PluginText parse(
    Object? raw, {
    required String field,
    int maxLength = PluginLimits.maxDescriptionLength,
    bool allowEmpty = false,
  }) {
    final Map<String, String> values = {};
    if (raw is String) {
      final value = raw.trim();
      if (value.isEmpty && !allowEmpty) {
        throw PluginInstallError(
            PluginErrorCode.invalidManifest, '$field must not be empty.');
      }
      if (_runes(value) > maxLength) {
        throw PluginInstallError(PluginErrorCode.nameTooLong,
            '$field exceeds $maxLength characters.');
      }
      values[''] = value;
    } else if (raw is Map) {
      if (raw.length > 16) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            '$field has too many locale variants.');
      }
      for (final entry in raw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || key.trim().isEmpty || key.length > 16) {
          throw PluginInstallError(PluginErrorCode.invalidManifest,
              '$field has an invalid locale key.');
        }
        if (value is! String || (value.trim().isEmpty && !allowEmpty)) {
          throw PluginInstallError(PluginErrorCode.invalidManifest,
              '$field locale value must be a non-empty string.');
        }
        if (_runes(value) > maxLength) {
          throw PluginInstallError(PluginErrorCode.nameTooLong,
              '$field exceeds $maxLength characters.');
        }
        values[key.trim()] = value.trim();
      }
      if (values.isEmpty && !allowEmpty) {
        throw PluginInstallError(
            PluginErrorCode.invalidManifest, '$field must not be empty.');
      }
    } else {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          '$field must be a string or a locale map.');
    }
    return PluginText(values);
  }

  /// Exact tag, then language prefix, then English, then the first value.
  String resolve(String? locale) {
    if (values.isEmpty) return '';
    final normalized = (locale ?? '').replaceAll('_', '-').toLowerCase().trim();
    if (normalized.isEmpty) {
      return values['en'] ?? values.values.first;
    }
    final byLowerKey = {
      for (final entry in values.entries) entry.key.toLowerCase(): entry.value,
    };
    final exact = byLowerKey[normalized];
    if (exact != null) return exact;
    final language = normalized.split('-').first;
    final prefix = byLowerKey[language];
    if (prefix != null) return prefix;
    final compatible = byLowerKey.entries
        .where((entry) => entry.key.split('-').first == language)
        .map((entry) => entry.value)
        .firstOrNull;
    if (compatible != null) return compatible;
    return byLowerKey['en'] ?? values.values.first;
  }

  Map<String, String> toJson() => Map<String, String>.from(values);

  static PluginText fromJson(Object? raw) {
    if (raw is Map) {
      return PluginText(
          raw.map((key, value) => MapEntry(key.toString(), value.toString())));
    }
    if (raw is String) return PluginText({'': raw});
    return const PluginText({});
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PluginText || other.values.length != values.length) {
      return false;
    }
    for (final entry in values.entries) {
      if (other.values[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(
      values.entries.map((entry) => Object.hash(entry.key, entry.value)));
}

class PluginAuthor {
  const PluginAuthor({required this.name, this.url});

  final String name;
  final String? url;

  static PluginAuthor? parse(Object? raw, String field) {
    if (raw == null) return null;
    if (raw is String) {
      final name = raw.trim();
      if (name.isEmpty) {
        throw PluginInstallError(
            PluginErrorCode.invalidManifest, '$field must not be empty.');
      }
      if (_runes(name) > 100) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            '$field exceeds the allowed length.');
      }
      return PluginAuthor(name: name);
    }
    if (raw is Map) {
      final name = raw['name'];
      final url = raw['url'];
      if (name is! String || name.trim().isEmpty) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            '$field.name must be a non-empty string.');
      }
      if (_runes(name.trim()) > 100) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            '$field.name exceeds the allowed length.');
      }
      if (url != null) {
        if (url is! String || url.trim().isEmpty) {
          throw PluginInstallError(PluginErrorCode.invalidManifest,
              '$field.url must be a non-empty string.');
        }
        final uri = Uri.tryParse(url.trim());
        if (uri == null ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          throw PluginInstallError(PluginErrorCode.invalidManifest,
              '$field.url must be an http(s) URL.');
        }
      }
      return PluginAuthor(
        name: name.trim(),
        url: url is String ? url.trim() : null,
      );
    }
    throw PluginInstallError(PluginErrorCode.invalidManifest,
        '$field must be a string or an object.');
  }

  Map<String, Object?> toJson() => {
        'name': name,
        if (url != null) 'url': url,
      };

  @override
  bool operator ==(Object other) =>
      other is PluginAuthor && other.name == name && other.url == url;

  @override
  int get hashCode => Object.hash(name, url);
}

sealed class PluginContribution {
  const PluginContribution({
    required this.kind,
    required this.schema,
    required this.id,
    required this.index,
    required this.raw,
  });

  final String kind;
  final int schema;
  final String id;
  final int index;
  final Map<String, dynamic> raw;

  static PluginContribution parse(
    Map<String, dynamic> json, {
    required int index,
    required List<String> warnings,
    PluginNetwork? network,
  }) {
    final kind = json['kind'];
    if (kind is! String || kind.trim().isEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].kind must be a non-empty string.');
    }
    final schema = json['schema'];
    if (schema is! int || schema < 1) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].schema must be a positive integer.');
    }
    final rawId = json['id'];
    final id = rawId is String ? rawId : '';
    if (kind == kAiSkillContributionKind) {
      if (!_skillIdPattern.hasMatch(id)) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            'contributes[$index].id is invalid.');
      }
      return AiSkillContribution.parse(
          kind: kind, schema: schema, id: id, index: index, raw: json);
    }
    if (kind == kSelectionActionContributionKind) {
      if (!_skillIdPattern.hasMatch(id)) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            'contributes[$index].id is invalid.');
      }
      return SelectionActionContribution.parse(
          kind: kind, schema: schema, id: id, index: index, raw: json);
    }
    if (kind == kDictionarySourceContributionKind) {
      if (!_skillIdPattern.hasMatch(id)) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            'contributes[$index].id is invalid.');
      }
      return DictionarySourceContribution.parse(
          kind: kind,
          schema: schema,
          id: id,
          index: index,
          raw: json,
          network: network);
    }
    // Forward compatibility: an unknown kind is skipped even if new fields or
    // a missing id would fail the known-kind schema (decision D1).
    warnings.add(
        "Contribution kind '$kind' (id: ${id.isEmpty ? '?' : id}) is not supported and was skipped.");
    return UnknownContribution(
        kind: kind,
        schema: schema,
        id: id.isEmpty ? 'unknown-$index' : id,
        index: index,
        raw: json);
  }
}

class UnknownContribution extends PluginContribution {
  const UnknownContribution({
    required super.kind,
    required super.schema,
    required super.id,
    required super.index,
    required super.raw,
  });
}

class AiSkillContribution extends PluginContribution {
  const AiSkillContribution({
    required super.kind,
    required super.schema,
    required super.id,
    required super.index,
    required super.raw,
    required this.name,
    required this.description,
    required this.prompt,
    required this.enabled,
  });

  final PluginText name;
  final PluginText? description;
  final String prompt;
  final bool enabled;

  factory AiSkillContribution.parse({
    required String kind,
    required int schema,
    required String id,
    required int index,
    required Map<String, dynamic> raw,
  }) {
    final name = PluginText.parse(raw['name'],
        field: 'contributes[$index].name',
        maxLength: PluginLimits.maxDisplayNameLength);
    final description = raw['description'] == null
        ? null
        : PluginText.parse(raw['description'],
            field: 'contributes[$index].description');
    final prompt = raw['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].prompt must be a non-empty string.');
    }
    if (_runes(prompt) > PluginLimits.maxPromptLength) {
      throw PluginInstallError(PluginErrorCode.promptTooLong,
          'contributes[$index].prompt exceeds ${PluginLimits.maxPromptLength} characters.');
    }
    final enabled = raw['enabled'];
    if (enabled != null && enabled is! bool) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].enabled must be a boolean.');
    }
    return AiSkillContribution(
      kind: kind,
      schema: schema,
      id: id,
      index: index,
      raw: raw,
      name: name,
      description: description,
      prompt: prompt,
      enabled: enabled is bool ? enabled : true,
    );
  }
}

enum PluginSelectionScope { selection, context }

/// A declarative selection-toolbar action. It materialises as a custom AI
/// command (`SelectionToolbarItem(action: 'aiCommand')`), so the existing
/// toolbar runtime executes it without any plugin-specific branch.
class SelectionActionContribution extends PluginContribution {
  const SelectionActionContribution({
    required super.kind,
    required super.schema,
    required super.id,
    required super.index,
    required super.raw,
    required this.name,
    required this.prompt,
    required this.icon,
    required this.scope,
    required this.enabled,
  });

  final PluginText name;
  final String prompt;
  final String icon;
  final PluginSelectionScope scope;
  final bool enabled;

  factory SelectionActionContribution.parse({
    required String kind,
    required int schema,
    required String id,
    required int index,
    required Map<String, dynamic> raw,
  }) {
    final name = PluginText.parse(raw['name'],
        field: 'contributes[$index].name',
        maxLength: PluginLimits.maxSelectionActionNameLength);
    final prompt = raw['prompt'];
    if (prompt is! String || prompt.trim().isEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].prompt must be a non-empty string.');
    }
    if (_runes(prompt) > PluginLimits.maxPromptLength) {
      throw PluginInstallError(PluginErrorCode.promptTooLong,
          'contributes[$index].prompt exceeds ${PluginLimits.maxPromptLength} characters.');
    }
    final icon = raw['icon'];
    if (icon is! String || !_iconIdPattern.hasMatch(icon)) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].icon must be a toolbar icon id.');
    }
    final scopeRaw = raw['scope'] ?? PluginSelectionScope.context.name;
    final scope = PluginSelectionScope.values
        .where((value) => value.name == scopeRaw)
        .firstOrNull;
    if (scope == null) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].scope must be "selection" or "context".');
    }
    final enabled = raw['enabled'];
    if (enabled != null && enabled is! bool) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].enabled must be a boolean.');
    }
    return SelectionActionContribution(
      kind: kind,
      schema: schema,
      id: id,
      index: index,
      raw: raw,
      name: name,
      prompt: prompt,
      icon: icon,
      scope: scope,
      enabled: enabled is bool ? enabled : true,
    );
  }
}

/// Setting kinds.
///
/// `secret` is a P3 addition: the value never enters `pluginConfig_`, is stored
/// under `pluginSecret_<pluginId>`, and is never exported or logged. It is only
/// accepted in packages that declare `net:http`.
enum PluginSettingType { text, number, toggle, select, tip, secret }

class PluginSettingSpec {
  const PluginSettingSpec({
    required this.key,
    required this.type,
    required this.label,
    this.description,
    this.defaultValue,
    this.options = const [],
    this.required = false,
  });

  final String key;
  final PluginSettingType type;
  final PluginText? label;
  final PluginText? description;
  final Object? defaultValue;
  final List<String> options;

  /// Secrets only: when true a lookup fails instead of silently omitting the
  /// header, so a misconfigured source reports a configuration error.
  final bool required;

  bool get isSecret => type == PluginSettingType.secret;

  static PluginSettingSpec parse(Object? raw, int index) {
    if (raw is! Map) {
      throw PluginInstallError(PluginErrorCode.invalidSetting,
          'settings[$index] must be an object.');
    }
    final key = raw['key'];
    if (key is! String || !settingKeyPattern.hasMatch(key)) {
      throw PluginInstallError(
          PluginErrorCode.invalidSetting, 'settings[$index].key is invalid.');
    }
    final typeName = raw['type'];
    final type = PluginSettingType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    if (type == null) {
      throw PluginInstallError(PluginErrorCode.unsupportedSettingType,
          'settings[$index].type is not supported.');
    }
    final label = raw['label'] == null
        ? null
        : PluginText.parse(raw['label'],
            field: 'settings[$index].label',
            maxLength: PluginLimits.maxSettingLabelLength);
    final description = raw['description'] == null
        ? null
        : PluginText.parse(raw['description'],
            field: 'settings[$index].description');
    final defaultValue = raw['defaultValue'];
    var options = const <String>[];
    switch (type) {
      case PluginSettingType.text:
        if (defaultValue != null && defaultValue is! String) {
          throw PluginInstallError(PluginErrorCode.invalidSetting,
              'settings[$index].defaultValue must be a string.');
        }
        break;
      case PluginSettingType.number:
        if (defaultValue != null && defaultValue is! num) {
          throw PluginInstallError(PluginErrorCode.invalidSetting,
              'settings[$index].defaultValue must be a number.');
        }
        break;
      case PluginSettingType.toggle:
        if (defaultValue != null && defaultValue is! bool) {
          throw PluginInstallError(PluginErrorCode.invalidSetting,
              'settings[$index].defaultValue must be a boolean.');
        }
        break;
      case PluginSettingType.select:
        final rawOptions = raw['options'];
        if (rawOptions is! List ||
            rawOptions.isEmpty ||
            rawOptions.length > 100 ||
            rawOptions.any((option) => option is! String)) {
          throw PluginInstallError(PluginErrorCode.invalidSetting,
              'settings[$index].options must be a non-empty string list.');
        }
        options = rawOptions.cast<String>();
        if (defaultValue != null &&
            (defaultValue is! String || !options.contains(defaultValue))) {
          throw PluginInstallError(PluginErrorCode.invalidSetting,
              'settings[$index].defaultValue must be one of the options.');
        }
        break;
      case PluginSettingType.tip:
        break;
      case PluginSettingType.secret:
        // A secret has no default: shipping one would put a credential in the
        // package, and every user would share it.
        if (defaultValue != null) {
          throw PluginInstallError(PluginErrorCode.invalidSetting,
              'settings[$index].defaultValue is not allowed for a secret.');
        }
        break;
    }
    final requiredRaw = raw['required'];
    if (type == PluginSettingType.secret) {
      if (requiredRaw != null && requiredRaw is! bool) {
        throw PluginInstallError(PluginErrorCode.invalidSetting,
            'settings[$index].required must be a boolean.');
      }
    } else if (requiredRaw != null) {
      throw PluginInstallError(PluginErrorCode.invalidSetting,
          'settings[$index].required is only valid for a secret.');
    }
    return PluginSettingSpec(
      key: key,
      type: type,
      label: label,
      description: description,
      defaultValue: defaultValue,
      options: options,
      required: requiredRaw is bool ? requiredRaw : false,
    );
  }
}

class PluginManifest {
  const PluginManifest({
    required this.schemaVersion,
    required this.id,
    required this.version,
    required this.name,
    required this.description,
    required this.author,
    required this.license,
    required this.minAppVersion,
    required this.capabilities,
    required this.contributions,
    required this.settings,
    required this.hostApi,
    required this.warnings,
    this.network,
  });

  final int schemaVersion;
  final String id;
  final String version;
  final PluginText name;
  final PluginText description;
  final PluginAuthor? author;
  final String license;
  final String? minAppVersion;
  final Set<String> capabilities;
  final List<PluginContribution> contributions;
  final List<PluginSettingSpec> settings;
  final int hostApi;

  /// Declarative network block; null unless the package declares `net:http`.
  final PluginNetwork? network;

  /// Non-fatal issues, e.g. unsupported contribution kinds that were skipped.
  final List<String> warnings;

  static const int supportedSchemaVersion = 1;
  static const int supportedHostApi = 1;

  static PluginManifest parse(
    String raw, {
    Set<String> allowedCapabilities = kP1SupportedCapabilities,
  }) {
    if (utf8.encode(raw).length > PluginLimits.maxManifestBytes) {
      throw PluginInstallError(PluginErrorCode.manifestTooLarge,
          'manifest.json exceeds ${PluginLimits.maxManifestBytes} bytes.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'manifest.json is not valid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          'manifest.json must contain a JSON object.');
    }
    return fromJson(decoded, allowedCapabilities: allowedCapabilities);
  }

  static PluginManifest fromJson(
    Map<String, dynamic> json, {
    Set<String> allowedCapabilities = kP1SupportedCapabilities,
  }) {
    final warnings = <String>[];
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int) {
      throw PluginInstallError(PluginErrorCode.unsupportedSchema,
          'schemaVersion must be an integer.');
    }
    if (schemaVersion != supportedSchemaVersion) {
      throw PluginInstallError(PluginErrorCode.unsupportedSchema,
          'Package schema version $schemaVersion is not supported. Please update the app.');
    }

    final id = json['id'];
    if (id is! String || !pluginIdPattern.hasMatch(id)) {
      throw PluginInstallError(PluginErrorCode.invalidPluginId,
          'Plugin id must match ${pluginIdPattern.pattern}.');
    }

    final versionRaw = json['version'];
    if (versionRaw is! String || !_strictVersionPattern.hasMatch(versionRaw)) {
      throw PluginInstallError(PluginErrorCode.invalidVersion,
          'version must be a stable semantic version such as 1.0.0.');
    }
    try {
      Version.parse(versionRaw);
    } on FormatException {
      throw PluginInstallError(
          PluginErrorCode.invalidVersion, 'version is not valid semver.');
    }

    final name = PluginText.parse(json['name'],
        field: 'name', maxLength: PluginLimits.maxDisplayNameLength);
    final description = json['description'] == null
        ? const PluginText({})
        : PluginText.parse(json['description'], field: 'description');
    final author = PluginAuthor.parse(json['author'], 'author');

    final license = json['license'];
    if (license is! String || license.trim().isEmpty) {
      throw PluginInstallError(PluginErrorCode.missingLicense,
          'license is required (SPDX identifier).');
    }
    if (license.trim().length > 64 ||
        !_licensePattern.hasMatch(license.trim())) {
      throw PluginInstallError(PluginErrorCode.invalidLicense,
          'license must be an SPDX identifier such as MIT or CC0-1.0.');
    }

    final hostApi = json['hostApi'] ?? supportedHostApi;
    if (hostApi is! int || hostApi != supportedHostApi) {
      throw PluginInstallError(PluginErrorCode.unsupportedHostApi,
          'hostApi $hostApi is not supported. Please update the app.');
    }

    final minAppVersionRaw = json['minAppVersion'];
    if (minAppVersionRaw != null &&
        (minAppVersionRaw is! String ||
            !_strictVersionPattern.hasMatch(minAppVersionRaw))) {
      throw PluginInstallError(
          PluginErrorCode.invalidVersion, 'minAppVersion must be x.y.z.');
    }

    final rawCapabilities = json['capabilities'] ?? const <dynamic>[];
    if (rawCapabilities is! List) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'capabilities must be an array.');
    }
    final capabilities = <String>{};
    for (final capability in rawCapabilities) {
      if (capability is! String || !_capabilityPattern.hasMatch(capability)) {
        throw PluginInstallError(PluginErrorCode.invalidManifest,
            'capabilities contains an invalid token.');
      }
      if (capability == 'storage:plugin') {
        // Always granted implicitly; accept but do not store as a grant.
        continue;
      }
      if (!kKnownCapabilities.contains(capability)) {
        throw PluginInstallError(PluginErrorCode.unknownCapability,
            "Unknown capability '$capability'. This package may be corrupted.");
      }
      if (!allowedCapabilities.contains(capability)) {
        throw PluginInstallError(PluginErrorCode.capabilityUnavailable,
            "Capability '$capability' requires a newer app version.");
      }
      capabilities.add(capability);
    }

    // P3: a network block is mandatory for net:http and forbidden without it.
    // Failing closed here means a package cannot declare a transport it did not
    // ask permission for, nor get permission it never uses.
    final rawNetwork = json['network'];
    final declaresNet = capabilities.contains('net:http');
    if (declaresNet && rawNetwork == null) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          "A package declaring 'net:http' must provide a 'network' block.");
    }
    if (!declaresNet && rawNetwork != null) {
      throw PluginInstallError(PluginErrorCode.invalidManifest,
          "A 'network' block requires the 'net:http' capability.");
    }
    final network = rawNetwork == null ? null : PluginNetwork.parse(rawNetwork);

    final rawContributions = json['contributes'] ?? const <dynamic>[];
    if (rawContributions is! List) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'contributes must be an array.');
    }
    if (rawContributions.length > PluginLimits.maxContributions) {
      throw PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package may declare at most ${PluginLimits.maxContributions} contributions.');
    }
    final contributions = <PluginContribution>[];
    final ids = <String>{};
    for (var index = 0; index < rawContributions.length; index++) {
      final raw = rawContributions[index];
      if (raw is! Map<String, dynamic>) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            'contributes[$index] must be an object.');
      }
      final contribution = PluginContribution.parse(raw,
          index: index, warnings: warnings, network: network);
      if (!ids.add('${contribution.kind}:${contribution.id}')) {
        throw PluginInstallError(PluginErrorCode.duplicateContribution,
            "Duplicate contribution '${contribution.kind}:${contribution.id}'.",
            entry: contribution.id);
      }
      contributions.add(contribution);
    }
    _validateContributionCounts(contributions);

    final rawSettings = json['settings'] ?? const <dynamic>[];
    if (rawSettings is! List) {
      throw PluginInstallError(
          PluginErrorCode.invalidManifest, 'settings must be an array.');
    }
    if (rawSettings.length > 40) {
      throw PluginInstallError(
          PluginErrorCode.invalidSetting, 'Too many settings entries.');
    }
    final settings = <PluginSettingSpec>[];
    final settingKeys = <String>{};
    for (var index = 0; index < rawSettings.length; index++) {
      final setting = PluginSettingSpec.parse(rawSettings[index], index);
      if (!settingKeys.add(setting.key)) {
        throw PluginInstallError(PluginErrorCode.duplicateSetting,
            "Duplicate setting key '${setting.key}'.");
      }
      // A secret is only meaningful when the package can transmit it, and a
      // package without net:http must not accumulate credentials at all.
      if (setting.isSecret && !declaresNet) {
        throw PluginInstallError(PluginErrorCode.invalidSetting,
            "settings[$index] is a secret, which requires the 'net:http' capability.");
      }
      settings.add(setting);
    }

    // Every {setting.<key>} and {secret.<key>} a source references must exist,
    // so a typo is an install error rather than a silently empty request.
    final settingByKey = {for (final setting in settings) setting.key: setting};
    for (final source
        in contributions.whereType<DictionarySourceContribution>()) {
      _validateTemplateReferences(source, settingByKey);
    }

    final dictionarySources = contributions
        .whereType<DictionarySourceContribution>()
        .length;
    if (dictionarySources > PluginLimits.maxDictionarySourcesPerPlugin) {
      throw PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package may declare at most '
          '${PluginLimits.maxDictionarySourcesPerPlugin} dictionary sources.');
    }

    return PluginManifest(
      schemaVersion: schemaVersion,
      id: id,
      version: versionRaw,
      name: name,
      description: description,
      author: author,
      license: license.trim(),
      minAppVersion:
          minAppVersionRaw is String ? minAppVersionRaw.trim() : null,
      capabilities: capabilities,
      contributions: contributions,
      settings: settings,
      hostApi: hostApi,
      warnings: List.unmodifiable(warnings),
      network: network,
    );
  }

  /// Every placeholder in a source's templates must resolve.
  ///
  /// Checked at install time rather than request time: a package that asks for
  /// `{setting.missing}` would otherwise send a literal placeholder to the
  /// upstream API, which is a silent data bug the user cannot diagnose.
  static void _validateTemplateReferences(
    DictionarySourceContribution source,
    Map<String, PluginSettingSpec> settings,
  ) {
    void check(String value, String field, {required bool secretAllowed}) {
      for (final match
          in PluginRequestTemplate.settingPlaceholder.allMatches(value)) {
        final key = match.group(1)!;
        final setting = settings[key];
        if (setting == null) {
          throw PluginInstallError(PluginErrorCode.invalidContribution,
              "$field references an undeclared setting '$key'.");
        }
        if (setting.isSecret) {
          throw PluginInstallError(
              PluginErrorCode.invalidContribution,
              "$field references '$key', which is a secret; secrets may only be used in the Authorization header.");
        }
      }
      for (final match
          in PluginRequestTemplate.secretPlaceholder.allMatches(value)) {
        final key = match.group(1)!;
        if (!secretAllowed) {
          throw PluginInstallError(PluginErrorCode.invalidContribution,
              "$field must not reference the secret '$key'.");
        }
        final setting = settings[key];
        if (setting == null || !setting.isSecret) {
          throw PluginInstallError(PluginErrorCode.invalidContribution,
              "$field references an undeclared secret '$key'.");
        }
      }
    }

    check(source.request.url, 'request.url', secretAllowed: false);
    for (final entry in source.request.query.entries) {
      check(entry.value, 'request.query.${entry.key}', secretAllowed: false);
    }
    for (final entry in source.request.headers.entries) {
      check(entry.value, 'request.headers.${entry.key}',
          secretAllowed: entry.key == 'Authorization');
    }
  }

  static void _validateContributionCounts(
      List<PluginContribution> contributions) {
    final prompts = contributions.whereType<AiSkillContribution>().length;
    if (prompts > PluginLimits.maxPromptsPerPlugin) {
      throw PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package may declare at most ${PluginLimits.maxPromptsPerPlugin} prompt templates.');
    }
    final actions =
        contributions.whereType<SelectionActionContribution>().length;
    if (actions > PluginLimits.maxSelectionActionsPerPlugin) {
      throw PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package may declare at most ${PluginLimits.maxSelectionActionsPerPlugin} selection actions.');
    }
  }

  /// Compares [minAppVersion] against the running app version, ignoring build
  /// metadata. Unknown running versions skip the check rather than block
  /// installs (tests and custom builds).
  void ensureCompatibleWith(String appVersion) {
    final min = minAppVersion;
    if (min == null) return;
    Version? current;
    try {
      current = Version.parse(appVersion.split('+').first);
    } on FormatException {
      return;
    }
    final required = Version.parse(min);
    if (current < required) {
      throw PluginInstallError(PluginErrorCode.appTooOld,
          'This plugin requires app version $min or newer.');
    }
  }

  String get localizedName => name.resolve(null);
}

final RegExp pluginIdPattern =
    RegExp(r'^[a-z0-9]([a-z0-9._-]{1,62}[a-z0-9])?$');
final RegExp _skillIdPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,62}$');
final RegExp _iconIdPattern = RegExp(r'^[a-z][a-z0-9]{0,31}$');
final RegExp settingKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
final RegExp _strictVersionPattern = RegExp(r'^\d+\.\d+\.\d+$');
final RegExp _licensePattern = RegExp(r'^[A-Za-z0-9.+\-(): ]+$');
final RegExp _capabilityPattern = RegExp(r'^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$');

int _runes(String value) => value.runes.length;

/// A declarative dictionary source backed by a host-proxied HTTPS GET.
///
/// The package supplies a request template, a response mapping and the licence
/// it operates under; the host owns the transport, the allowlist, the quotas and
/// the rendering. Nothing here executes code.
class DictionarySourceContribution extends PluginContribution {
  const DictionarySourceContribution({
    required super.kind,
    required super.schema,
    required super.id,
    required super.index,
    required super.raw,
    required this.name,
    required this.request,
    required this.response,
    required this.license,
    required this.attribution,
    required this.licenseUri,
    required this.sourceUrl,
  });

  final PluginText name;
  final PluginRequestTemplate request;
  final PluginResponseMapping response;

  /// Required: the lookup UI shows these next to results.
  final String license;
  final String attribution;
  final String? licenseUri;
  final String? sourceUrl;

  factory DictionarySourceContribution.parse({
    required String kind,
    required int schema,
    required String id,
    required int index,
    required Map<String, dynamic> raw,
    required PluginNetwork? network,
  }) {
    if (network == null) {
      throw PluginInstallError(PluginErrorCode.capabilityUnavailable,
          "contributes[$index] uses 'dictionarySource' but the package declares no 'network' block.");
    }
    final name = PluginText.parse(raw['name'],
        field: 'contributes[$index].name',
        maxLength: PluginLimits.maxDisplayNameLength);

    final license = raw['license'];
    if (license is! String || license.trim().isEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].license is required: a dictionary source must state '
          'the terms of the content it serves.');
    }
    final attribution = raw['attribution'];
    if (attribution is! String || attribution.trim().isEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].attribution is required: results must name their source.');
    }
    if (_runes(attribution.trim()) > 200) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].attribution is too long.');
    }
    final licenseUri =
        _httpsUrl(raw['licenseUri'], 'contributes[$index].licenseUri');
    final sourceUrl =
        _httpsUrl(raw['sourceUrl'], 'contributes[$index].sourceUrl');

    final request = PluginRequestTemplate.parse(raw['request'], network);
    final response = PluginResponseMapping.parse(raw['response']);

    return DictionarySourceContribution(
      kind: kind,
      schema: schema,
      id: id,
      index: index,
      raw: raw,
      name: name,
      request: request,
      response: response,
      license: license.trim(),
      attribution: attribution.trim(),
      licenseUri: licenseUri,
      sourceUrl: sourceUrl,
    );
  }

  /// Optional metadata URLs must be https; a bad one is an error rather than a
  /// silently dropped field, because it is shown to the user as provenance.
  static String? _httpsUrl(Object? raw, String field) {
    if (raw == null) return null;
    if (raw is! String || raw.trim().isEmpty) {
      throw PluginInstallError(
          PluginErrorCode.invalidContribution, '$field must be a string.');
    }
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          '$field must be an https URL without credentials.');
    }
    return raw.trim();
  }
}