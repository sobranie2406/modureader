import 'package:anx_reader/models/plugin_manifest.dart';

enum PluginStatus {
  enabled,
  disabled,
  broken,
  missing;

  static PluginStatus parse(Object? value) {
    for (final status in PluginStatus.values) {
      if (status.name == value) return status;
    }
    return PluginStatus.disabled;
  }

  bool get contributes => this == PluginStatus.enabled;
}

/// One materialised contribution. The hash is of the value written into the
/// host data structure (prompt content in P1a) and drives the uninstall guard.
class AppliedContribution {
  const AppliedContribution({
    required this.kind,
    required this.id,
    required this.contentSha256,
  });

  final String kind;
  final String id;
  final String contentSha256;

  Map<String, Object?> toJson() => {
        'kind': kind,
        'id': id,
        'contentSha256': contentSha256,
      };

  static AppliedContribution fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Applied contribution must be an object');
    }
    final kind = raw['kind'];
    final id = raw['id'];
    final hash = raw['contentSha256'];
    if (kind is! String || id is! String || hash is! String) {
      throw const FormatException('Applied contribution fields are invalid');
    }
    return AppliedContribution(kind: kind, id: id, contentSha256: hash);
  }
}

class PluginRecord {
  const PluginRecord({
    required this.id,
    required this.version,
    required this.name,
    required this.license,
    this.author,
    required this.installedAt,
    required this.sha256,
    required this.status,
    this.applied = const [],
    this.lastError,
  });

  final String id;
  final String version;
  final PluginText name;
  final String license;
  final String? author;
  final DateTime installedAt;
  final String sha256;
  final PluginStatus status;
  final List<AppliedContribution> applied;
  final String? lastError;

  bool get isUsable =>
      status == PluginStatus.enabled || status == PluginStatus.disabled;

  PluginRecord copyWith({
    String? version,
    PluginText? name,
    String? license,
    String? author,
    DateTime? installedAt,
    String? sha256,
    PluginStatus? status,
    List<AppliedContribution>? applied,
    String? lastError,
    bool clearLastError = false,
  }) {
    return PluginRecord(
      id: id,
      version: version ?? this.version,
      name: name ?? this.name,
      license: license ?? this.license,
      author: author ?? this.author,
      installedAt: installedAt ?? this.installedAt,
      sha256: sha256 ?? this.sha256,
      status: status ?? this.status,
      applied: applied ?? this.applied,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'name': name.toJson(),
        'license': license,
        if (author != null) 'author': author,
        'installedAt': installedAt.toUtc().toIso8601String(),
        'sha256': sha256,
        'status': status.name,
        'applied': applied.map((item) => item.toJson()).toList(),
        if (lastError != null) 'lastError': lastError,
      };

  static PluginRecord fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Plugin record must be an object');
    }
    final id = raw['id'];
    final version = raw['version'];
    final license = raw['license'];
    final sha256 = raw['sha256'];
    final installedAt = raw['installedAt'];
    if (id is! String ||
        id.isEmpty ||
        version is! String ||
        version.isEmpty ||
        license is! String ||
        sha256 is! String ||
        installedAt is! String) {
      throw const FormatException('Plugin record fields are invalid');
    }
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(installedAt);
    } on FormatException {
      throw const FormatException('Plugin record date is invalid');
    }
    final rawApplied = raw['applied'];
    final applied = <AppliedContribution>[];
    if (rawApplied is List) {
      for (final item in rawApplied) {
        try {
          applied.add(AppliedContribution.fromJson(item));
        } on FormatException {
          // A corrupted applied entry must not hide the rest of the plugin.
        }
      }
    }
    final lastError = raw['lastError'];
    return PluginRecord(
      id: id,
      version: version,
      name: PluginText.fromJson(raw['name']),
      license: license,
      author: raw['author'] is String ? raw['author'] as String : null,
      installedAt: parsedDate,
      sha256: sha256,
      status: PluginStatus.parse(raw['status']),
      applied: List.unmodifiable(applied),
      lastError: lastError is String && lastError.isNotEmpty ? lastError : null,
    );
  }
}

/// Backups may not turn the displayed package digest into arbitrary text.
final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

class PluginState {
  const PluginState({this.schemaVersion = 1, this.plugins = const []});

  static const int currentSchemaVersion = 1;
  static const int maxRecords = 100;

  final int schemaVersion;
  final List<PluginRecord> plugins;

  static const PluginState empty = PluginState();

  PluginRecord? byId(String id) {
    for (final plugin in plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  int get enabledCount =>
      plugins.where((plugin) => plugin.status == PluginStatus.enabled).length;

  PluginState upsert(PluginRecord record) {
    final next = [
      for (final plugin in plugins)
        if (plugin.id == record.id) record else plugin,
      if (byId(record.id) == null) record,
    ];
    return PluginState(schemaVersion: schemaVersion, plugins: next);
  }

  PluginState remove(String id) {
    return PluginState(
      schemaVersion: schemaVersion,
      plugins: plugins.where((plugin) => plugin.id != id).toList(),
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'plugins': plugins.map((plugin) => plugin.toJson()).toList(),
      };

  static PluginState fromJson(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Plugin state must be an object');
    }
    final version = raw['schemaVersion'];
    if (version is! int || version != currentSchemaVersion) {
      throw const FormatException('Unsupported plugin state schema');
    }
    final rawPlugins = raw['plugins'];
    if (rawPlugins is! List) {
      throw const FormatException('Plugin state must contain a plugin list');
    }
    final plugins = <PluginRecord>[];
    final seen = <String>{};
    for (final item in rawPlugins) {
      try {
        final record = PluginRecord.fromJson(item);
        if (seen.add(record.id)) plugins.add(record);
      } on FormatException {
        // Skip a single damaged record; keep the rest of the registry usable.
      }
    }
    return PluginState(
        schemaVersion: version, plugins: List.unmodifiable(plugins));
  }

  /// Stricter parser for importing a settings backup: a damaged record rejects
  /// the whole payload instead of silently dropping installed plugins.
  static PluginState parseStrict(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Plugin state must be an object');
    }
    final version = raw['schemaVersion'];
    if (version is! int || version != currentSchemaVersion) {
      throw const FormatException('Unsupported plugin state schema');
    }
    final rawPlugins = raw['plugins'];
    if (rawPlugins is! List || rawPlugins.length > maxRecords) {
      throw const FormatException('Plugin state has an invalid plugin list');
    }
    final plugins = <PluginRecord>[];
    final seen = <String>{};
    for (final item in rawPlugins) {
      final record = PluginRecord.fromJson(item);
      if (!pluginIdPattern.hasMatch(record.id) ||
          !_sha256Pattern.hasMatch(record.sha256) ||
          record.name.isEmpty ||
          !seen.add(record.id)) {
        throw const FormatException('Invalid plugin record');
      }
      plugins.add(record);
    }
    return PluginState(
        schemaVersion: version, plugins: List.unmodifiable(plugins));
  }
}
