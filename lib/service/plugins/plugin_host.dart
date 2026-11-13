import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_contributions.dart';
import 'package:modu_reader/service/plugins/plugin_package.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:modu_reader/utils/app_version.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

class PluginInstallResult {
  const PluginInstallResult({required this.record, this.warnings = const []});

  final PluginRecord record;
  final List<String> warnings;
}

/// Read-only inspection of a package before anything is written.
///
/// The preview runs the same package, trust and compatibility checks as
/// [PluginHost.install], so a confirmed preview cannot fail for a reason the
/// user could have seen first. Nothing here mutates preferences or the files.
class PluginPreview {
  const PluginPreview({
    required this.manifest,
    required this.manifestText,
    required this.sha256,
    required this.compressedBytes,
    required this.readme,
    required this.warnings,
    required this.installedVersion,
  });

  final PluginManifest manifest;
  final String manifestText;
  final String sha256;
  final int compressedBytes;

  /// First [maxReadmeChars] of the package README, or null when it has none.
  final String? readme;

  /// Non-fatal parsing notices, for example skipped contribution kinds.
  final List<String> warnings;

  /// Version already installed for this id, if any.
  final String? installedVersion;

  static const int maxReadmeChars = 8 * 1024;

  bool get willReplace => installedVersion != null;
}

/// Single source of truth for installed plugins.
///
/// P1a only materialises declarative contributions; no package code runs.
/// All public mutation methods are transactional around the prompt snapshot:
/// a failure restores the snapshot and the filesystem, and never leaves a
/// registry entry behind.
class PluginHost extends ChangeNotifier {
  PluginHost({
    PluginPaths? paths,
    PluginPackageReader? reader,
    PluginContributions? contributions,
    this.trust = const PluginTrust(),
    Future<String> Function()? appVersionResolver,
  })  : _paths = paths ?? PluginPaths(),
        _appVersionResolver = appVersionResolver ?? getAppVersion {
    _reader = reader ?? PluginPackageReader(paths: _paths);
    _contributions = contributions ?? PluginContributions.standard();
  }

  static PluginHost? _instance;

  static PluginHost get instance => _instance ??= PluginHost();

  final PluginPaths _paths;
  @visibleForTesting
  final PluginTrust trust;
  late final PluginPackageReader _reader;
  late final PluginContributions _contributions;
  final Future<String> Function() _appVersionResolver;

  static const bool _compiledIn =
      bool.fromEnvironment('MODU_PLUGINS', defaultValue: true);

  /// Build-level kill switch (`--dart-define=MODU_PLUGINS=false`).
  static bool get isEnabled => _compiledIn;

  List<PluginRecord> _plugins = const [];
  final Map<String, PluginManifest> _manifests = {};
  final Map<String, String> _manifestTexts = {};
  String _appVersion = '';
  bool _initialized = false;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  // Serialize package/state transactions, including disabling during an import.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    return previous.then((_) => action()).whenComplete(done.complete);
  }

  List<PluginRecord> get plugins => List.unmodifiable(_plugins);

  PluginPaths get paths => _paths;

  String get appVersion => _appVersion;

  bool get isInitialized => _initialized;

  PluginRecord? byId(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  /// Parsed manifest kept in memory so enable/disable and the detail page do
  /// not need file-system access (and keep working with a fake clock in tests).
  PluginManifest? manifestFor(String id) => _manifests[id];

  String? manifestTextFor(String id) => _manifestTexts[id];

  /// First 8 KB of the installed package README, resolved lazily so startup
  /// does not read files it may never show.
  Future<String?> readmeFor(String id) => _readReadme(_paths.pluginDir(id));

  /// Loads the registry and reconciles it with the package directory.
  ///
  /// Safe to call more than once (Android deferred start, macOS migration).
  Future<void> initialize() => _exclusive(_initialize);

  Future<void> _initialize() async {
    if (_disposed) return;
    await _initializeOnce();
  }

  Future<void> _initializeOnce() async {
    if (!_compiledIn || !Prefs().experimentalPluginsEnabled) {
      await _suspendPlugins();
      notifyListeners();
      return;
    }
    await _paths.ensureCreated();
    await _paths.cleanStale();
    try {
      _appVersion = await _appVersionResolver();
    } catch (_) {
      _appVersion = '';
    }

    final loaded = Prefs().pluginState;
    final next = <PluginRecord>[];
    var changed = false;
    _manifests.clear();
    _manifestTexts.clear();
    for (final record in loaded.plugins) {
      final result = await _reconcile(record);
      next.add(result.record);
      changed = changed || result.changed;
    }
    _plugins = next;
    _initialized = true;
    if (changed) {
      try {
        await Prefs()
            .savePluginState(PluginState(plugins: List.unmodifiable(next)));
      } catch (error) {
        AnxLog.warning('Could not persist reconciled plugin state: $error');
      }
    }
    notifyListeners();
  }

  Future<_Reconciled> _reconcile(PluginRecord record) async {
    final directory = _paths.pluginDir(record.id);
    if (!await directory.exists()) {
      _manifests.remove(record.id);
      _manifestTexts.remove(record.id);
      await _removeContributions(record);
      return _Reconciled(
        record: record.copyWith(
            status: PluginStatus.missing,
            applied: const [],
            clearLastError: true),
        changed: true,
      );
    }

    _LoadedManifest? loadedManifest;
    try {
      await trust.verify(directory, record.id, record.version);
      loadedManifest = await _readManifest(record.id);
      if (loadedManifest != null) {
        _ensureSupportedCapabilities(loadedManifest.manifest);
      }
    } catch (error) {
      _manifests.remove(record.id);
      _manifestTexts.remove(record.id);
      await _removeContributions(record);
      return _Reconciled(
        record: record.copyWith(
            status: PluginStatus.broken,
            applied: const [],
            lastError: describeError(error)),
        changed: true,
      );
    }
    if (loadedManifest == null ||
        loadedManifest.manifest.id != record.id ||
        loadedManifest.manifest.version != record.version) {
      await _removeContributions(record);
      return _Reconciled(
        record: record.copyWith(
            status: PluginStatus.broken,
            applied: const [],
            lastError: 'Installed files no longer match the registry entry.'),
        changed: true,
      );
    }
    final manifest = loadedManifest.manifest;
    _manifests[record.id] = manifest;
    _manifestTexts[record.id] = loadedManifest.text;

    if (record.status == PluginStatus.missing ||
        record.status == PluginStatus.broken) {
      // The package came back (for example the storage was remounted). Keep it
      // disabled until the user enables it again.
      return _Reconciled(
          record: record.copyWith(
              status: PluginStatus.disabled, clearLastError: true),
          changed: true);
    }

    if (record.status == PluginStatus.enabled) {
      // Each handler answers for its own kind (P2). runtimeOnly kinds live in
      // an in-memory registry, so they are rebuilt on every start rather than
      // probed. Declarative kinds keep P1's "rebuild only when every entry is
      // gone" rule, so one prompt the user deleted is not resurrected.
      final hasRuntimeOnly = record.applied.any((entry) =>
          _contributions.registry.forKind(entry.kind)?.runtimeOnly ?? false);
      final lost = hasRuntimeOnly ||
          record.applied.isEmpty ||
          record.applied.every((entry) {
            final handler = _contributions.registry.forKind(entry.kind);
            // A kind this build does not know cannot be judged; leave it alone.
            return handler != null && !handler.isApplied(entry);
          });
      if (lost) {
        try {
          final applied = await _contributions.apply(manifest);
          return _Reconciled(
              record: record.copyWith(applied: applied), changed: true);
        } catch (error) {
          return _Reconciled(
              record: record.copyWith(
                  status: PluginStatus.broken,
                  lastError: describeError(error),
                  applied: const []),
              changed: true);
        }
      }
    }

    return _Reconciled(record: record, changed: false);
  }

  Future<_LoadedManifest?> _readManifest(String id) async {
    final file = _paths.manifestFile(id);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length > PluginLimits.maxManifestBytes) {
      throw const PluginInstallError(
          PluginErrorCode.manifestTooLarge, 'manifest.json is too large.');
    }
    final text = _decodeUtf8(bytes);
    return _LoadedManifest(PluginManifest.parse(text), text);
  }

  /// Inspects [package] without installing it.
  ///
  /// Runs the same package, trust and compatibility checks as [install] so the
  /// confirmation page can show what would happen; the staging directory is
  /// always removed and no preference is written.
  Future<PluginPreview> preview(File package,
          {bool allowSameVersion = false}) =>
      _exclusive(() => _preview(package, allowSameVersion: allowSameVersion));

  Future<PluginPreview> _preview(File package,
      {required bool allowSameVersion}) async {
    _ensureUsable();
    if (!_initialized) await _initialize();
    final pkg = await _reader.read(package);
    try {
      final manifest = pkg.manifest;
      _ensureSupportedCapabilities(manifest);
      await trust.verify(pkg.staging, manifest.id, manifest.version);
      if (_appVersion.isNotEmpty) manifest.ensureCompatibleWith(_appVersion);
      final existing = byId(manifest.id);
      _checkVersionConflict(existing, manifest,
          allowSameVersion: allowSameVersion);
      return PluginPreview(
        manifest: manifest,
        manifestText: pkg.manifestText,
        sha256: pkg.sha256,
        compressedBytes: pkg.compressedBytes,
        readme: await _readReadme(pkg.staging),
        warnings: List.unmodifiable(pkg.warnings),
        installedVersion: existing?.version,
      );
    } finally {
      await pkg.dispose();
    }
  }

  /// Shared by install and preview so both reject the same version states.
  void _checkVersionConflict(
    PluginRecord? existing,
    PluginManifest manifest, {
    required bool allowSameVersion,
  }) {
    if (existing == null) return;
    final comparison = Version.parse(manifest.version)
        .compareTo(Version.parse(existing.version));
    final repairable = existing.status == PluginStatus.broken ||
        existing.status == PluginStatus.missing;
    if (comparison < 0) {
      throw PluginInstallError(PluginErrorCode.downgradeNotAllowed,
          'A newer version (${existing.version}) is already installed. Uninstall it first.');
    }
    if (comparison == 0 && !repairable && !allowSameVersion) {
      throw PluginInstallError(PluginErrorCode.alreadyInstalled,
          'Version ${manifest.version} is already installed.');
    }
  }

  /// The details page shows the first 8 KB of the README as plain text.
  Future<String?> _readReadme(Directory directory) async {
    final file = File(p.join(directory.path, 'README.md'));
    try {
      if (!await file.exists()) return null;
      // Four bytes per character covers every UTF-8 scalar value; a sequence
      // cut at the limit is decoded with replacement instead of throwing.
      final bytes = await file.readAsBytes();
      final text = const Utf8Decoder(allowMalformed: true)
          .convert(bytes.take(PluginPreview.maxReadmeChars * 4).toList());
      final runes = text.runes.toList();
      if (runes.length <= PluginPreview.maxReadmeChars) return text;
      return '${String.fromCharCodes(runes.take(PluginPreview.maxReadmeChars))}…';
    } catch (error) {
      AnxLog.warning('Could not read plugin README: $error');
      return null;
    }
  }

  Future<PluginInstallResult> install(File package,
          {bool allowSameVersion = false, String? expectedSha256}) =>
      _exclusive(() => _install(package,
          allowSameVersion: allowSameVersion, expectedSha256: expectedSha256));

  void _ensureSupportedCapabilities(PluginManifest manifest) {
    // Transport helpers are not wired to consent, secrets or lookup UI yet.
    if (manifest.capabilities.contains('net:http')) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Network plugins are not available in this version.');
    }
  }

  Future<PluginInstallResult> _install(File package,
      {bool allowSameVersion = false, String? expectedSha256}) async {
    _ensureUsable();
    if (!_initialized) await _initialize();
    final pkg = await _reader.read(package);
    try {
      if (expectedSha256 != null && pkg.sha256 != expectedSha256) {
        throw const PluginInstallError(PluginErrorCode.invalidPackage,
            'Package changed after preview. Select it again to review it.');
      }
      final manifest = pkg.manifest;
      _ensureSupportedCapabilities(manifest);
      await trust.verify(pkg.staging, manifest.id, manifest.version);
      if (_appVersion.isNotEmpty) manifest.ensureCompatibleWith(_appVersion);

      final existing = byId(manifest.id);
      _checkVersionConflict(existing, manifest,
          allowSameVersion: allowSameVersion);

      final promptsSnapshot = Prefs().userPrompts;
      final toolbarSnapshot = Prefs().selectionToolbar;
      List<AppliedContribution> applied = const [];
      Directory? previousFiles;
      var filesPlaced = false;
      try {
        // Remove owned values first: edited values become ordinary user entries,
        // and retired actions release their slots before validating the upgrade.
        if (existing != null) await _contributions.remove(existing.applied);
        applied = await _contributions.apply(manifest);
        previousFiles = await _placeFiles(pkg);
        filesPlaced = true;

        final record = PluginRecord(
          id: manifest.id,
          version: manifest.version,
          name: manifest.name,
          license: manifest.license,
          author: manifest.author?.name,
          installedAt: DateTime.now(),
          sha256: pkg.sha256,
          status: PluginStatus.enabled,
          applied: List.unmodifiable(applied),
        );
        await Prefs().savePluginState(Prefs().pluginState.upsert(record));
        _manifests[manifest.id] = manifest;
        _manifestTexts[manifest.id] = pkg.manifestText;
        _upsertMemory(record);
        notifyListeners();
        if (previousFiles != null) await _deleteQuietly(previousFiles);
        return PluginInstallResult(
            record: record, warnings: List.unmodifiable(pkg.warnings));
      } catch (error) {
        Prefs().userPrompts = promptsSnapshot;
        try {
          await Prefs().saveSelectionToolbar(toolbarSnapshot);
        } catch (_) {
          // The original failure is more useful; the snapshot is retried on
          // the next plugin mutation.
        }
        if (filesPlaced) await _rollbackFiles(manifest.id, previousFiles);
        rethrow;
      }
    } finally {
      await pkg.dispose();
    }
  }

  Future<void> enable(String id) => _exclusive(() => _enable(id));

  Future<void> _enable(String id) async {
    _ensureUsable();
    final record = _require(id);
    if (!record.isUsable) {
      throw PluginInstallError(PluginErrorCode.pluginUnavailable,
          'This plugin is ${record.status.name}; reinstall it first.');
    }
    if (record.status == PluginStatus.enabled) return;

    await trust.verify(_paths.pluginDir(id), id, record.version);

    final manifest = _manifests[id];
    if (manifest == null) {
      throw PluginInstallError(
          PluginErrorCode.pluginUnavailable, 'Plugin manifest is unavailable.');
    }
    _ensureSupportedCapabilities(manifest);
    manifest.ensureCompatibleWith(_appVersion);
    final promptsSnapshot = Prefs().userPrompts;
    final toolbarSnapshot = Prefs().selectionToolbar;
    try {
      final applied = await _contributions.apply(manifest);
      final newIds = applied.map((entry) => entry.id).toSet();
      final stale =
          record.applied.where((entry) => !newIds.contains(entry.id)).toList();
      await _contributions.remove(stale);
      final updated = record.copyWith(
        status: PluginStatus.enabled,
        applied: List.unmodifiable(applied),
        clearLastError: true,
      );
      await Prefs().savePluginState(Prefs().pluginState.upsert(updated));
      _upsertMemory(updated);
      notifyListeners();
    } catch (_) {
      Prefs().userPrompts = promptsSnapshot;
      try {
        await Prefs().saveSelectionToolbar(toolbarSnapshot);
      } catch (_) {
        // Best effort; the enable operation already failed.
      }
      rethrow;
    }
  }

  Future<void> disable(String id) => _exclusive(() => _disable(id));

  Future<void> _disable(String id) async {
    _ensureUsable();
    final record = _require(id);
    if (!record.isUsable) {
      throw PluginInstallError(PluginErrorCode.pluginUnavailable,
          'This plugin is ${record.status.name}; uninstall it instead.');
    }
    if (record.status == PluginStatus.disabled) return;
    final prompts = Prefs().userPrompts;
    final toolbar = Prefs().selectionToolbar;
    try {
      await _contributions.remove(record.applied);
      final updated =
          record.copyWith(status: PluginStatus.disabled, applied: const []);
      await Prefs().savePluginState(Prefs().pluginState.upsert(updated));
      _upsertMemory(updated);
    } catch (_) {
      Prefs().userPrompts = prompts;
      await Prefs().saveSelectionToolbar(toolbar);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> uninstall(String id) => _exclusive(() => _uninstall(id));

  Future<void> _uninstall(String id) async {
    _ensureUsable();
    final record = _require(id);
    final prompts = Prefs().userPrompts;
    final toolbar = Prefs().selectionToolbar;
    try {
      await _contributions.remove(record.applied);
      await Prefs().removePluginData(id);
    } catch (_) {
      Prefs().userPrompts = prompts;
      await Prefs().saveSelectionToolbar(toolbar);
      rethrow;
    }
    _plugins = _plugins.where((plugin) => plugin.id != id).toList();
    _manifests.remove(id);
    _manifestTexts.remove(id);
    notifyListeners();

    // File deletion is best-effort: the registry entry is already gone, so a
    // locked directory cannot leave the plugin half-installed.
    try {
      final directory = _paths.pluginDir(id);
      if (await directory.exists()) {
        final trashed = await _moveToTrash(directory, id);
        await _deleteQuietly(trashed);
      }
    } catch (error) {
      AnxLog.warning('Could not delete files of $id: ${describeError(error)}');
    }
  }

  PluginRecord _require(String id) {
    final record = byId(id);
    if (record == null) {
      throw PluginInstallError(
          PluginErrorCode.notInstalled, 'Plugin $id is not installed.');
    }
    return record;
  }

  void _ensureUsable() {
    if (!_compiledIn || !Prefs().experimentalPluginsEnabled) {
      throw PluginInstallError(PluginErrorCode.internal,
          'Enable plugins in Experimental features first.');
    }
    if (_disposed) {
      throw PluginInstallError(
          PluginErrorCode.internal, 'Plugin host is disposed.');
    }
  }

  /// Consent is local to this device and intentionally excluded from backups.
  Future<void> setExperimentalEnabled(bool value) =>
      _exclusive(() => _setExperimentalEnabled(value));

  Future<void> _setExperimentalEnabled(bool value) async {
    if (_disposed || !_compiledIn) {
      throw PluginInstallError(
          PluginErrorCode.internal, 'Plugins are unavailable.');
    }
    if (value) {
      await Prefs().saveExperimentalPluginsEnabled(true);
      try {
        await _initialize();
      } catch (_) {
        await Prefs().saveExperimentalPluginsEnabled(false);
        rethrow;
      }
    } else {
      await _suspendPlugins();
      await Prefs().saveExperimentalPluginsEnabled(false);
    }
    notifyListeners();
  }

  Future<void> _suspendPlugins() async {
    final state = Prefs().pluginState;
    final prompts = Prefs().userPrompts;
    final toolbar = Prefs().selectionToolbar;
    try {
      final next = <PluginRecord>[];
      for (final record in state.plugins) {
        await _contributions.remove(record.applied);
        next.add(record.copyWith(
          status: record.status == PluginStatus.enabled
              ? PluginStatus.disabled
              : record.status,
          applied: const [],
        ));
      }
      if (state.plugins.isNotEmpty) {
        await Prefs().savePluginState(PluginState(plugins: next));
      }
      _plugins = next;
      _initialized = false;
      _manifests.clear();
      _manifestTexts.clear();
    } catch (_) {
      Prefs().userPrompts = prompts;
      await Prefs().saveSelectionToolbar(toolbar);
      rethrow;
    }
  }

  void _upsertMemory(PluginRecord record) {
    final next = <PluginRecord>[];
    var replaced = false;
    for (final plugin in _plugins) {
      if (plugin.id == record.id) {
        next.add(record);
        replaced = true;
      } else {
        next.add(plugin);
      }
    }
    if (!replaced) next.add(record);
    _plugins = next;
  }

  Future<void> _removeContributions(PluginRecord record) async {
    await _contributions.remove(record.applied);
  }

  /// Moves the staged package into place, returning the previous directory if
  /// this was a replacement (it is deleted after the state is committed).
  Future<Directory?> _placeFiles(PluginPackage pkg) async {
    final id = pkg.manifest.id;
    final target = _paths.pluginDir(id);
    Directory? previous;
    if (await target.exists()) {
      previous = await _moveToTrash(target, id);
    }
    try {
      await pkg.staging.rename(target.path);
      return previous;
    } catch (_) {
      if (previous != null) {
        try {
          await previous.rename(target.path);
        } catch (_) {
          // Best effort; the package stays in trash and the record is rolled back.
        }
      }
      rethrow;
    }
  }

  Future<void> _rollbackFiles(String id, Directory? previousFiles) async {
    final target = _paths.pluginDir(id);
    await _deleteQuietly(target);
    if (previousFiles != null) {
      try {
        await previousFiles.rename(target.path);
      } catch (_) {
        // Nothing else can be done here; uninstall still works on the record.
      }
    }
  }

  Future<Directory> _moveToTrash(Directory directory, String id) async {
    final destination = Directory(p.join(
        _paths.trash.path, '$id-${DateTime.now().microsecondsSinceEpoch}'));
    await _paths.trash.create(recursive: true);
    await directory.rename(destination.path);
    return destination;
  }

  Future<void> _deleteQuietly(Directory? directory) async {
    if (directory == null) return;
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      // The startup sweep removes stale trash entries.
    }
  }

  static String _decodeUtf8(List<int> bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      throw const PluginInstallError(
          PluginErrorCode.invalidManifest, 'manifest.json must be UTF-8.');
    }
  }

  /// Truncated, prompt-free error text suitable for the diagnostics UI.
  static String describeError(Object error) {
    final message = error is PluginInstallError
        ? '${error.code.name}: ${error.message}'
        : error.toString();
    return message.length <= 500 ? message : '${message.substring(0, 500)}…';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

class _Reconciled {
  const _Reconciled({required this.record, required this.changed});

  final PluginRecord record;
  final bool changed;
}

class _LoadedManifest {
  const _LoadedManifest(this.manifest, this.text);

  final PluginManifest manifest;
  final String text;
}
