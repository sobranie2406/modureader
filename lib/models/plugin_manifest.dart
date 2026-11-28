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
  static const int maxBookActionsPerPlugin = 24;
  static const int maxDictionarySourcesPerPlugin = 8;
  static const int maxScriptBytes = 128 * 1024;
  static const int maxArticleScriptBytes = 512 * 1024;
  static const int maxArticleHtmlBytes = 2 * 1024 * 1024;
  static const int maxArticleMarkdownBytes = 512 * 1024;
  static const int maxDescriptionLength = 2000;
  static const int maxSettingLabelLength = 80;
  static const int maxIdLength = 64;
}

/// Capability tokens understood by the manifest parser.
///
/// Availability and consent are checked by PluginHost after parsing.
/// `storage:plugin` is implicit (plugins always own their private directory)
/// but declared packages are accepted for forward compatibility.
const Set<String> kP1SupportedCapabilities = {
  'ai:prompt-pack',
  'ui:selection-action',
  'ui:book-action',
  'ui:reader-action',
  'net:http',
  kPluginAuthenticatedHttpCapability,
  'storage:plugin',
  'script:run',
  'library:read',
  'note:write',
  'library:private',
  'library:private-control',
  'library:private-policy',
  'settings:device',
  'dictionary:transform',
  'article:capture',
  'article:extract',
  // P6: host API expansion. Each is a runtime grant the user switches on.
  'note:read',
  'book:content',
  'library:write',
  'reading:read',
  kReadingPositionReadCapability,
  kReadingPositionWriteCapability,
  'ai:invoke',
  'translate:invoke',
  'tts:invoke',
  'dictionary:lookup',
  'clipboard:read',
  'clipboard:write',
  'share:text',
  'ui:dialog',
  'ui:progress',
  'url:open',
  'knowledge:query',
  'search:library',
};

/// Known tokens are checked separately from the adapter's allowed capabilities.
const Set<String> kKnownCapabilities = {
  'ai:prompt-pack',
  'ui:selection-action',
  'ui:book-action',
  'ui:reader-action',
  'net:http',
  kPluginAuthenticatedHttpCapability,
  'script:run',
  'library:read',
  'note:write',
  'library:private',
  'library:private-control',
  'library:private-policy',
  'settings:device',
  'dictionary:transform',
  'article:capture',
  'article:extract',
  'storage:plugin',
  'note:read',
  'book:content',
  'library:write',
  'reading:read',
  kReadingPositionReadCapability,
  kReadingPositionWriteCapability,
  'ai:invoke',
  'translate:invoke',
  'tts:invoke',
  'dictionary:lookup',
  'clipboard:read',
  'clipboard:write',
  'share:text',
  'ui:dialog',
  'ui:progress',
  'url:open',
  'knowledge:query',
  'search:library',
};

const String kAiPromptPackCapability = 'ai:prompt-pack';
const String kSelectionActionCapability = 'ui:selection-action';
const String kBookActionCapability = 'ui:book-action';
const String kReaderActionCapability = 'ui:reader-action';
const String kAiSkillContributionKind = 'aiSkill';
const String kSelectionActionContributionKind = 'selectionAction';
const String kDictionarySourceContributionKind = 'dictionarySource';
const String kScriptActionContributionKind = 'scriptAction';
const String kBookActionContributionKind = 'bookAction';
const String kScriptRunCapability = 'script:run';
const String kLibraryReadCapability = 'library:read';
const String kNoteWriteCapability = 'note:write';
const String kLibraryPrivateCapability = 'library:private';
const String kLibraryPrivateControlCapability = 'library:private-control';
const String kLibraryPrivatePolicyCapability = 'library:private-policy';
const String kPluginDeviceSettingsCapability = 'settings:device';
const String kDictionaryTransformCapability = 'dictionary:transform';
const String kArticleCaptureCapability = 'article:capture';
const String kArticleExtractCapability = 'article:extract';
const String kPluginAuthenticatedHttpCapability = 'net:request';

// P6 host API capabilities. Kept next to the tokens above so the manifest and
// the runtime permission catalogue cannot drift apart.
const String kNoteReadCapability = 'note:read';
const String kBookContentCapability = 'book:content';
const String kLibraryWriteCapability = 'library:write';
const String kReadingReadCapability = 'reading:read';
const String kReadingPositionReadCapability = 'reading:position-read';
const String kReadingPositionWriteCapability = 'reading:position-write';
const String kAiInvokeCapability = 'ai:invoke';
const String kTranslateInvokeCapability = 'translate:invoke';
const String kTtsInvokeCapability = 'tts:invoke';
const String kDictionaryLookupCapability = 'dictionary:lookup';
const String kClipboardReadCapability = 'clipboard:read';
const String kClipboardWriteCapability = 'clipboard:write';
const String kShareTextCapability = 'share:text';
const String kUiDialogCapability = 'ui:dialog';
const String kUiProgressCapability = 'ui:progress';
const String kUrlOpenCapability = 'url:open';
const String kKnowledgeQueryCapability = 'knowledge:query';
const String kSearchLibraryCapability = 'search:library';
const String kPluginStorageCapability = 'storage:plugin';

/// Capabilities a package holds by being installed.
///
/// They are never stored as grants, and a package may name them in its
/// manifest only for forward compatibility: the parser drops them from
/// [PluginManifest.capabilities]. Every caller authorising a host call must
/// therefore treat this set as "declared and granted", exactly like an
/// install-tier token, or the call fails with `permission` even though the
/// plugin was never able to fix it — that is what broke `modu.storage.*`.
const Set<String> kImplicitCapabilities = {kPluginStorageCapability};

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
  permissionNotRuntime,
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
    if (kind == kScriptActionContributionKind) {
      if (!_skillIdPattern.hasMatch(id)) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            'contributes[$index].id is invalid.');
      }
      return ScriptActionContribution.parse(
          kind: kind, schema: schema, id: id, index: index, raw: json);
    }
    if (kind == kBookActionContributionKind) {
      if (!_skillIdPattern.hasMatch(id)) {
        throw PluginInstallError(PluginErrorCode.invalidContribution,
            'contributes[$index].id is invalid.');
      }
      return BookActionContribution.parse(
          kind: kind, schema: schema, id: id, index: index, raw: json);
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

/// A package-provided book menu entry for a bounded native command, not code.
class BookActionContribution extends PluginContribution {
  const BookActionContribution({
    required super.kind,
    required super.schema,
    required super.id,
    required super.index,
    required super.raw,
    required this.name,
    required this.command,
    this.privateValue,
    this.lockAfter = false,
    this.lockAfterSetting,
    this.when = 'any',
  });

  final PluginText name;
  final String command;
  final bool? privateValue;
  final bool lockAfter;
  final String? lockAfterSetting;
  final String when;

  factory BookActionContribution.parse({
    required String kind,
    required int schema,
    required String id,
    required int index,
    required Map<String, dynamic> raw,
  }) {
    final command = raw['command'];
    if (schema != 1 ||
        !const {'privateLibrary.hide', 'privateLibrary.setPrivate'}
            .contains(command)) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index] has an unsupported book action.');
    }
    final newFields = ['private', 'lockAfter', 'lockAfterSetting', 'when'];
    if ((command == 'privateLibrary.hide' && newFields.any(raw.containsKey)) ||
        (command == 'privateLibrary.setPrivate' &&
            (raw['private'] is! bool ||
                (raw.containsKey('lockAfter') && raw['lockAfter'] is! bool) ||
                (raw.containsKey('lockAfterSetting') &&
                    (raw['lockAfterSetting'] is! String ||
                        !settingKeyPattern
                            .hasMatch(raw['lockAfterSetting']))) ||
                (raw.containsKey('lockAfter') &&
                    raw.containsKey('lockAfterSetting')) ||
                !const {'public', 'private', 'any'}
                    .contains(raw['when'] ?? 'any')))) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index] has invalid book action options.');
    }
    return BookActionContribution(
        kind: kind,
        schema: schema,
        id: id,
        index: index,
        raw: raw,
        name: PluginText.parse(raw['name'],
            field: 'contributes[$index].name',
            maxLength: PluginLimits.maxSelectionActionNameLength),
        command: command as String,
        privateValue: raw['private'] as bool?,
        lockAfter: raw['lockAfter'] as bool? ?? false,
        lockAfterSetting: raw['lockAfterSetting'] as String?,
        when: raw['when'] as String? ?? 'any');
  }
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

enum PluginScriptSurface {
  selection,
  library,
  dictionary,
  article,
  bookImport,
  reader,
  readerOpen,
}

class ScriptActionContribution extends PluginContribution {
  const ScriptActionContribution({
    required super.kind,
    required super.schema,
    required super.id,
    required super.index,
    required super.raw,
    required this.name,
    required this.entry,
    this.surface = PluginScriptSurface.selection,
    this.scope = PluginSelectionScope.selection,
    this.enabledSetting,
    this.formats = const {},
  });

  final PluginText name;
  final String entry;
  final PluginScriptSurface surface;
  final PluginSelectionScope scope;
  final String? enabledSetting;
  final Set<String> formats;

  bool supportsFormat(String format) =>
      formats.isEmpty || formats.contains(format);

  factory ScriptActionContribution.parse({
    required String kind,
    required int schema,
    required String id,
    required int index,
    required Map<String, dynamic> raw,
  }) {
    if (schema != 1) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].schema is not supported.');
    }
    final entry = raw['entry'];
    if (entry is! String ||
        entry.length > 256 ||
        !RegExp(r'^[A-Za-z0-9_./-]+\.js$').hasMatch(entry) ||
        entry.startsWith('/') ||
        entry
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw PluginInstallError(PluginErrorCode.invalidPath,
          'contributes[$index].entry must be a relative JavaScript file.');
    }
    final surface = PluginScriptSurface.values
        .where((value) => value.name == (raw['surface'] ?? 'selection'))
        .firstOrNull;
    final scope = PluginSelectionScope.values
        .where((value) => value.name == (raw['scope'] ?? 'selection'))
        .firstOrNull;
    if (surface == null ||
        scope == null ||
        (const {
              PluginScriptSurface.dictionary,
              PluginScriptSurface.article,
              PluginScriptSurface.bookImport,
              PluginScriptSurface.reader,
              PluginScriptSurface.readerOpen,
            }.contains(surface) &&
            scope != PluginSelectionScope.selection)) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index] has an invalid surface or scope.');
    }
    final enabledSetting = raw['enabledSetting'];
    if ((raw.containsKey('enabledSetting') ||
            surface == PluginScriptSurface.readerOpen) &&
        ((surface != PluginScriptSurface.bookImport &&
                surface != PluginScriptSurface.readerOpen) ||
            enabledSetting is! String ||
            !settingKeyPattern.hasMatch(enabledSetting))) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].enabledSetting is invalid.');
    }
    final formats = raw['formats'];
    if (raw.containsKey('formats') &&
        ((surface != PluginScriptSurface.reader &&
                surface != PluginScriptSurface.readerOpen) ||
            formats is! List ||
            formats.isEmpty ||
            formats.length > 16 ||
            !formats.every((format) =>
                format is String &&
                RegExp(r'^[a-z0-9]{1,12}$').hasMatch(format)) ||
            formats.toSet().length != formats.length)) {
      throw PluginInstallError(PluginErrorCode.invalidContribution,
          'contributes[$index].formats is invalid.');
    }
    return ScriptActionContribution(
      kind: kind,
      schema: schema,
      id: id,
      index: index,
      raw: raw,
      name: PluginText.parse(raw['name'],
          field: 'contributes[$index].name',
          maxLength: PluginLimits.maxSelectionActionNameLength),
      entry: entry,
      surface: surface,
      scope: scope,
      enabledSetting: enabledSetting as String?,
      formats: formats == null
          ? const {}
          : Set.unmodifiable((formats as List).cast<String>()),
    );
  }
}

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

enum PluginSettingStorage { sync, device }

const Set<String> kPrivateLibrarySettingBindings = {
  'privateLibrary.privateOnly',
  'privateLibrary.autoImport',
  'privateLibrary.lockAfterHide',
};

class PluginSettingSpec {
  const PluginSettingSpec({
    required this.key,
    required this.type,
    required this.label,
    this.description,
    this.defaultValue,
    this.options = const [],
    this.required = false,
    this.storage = PluginSettingStorage.sync,
    this.binding,
    this.secretTransform,
  });

  final String key;
  final PluginSettingType type;
  final PluginText? label;
  final PluginText? description;
  final Object? defaultValue;
  final List<String> options;
  final PluginSettingStorage storage;
  final String? binding;
  final String? secretTransform;
  bool get isDevice => storage == PluginSettingStorage.device;

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
    final transform = raw['transform'];
    if (raw.containsKey('transform') &&
        (type != PluginSettingType.secret || transform != 'md5')) {
      throw PluginInstallError(PluginErrorCode.invalidSetting,
          'settings[$index].transform is invalid.');
    }
    final storage = PluginSettingStorage.values
        .where((entry) => entry.name == (raw['storage'] ?? 'sync'))
        .firstOrNull;
    final binding = raw['binding'];
    if (storage == null ||
        (raw.containsKey('binding') &&
            (binding is! String ||
                !kPrivateLibrarySettingBindings.contains(binding) ||
                type != PluginSettingType.toggle ||
                storage != PluginSettingStorage.device)) ||
        (storage == PluginSettingStorage.device &&
            (type == PluginSettingType.secret ||
                type == PluginSettingType.tip))) {
      throw PluginInstallError(PluginErrorCode.invalidSetting,
          'settings[$index] has an invalid storage or binding.');
    }
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
      storage: storage,
      binding: binding as String?,
      secretTransform: transform as String?,
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
      if (capability == kPluginStorageCapability) {
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
    final authenticated = network?.request;
    if (capabilities.contains(kPluginAuthenticatedHttpCapability) !=
        (authenticated != null)) {
      throw const PluginInstallError(PluginErrorCode.invalidManifest,
          'Authenticated networking requires net:request and network.request.');
    }

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
    if ((capabilities.contains(kLibraryPrivateControlCapability) ||
            capabilities.contains(kLibraryPrivatePolicyCapability)) &&
        !capabilities.contains(kLibraryPrivateCapability)) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Private-library controls and policies require library:private.');
    }
    if (capabilities.contains(kLibraryPrivatePolicyCapability) &&
        !capabilities.contains(kScriptRunCapability)) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Private-library policies require script:run.');
    }
    if (contributions.any((entry) => entry is BookActionContribution) &&
        !capabilities
            .containsAll({kBookActionCapability, kLibraryPrivateCapability})) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Book actions require their book-menu and private-library capabilities.');
    }
    if (contributions
            .whereType<BookActionContribution>()
            .any((action) => action.command == 'privateLibrary.setPrivate') &&
        !capabilities.contains(kLibraryPrivateControlCapability)) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Private-library book controls require library:private-control.');
    }
    for (final action in contributions.whereType<ScriptActionContribution>()) {
      if (!capabilities.contains(kScriptRunCapability) ||
          (action.surface == PluginScriptSurface.selection &&
              !capabilities.contains(kSelectionActionCapability)) ||
          ((action.surface == PluginScriptSurface.reader ||
                  action.surface == PluginScriptSurface.readerOpen) &&
              !capabilities.contains(kReaderActionCapability)) ||
          (action.surface == PluginScriptSurface.dictionary &&
              !capabilities.contains(kDictionaryTransformCapability)) ||
          (action.surface == PluginScriptSurface.article &&
              !capabilities.contains(kArticleExtractCapability)) ||
          (action.surface == PluginScriptSurface.bookImport &&
              !capabilities.containsAll({
                kLibraryPrivateCapability,
                kLibraryPrivatePolicyCapability
              }))) {
        throw PluginInstallError(PluginErrorCode.capabilityUnavailable,
            'Script actions must declare their execution and surface capabilities.');
      }
    }
    if (contributions
            .whereType<ScriptActionContribution>()
            .where((action) => action.surface == PluginScriptSurface.bookImport)
            .length >
        1) {
      throw const PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package may declare only one book import policy.');
    }
    if (contributions
            .whereType<ScriptActionContribution>()
            .where((action) => action.surface == PluginScriptSurface.article)
            .length >
        1) {
      throw const PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package may declare only one article extractor.');
    }

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
      if (setting.isDevice &&
          !capabilities.contains(kPluginDeviceSettingsCapability)) {
        throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
            'Device settings require settings:device.');
      }
      if (setting.binding != null &&
          !capabilities.containsAll(
              {kLibraryPrivateControlCapability, kLibraryPrivateCapability})) {
        throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
            'Private-library bindings require their control capabilities.');
      }
      settings.add(setting);
    }

    // Every {setting.<key>} and {secret.<key>} a source references must exist,
    // so a typo is an install error rather than a silently empty request.
    final settingByKey = {for (final setting in settings) setting.key: setting};
    if (authenticated != null) {
      const invalid = PluginInstallError(PluginErrorCode.invalidSetting,
          'Authenticated networking must use declared local settings.');
      final base = settingByKey[authenticated.baseUrlSetting];
      if (base?.type != PluginSettingType.text ||
          base?.isDevice != true ||
          base?.defaultValue is! String) {
        throw invalid;
      }
      late final Uri defaultUri;
      try {
        defaultUri =
            PluginAuthenticatedRequest.baseUri(base!.defaultValue as String);
      } on FormatException {
        throw invalid;
      }
      if (!network!.allows(defaultUri.host)) throw invalid;
      for (final value in authenticated.headers.values) {
        final reference =
            PluginAuthenticatedRequest.credentialReference.firstMatch(value);
        if (reference == null) continue;
        final spec = settingByKey[reference.group(2)];
        if (reference.group(1) == 'secret'
            ? spec?.isSecret != true
            : spec?.type != PluginSettingType.text || spec?.isDevice != true) {
          throw invalid;
        }
      }
    }
    if (settings
            .where((setting) => setting.binding != null)
            .map((setting) => setting.binding)
            .toSet()
            .length !=
        settings.where((setting) => setting.binding != null).length) {
      throw const PluginInstallError(PluginErrorCode.invalidSetting,
          'A native setting may be bound only once.');
    }
    for (final action in contributions) {
      final key = action is ScriptActionContribution
          ? action.enabledSetting
          : action is BookActionContribution
              ? action.lockAfterSetting
              : null;
      if (action is ScriptActionContribution &&
          action.surface == PluginScriptSurface.readerOpen) {
        final gate = settingByKey[key];
        if (gate?.storage != PluginSettingStorage.device ||
            gate?.defaultValue != false) {
          throw const PluginInstallError(PluginErrorCode.invalidContribution,
              'Reader-open actions require a default-off device toggle.');
        }
      }
      if (key != null && settingByKey[key]?.type != PluginSettingType.toggle) {
        throw const PluginInstallError(PluginErrorCode.invalidContribution,
            'Action setting references must name a declared toggle.');
      }
    }
    for (final source
        in contributions.whereType<DictionarySourceContribution>()) {
      _validateTemplateReferences(source, settingByKey);
    }

    final dictionarySources =
        contributions.whereType<DictionarySourceContribution>().length;
    if (dictionarySources > PluginLimits.maxDictionarySourcesPerPlugin) {
      throw PluginInstallError(
          PluginErrorCode.tooManyContributions,
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
          throw PluginInstallError(PluginErrorCode.invalidContribution,
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
    final bookActions =
        contributions.whereType<BookActionContribution>().length;
    if (bookActions > PluginLimits.maxBookActionsPerPlugin) {
      throw const PluginInstallError(PluginErrorCode.tooManyContributions,
          'A package has too many book actions.');
    }
  }

  /// Compares [minAppVersion] against the app's major/minor/patch; preview
  /// labels keep the same API. Unknown versions skip this check (custom builds).
  void ensureCompatibleWith(String appVersion) {
    final min = minAppVersion;
    if (min == null) return;
    Version? current;
    try {
      final parsed = Version.parse(appVersion.split('+').first);
      current = Version(parsed.major, parsed.minor, parsed.patch);
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
      throw PluginInstallError(
          PluginErrorCode.invalidContribution,
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
