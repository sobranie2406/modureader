import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_permissions.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/main.dart' show navigatorKey;
import 'package:modu_reader/service/private_library.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/plugins/plugin_contributions.dart';
import 'package:modu_reader/service/plugins/plugin_package.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:modu_reader/service/plugins/plugin_config.dart';
import 'package:modu_reader/service/plugins/plugin_permissions.dart';
import 'package:modu_reader/service/plugins/plugin_private_import_policy.dart';
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
    this.development = false,
    PluginPackageReader? reader,
    PluginContributions? contributions,
    PluginTrust? trust,
    Future<String> Function()? appVersionResolver,
  })  : trust = trust ?? PluginTrust(),
        _paths = paths ?? PluginPaths(),
        _appVersionResolver = appVersionResolver ?? getAppVersion {
    _reader = reader ?? PluginPackageReader(paths: _paths);
    this.trust.bindCatalogDirectory(
        Directory(p.join(_paths.root.path, '.catalog-proofs')));
    _contributions = contributions ?? PluginContributions.standard();
  }

  static PluginHost? _instance;

  static PluginHost get instance => _instance ??= PluginHost();

  final bool development;
  PluginHost? _peer;
  Future<void> Function()? _closeDeveloperSession;
  final _reservedIds = <String>{};
  PluginState _developmentState = const PluginState();
  final _developmentConfig = <String, Map<String, dynamic>>{};
  Future<void> _configWrites = Future.value();
  final _runtimes = <PluginScriptRuntime>{};
  PluginScriptRuntime? _developmentRuntime;
  bool _sessionOpen = true;
  static PluginHost? _activeDeveloper;
  static bool get hasDevelopmentSession => _activeDeveloper != null;

  static PluginHost executionHostFor(String id) =>
      _activeDeveloper?.byId(id) != null ? _activeDeveloper! : instance;

  static PluginScriptRuntime runtimeFor(String id) {
    final owner = executionHostFor(id);
    return owner.development
        ? owner._developmentRuntime ??= PluginScriptRuntime(host: owner)
        : PluginScriptRuntime.instance;
  }

  void registerRuntime(PluginScriptRuntime runtime) {
    _runtimes.add(runtime);
    if (development) _developmentRuntime = runtime;
  }

  void unregisterRuntime(PluginScriptRuntime runtime) =>
      _runtimes.remove(runtime);

  static void attachDevelopment(PluginHost official, PluginHost developer,
      {Future<void> Function()? onGlobalDisable}) {
    if (!developer.development ||
        official.development ||
        official._peer != null ||
        _activeDeveloper != null) {
      throw StateError('A development session is already active.');
    }
    official._peer = developer;
    official._closeDeveloperSession = onGlobalDisable;
    developer._peer = official;
    _activeDeveloper = developer;
    official.notifyListeners();
  }

  static void detachDevelopment(PluginHost developer) {
    PrivateLibrary.instance.clearOptionsOverlay(developer);
    final official = developer._peer;
    developer._peer = null;
    if (identical(official?._peer, developer)) {
      official!._peer = null;
      official._closeDeveloperSession = null;
    }
    if (identical(_activeDeveloper, developer)) _activeDeveloper = null;
    PrivateLibrary.instance
        .setPluginActive(official?._hasPrivateProvider ?? false);
    official?.notifyListeners();
  }

  bool get _hasPrivateProvider =>
      !_disposed &&
      _sessionOpen &&
      _compiledIn &&
      Prefs().experimentalPluginsEnabled &&
      _plugins.any((record) =>
          record.status == PluginStatus.enabled &&
          (_manifests[record.id]
                  ?.capabilities
                  .contains(kLibraryPrivateCapability) ??
              false));

  PluginState get _state =>
      development ? _developmentState : Prefs().pluginState;
  Future<void> _saveState(PluginState state) async {
    if (development) {
      _developmentState = state;
    } else {
      await Prefs().savePluginState(state);
    }
  }

  Map<String, dynamic> configFor(String id) {
    if (development && (_disposed || !_sessionOpen)) return {};
    final manifest = manifestFor(id);
    if (manifest == null) return development ? {} : Prefs().pluginConfig(id);
    final saved = development
        ? Map<String, dynamic>.of(_developmentConfig[id] ?? const {})
        : PluginConfig.forStorage(
            manifest, Prefs().pluginConfig(id), PluginSettingStorage.sync);
    if (!development) {
      final raw = Prefs().prefs.get(PluginConfig.deviceKeyFor(id));
      try {
        if (raw != null) {
          saved.addAll(PluginConfig.forStorage(
              manifest, PluginConfig.decode(raw), PluginSettingStorage.device));
        }
      } on FormatException {
        // A broken local override falls back to package defaults.
      }
    }
    final native = development
        ? PrivateLibrary.instance.policyOptionsFor(this)
        : PrivateLibrary.instance.storedPolicyOptions;
    for (final spec in manifest.settings) {
      if (spec.binding != null) {
        saved[spec.key] = native[spec.binding!.split('.').last]!;
      }
    }
    return PluginConfig.sanitize(manifest, saved);
  }

  Future<void> saveConfig(String id, Map<String, dynamic> values) {
    final manifest = manifestFor(id);
    final session = PrivateLibrary.instance.authenticationSession;
    final snapshot = Map<String, dynamic>.of(values);
    final operation = _configWrites.then((_) async {
      bool current() =>
          !_disposed &&
          _sessionOpen &&
          identical(manifestFor(id), manifest) &&
          byId(id)?.isUsable == true &&
          (!development || Prefs().experimentalPluginsEnabled);
      if (manifest == null || !current()) {
        throw StateError('Plugin settings are unavailable.');
      }
      PluginConfig.validate(id, snapshot, manifest: manifest);
      final native = development
          ? PrivateLibrary.instance.policyOptionsFor(this)
          : PrivateLibrary.instance.storedPolicyOptions;
      final bindings = <String, bool>{
        for (final spec in manifest.settings)
          if (spec.binding != null &&
              snapshot[spec.key] is bool &&
              snapshot[spec.key] != native[spec.binding!.split('.').last])
            spec.binding!.split('.').last: snapshot[spec.key] as bool,
      };
      if (bindings.isNotEmpty) {
        bool authorized() =>
            current() &&
            isScriptRunnable(id) &&
            PrivateLibrary.instance.isAuthenticationCurrent(session);
        if (!authorized()) throw StateError('Private library locked.');
        if (development) {
          PrivateLibrary.instance.setOptionsOverlay(this,
              {...PrivateLibrary.instance.policyOptionsFor(this), ...bindings},
              isCurrent: authorized);
        } else {
          await PrivateLibrary.instance.setOptions(
              privateOnly: bindings['privateOnly'],
              autoImport: bindings['autoImport'],
              lockAfterHide: bindings['lockAfterHide'],
              isCurrent: authorized);
        }
      }
      if (!current()) throw StateError('Plugin settings changed.');
      if (development) {
        _developmentConfig[id] = PluginConfig.sanitize(manifest, snapshot);
      } else {
        final device = PluginConfig.forStorage(
            manifest, snapshot, PluginSettingStorage.device);
        if (!await Prefs()
            .prefs
            .setString(PluginConfig.deviceKeyFor(id), jsonEncode(device))) {
          throw StateError('Could not save device plugin settings.');
        }
        if (!current()) throw StateError('Plugin settings changed.');
        await Prefs().savePluginConfig(
            id,
            PluginConfig.forStorage(
                manifest, snapshot, PluginSettingStorage.sync));
      }
      notifyListeners();
    });
    _configWrites = operation.catchError((_) {});
    return operation;
  }

  Future<void> _removeData(String id) async {
    if (development) {
      if (_manifests[id]?.capabilities.contains(kLibraryPrivateCapability) ??
          false) {
        PrivateLibrary.instance.clearOptionsOverlay(this);
      }
      _developmentConfig.remove(id);
      await _saveState(_state.remove(id));
    } else {
      await Prefs().removePluginData(id);
      await Prefs().prefs.remove(PluginConfig.deviceKeyFor(id));
      await _revokeAllPermissions(id);
      await Prefs().clearPluginPermissionSeeded(id);
    }
    // Plugin data is inside the plugin's own directory tree, so uninstalling
    // removes it. If it cannot be deleted the package is still gone.
    try {
      final data = _paths.dataDir(id);
      if (await data.exists()) await data.delete(recursive: true);
    } catch (error) {
      if (!development) {
        AnxLog.warning('Could not delete plugin data of $id: '
            '${describeError(error)}');
      }
    }
  }

  void _reserveIdentity(String id) {
    if (_peer?.byId(id) != null ||
        _peer?._reservedIds.contains(id) == true ||
        (development && _peer?._state.byId(id) != null)) {
      throw const PluginInstallError(PluginErrorCode.invalidPackage,
          'An official or development plugin with this ID already exists. Remove it from the other list first.');
    }
    _reservedIds.add(id);
  }

  Future<void> closeDevelopment({bool skipAuthorization = false}) =>
      _exclusive(() async {
        if (!development) throw StateError('Not a development host.');
        if (!skipAuthorization) await _authorizePrivateRemoval(null);
        await _suspendPlugins();
        _sessionOpen = false;
        PrivateLibrary.instance.clearOptionsOverlay(this);
        _developmentConfig.clear();
        _developmentState = const PluginState();
        _plugins = const [];
        notifyListeners();
      });

  final PluginPaths _paths;
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
  bool _scriptsMutating = false;

  bool isScriptRunnable(String id) =>
      !_disposed &&
      _sessionOpen &&
      !_scriptsMutating &&
      _compiledIn &&
      Prefs().experimentalPluginsEnabled &&
      byId(id)?.status == PluginStatus.enabled;

  // ---- Runtime permissions -------------------------------------------------
  //
  // Grants are device-local and never leave it. A capability that is not in
  // this map is denied, including one a package update just added.

  /// Every grant held on this device, for every plugin.
  Map<String, Set<String>> get permissionGrants =>
      development ? const {} : Prefs().pluginPermissions;

  /// Capabilities [id] may use right now: declared, runtime-tier and granted.
  Set<String> grantedPermissions(String id) {
    if (development) return _developmentGrants(id);
    final manifest = manifestFor(id);
    if (manifest == null) return const {};
    final store = Prefs().pluginPermissions;
    return {
      for (final capability in PluginPermissions.requestedRuntime(manifest))
        if (PluginPermissions.allows(store, id, capability)) capability,
    };
  }

  /// True when the plugin declares [capability] and it is runtime-tier.
  bool requestsPermission(String id, String capability) {
    if (!isRuntimePermission(capability)) return true;
    final manifest = manifestFor(id);
    if (manifest == null) return false;
    return manifest.capabilities.contains(capability);
  }

  /// True when [id] may use [capability] right now.
  ///
  /// Install-tier capabilities are answered from the manifest; runtime-tier
  /// ones from the device grant map, so the check is the single place a new
  /// host API must consult.
  bool hasPermission(String id, String capability) {
    if (!isRuntimePermission(capability)) {
      return manifestFor(id)?.capabilities.contains(capability) ?? false;
    }
    if (development) return _developmentGrants(id).contains(capability);
    return PluginPermissions.allows(
        Prefs().pluginPermissions, id, capability);
  }

  /// Turns one runtime capability on or off.
  ///
  /// Refuses a capability the package does not declare: a stale grant would
  /// silently re-authorise it if a later version re-added the token.
  Future<void> setPermission(String id, String capability, bool granted) =>
      _exclusive(() => _setPermission(id, capability, granted));

  Future<void> _setPermission(
      String id, String capability, bool granted) async {
    _ensureUsable();
    final manifest = manifestFor(id);
    if (manifest == null) {
      throw PluginInstallError(
          PluginErrorCode.notInstalled, 'Plugin $id is not installed.');
    }
    if (!isRuntimePermission(capability)) {
      throw const PluginInstallError(PluginErrorCode.permissionNotRuntime,
          'This permission is granted by installing the package.');
    }
    if (!manifest.capabilities.contains(capability)) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'The package does not declare this permission.');
    }
    if (development) {
      final next = Set<String>.from(
          _developmentPermissionGrants[id] ?? const <String>{});
      if (granted) {
        next.add(capability);
      } else {
        next.remove(capability);
      }
      if (next.isEmpty) {
        _developmentPermissionGrants.remove(id);
      } else {
        _developmentPermissionGrants[id] = next;
      }
      notifyListeners();
      return;
    }
    // A user decision is recorded even when it is "deny everything", so the
    // grandfather seeding cannot hand the capability back on the next start.
    await Prefs().markPluginPermissionSeeded(id);
    final store = Map<String, Set<String>>.from(Prefs().pluginPermissions);
    final next = Set<String>.from(store[id] ?? const <String>{});
    if (granted) {
      next.add(capability);
    } else {
      next.remove(capability);
    }
    if (next.isEmpty) {
      store.remove(id);
    } else {
      store[id] = next;
    }
    await Prefs().savePluginPermissions(store);
    // A revoked capability must stop work already in flight.
    if (!granted) {
      for (final runtime in _runtimes) {
        runtime.cancelPlugin(id);
      }
    }
    notifyListeners();
  }

  /// Applies grants **without disturbing work that is already running**.
  ///
  /// [setPermission] is serialised with package mutations, which cancels every
  /// running script. That is correct for a settings-page toggle, but it is
  /// exactly wrong for consent a plugin asks for mid-run: the cancellation
  /// would kill the very job that just received the permission, so the plugin
  /// could never proceed. Granting therefore uses its own queue. Revoking still
  /// goes through [setPermission] and still stops running work.
  Future<Set<String>> grantPermissions(
      String id, Iterable<String> capabilities) {
    final wanted = List<String>.of(capabilities);
    final operation = _permissionWrites.then((_) async {
      for (final capability in wanted) {
        await _setPermission(id, capability, true);
      }
      return grantedPermissions(id);
    });
    _permissionWrites = operation.then<void>((_) {},
        onError: (Object _, StackTrace __) {});
    return operation;
  }

  /// Queue for permission writes that must not tear down running scripts.
  Future<void> _permissionWrites = Future.value();

  /// Drops every runtime grant a plugin holds.
  Future<void> revokeAllPermissions(String id) =>
      _exclusive(() => _revokeAllPermissions(id));

  Future<void> _revokeAllPermissions(String id) async {
    if (development) {
      _developmentPermissionGrants.remove(id);
      notifyListeners();
      return;
    }
    final store = Map<String, Set<String>>.from(Prefs().pluginPermissions);
    if (store.remove(id) == null) return;
    await Prefs().savePluginPermissions(store);
    for (final runtime in _runtimes) {
      runtime.cancelPlugin(id);
    }
    notifyListeners();
  }

  final _developmentPermissionGrants = <String, Set<String>>{};

  Set<String> _developmentGrants(String id) =>
      Set.unmodifiable(_developmentPermissionGrants[id] ?? const <String>{});

  /// Gives an **upgraded** package the grants it already implied before manual
  /// permission control existed, so the upgrade is not a regression.
  ///
  /// A fresh install never seeds: its grants must all be requested on the
  /// permission screen. The seeded marker distinguishes the two cases, because
  /// "no grants stored" is also what "the user revoked everything" looks like.
  Future<void> _seedLegacyPermissions(PluginManifest manifest,
      {required bool wasInstalled}) async {
    if (!wasInstalled) {
      if (!development) {
        await Prefs().markPluginPermissionSeeded(manifest.id);
      }
      return;
    }
    if (!development && Prefs().pluginPermissionSeeded.contains(manifest.id)) {
      return;
    }
    final legacy = PluginPermissions.legacyGrants(manifest);
    if (development) {
      if (legacy.isNotEmpty) _developmentPermissionGrants[manifest.id] = legacy;
      return;
    }
    await Prefs().markPluginPermissionSeeded(manifest.id);
    if (legacy.isEmpty) return;
    final store = Map<String, Set<String>>.from(Prefs().pluginPermissions);
    // Never overwrite a decision the user already made under the new system.
    if (store.containsKey(manifest.id)) return;
    store[manifest.id] = legacy;
    await Prefs().savePluginPermissions(store);
  }

  @override
  void notifyListeners() {
    if (identical(this, _instance) || _peer != null) {
      PrivateLibrary.instance.setPluginActive(
          _hasPrivateProvider || (_peer?._hasPrivateProvider ?? false));
    }
    super.notifyListeners();
  }

  // Serialize package/state transactions, including disabling during an import.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final previous = _pending;
    final done = Completer<void>();
    _pending = done.future;
    return previous.then((_) async {
      _scriptsMutating = true;
      for (final runtime in _runtimes.toList()) {
        runtime.cancelAll();
      }
      if (identical(this, _instance)) PluginScriptRuntime.cancelExisting();
      try {
        return await action();
      } finally {
        _scriptsMutating = false;
      }
    }).whenComplete(done.complete);
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
    PluginPrivateImportPolicy.attach(PrivateLibrary.instance);
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

    final loaded = _state;
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
        await _saveState(PluginState(plugins: List.unmodifiable(next)));
      } catch (error) {
        AnxLog.warning('Could not persist reconciled plugin state: $error');
      }
    }
    notifyListeners();
  }

  Future<_Reconciled> _reconcile(PluginRecord record) async {
    if (_peer?.byId(record.id) != null ||
        _peer?._reservedIds.contains(record.id) == true) {
      // Settings restoration must not replace another scope's live registry.
      return _Reconciled(
          record: record.copyWith(
              status: PluginStatus.disabled,
              applied: const [],
              lastError: 'This ID is active in another plugin scope.'),
          changed: true);
    }
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
      final persistent = record.applied
          .where((entry) =>
              !(_contributions.registry.forKind(entry.kind)?.runtimeOnly ??
                  false))
          .toList();
      final lost = record.applied.isEmpty ||
          (persistent.isNotEmpty &&
              persistent.every((entry) {
                final handler = _contributions.registry.forKind(entry.kind);
                // A kind this build does not know cannot be judged; leave it alone.
                return handler != null && !handler.isApplied(entry);
              }));
      if (lost || hasRuntimeOnly) {
        try {
          final applied = lost
              ? await _contributions.apply(manifest)
              : [
                  ...persistent,
                  for (final kind in _contributions.registry.kinds)
                    if (_contributions.registry.forKind(kind)!.runtimeOnly &&
                        manifest.contributions
                            .any((entry) => entry.kind == kind))
                      ...await _contributions.registry.forKind(kind)!.apply(
                          manifest,
                          manifest.contributions
                              .where((entry) => entry.kind == kind)
                              .toList()),
                ];
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
      _ensureUsable();
      final manifest = pkg.manifest;
      _reserveIdentity(manifest.id);
      _ensureSupportedCapabilities(manifest);
      if (!development) {
        await trust.verify(pkg.staging, manifest.id, manifest.version);
      }
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
      _reservedIds.remove(pkg.manifest.id);
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
      if (!development) AnxLog.warning('Could not read plugin README: $error');
      return null;
    }
  }

  Future<PluginInstallResult> install(File package,
          {bool allowSameVersion = false, String? expectedSha256}) =>
      _exclusive(() => _install(package,
          allowSameVersion: allowSameVersion, expectedSha256: expectedSha256));

  void _ensureSupportedCapabilities(PluginManifest manifest) {
    if (development &&
        (manifest.contributions.isEmpty ||
            manifest.contributions.any((c) =>
                c is! ScriptActionContribution &&
                c is! BookActionContribution))) {
      throw const PluginInstallError(PluginErrorCode.capabilityUnavailable,
          'Development mode supports scriptAction and bookAction only; aiSkill and selectionAction are not supported.');
    }
    // Script networking uses the bounded host proxy; dictionary contributions
    // still need their separate lookup integration.
    if (manifest.capabilities.contains('net:http') &&
        (!manifest.contributions.any((c) => c is ScriptActionContribution) ||
            manifest.contributions
                .any((c) => c is DictionarySourceContribution))) {
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
      _ensureUsable();
      if (expectedSha256 != null && pkg.sha256 != expectedSha256) {
        throw const PluginInstallError(PluginErrorCode.invalidPackage,
            'Package changed after preview. Select it again to review it.');
      }
      final manifest = pkg.manifest;
      _reserveIdentity(manifest.id);
      _ensureSupportedCapabilities(manifest);
      await trust.verify(pkg.staging, manifest.id, manifest.version);
      _ensureUsable();
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
        _ensureUsable();
        _reserveIdentity(manifest.id);
        applied = await _contributions.apply(manifest);
        _ensureUsable();
        previousFiles = await _placeFiles(pkg);
        filesPlaced = true;
        _ensureUsable();
        _reserveIdentity(manifest.id);

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
        await _saveState(_state.upsert(record));
        await _seedLegacyPermissions(manifest, wasInstalled: existing != null);
        if (development &&
            existing != null &&
            (_manifests[manifest.id]
                    ?.capabilities
                    .contains(kLibraryPrivateCapability) ??
                false)) {
          PrivateLibrary.instance.clearOptionsOverlay(this);
        }
        _manifests[manifest.id] = manifest;
        _manifestTexts[manifest.id] = pkg.manifestText;
        _upsertMemory(record);
        notifyListeners();
        if (previousFiles != null) await _deleteQuietly(previousFiles);
        return PluginInstallResult(
            record: record, warnings: List.unmodifiable(pkg.warnings));
      } catch (error) {
        if (development) {
          await _contributions.remove(applied);
          final oldManifest = existing == null ? null : _manifests[existing.id];
          if (!_disposed && oldManifest != null) {
            await _contributions.apply(oldManifest);
          }
        }
        if (!development) Prefs().userPrompts = promptsSnapshot;
        try {
          if (!development) await Prefs().saveSelectionToolbar(toolbarSnapshot);
        } catch (_) {
          // The original failure is more useful; the snapshot is retried on
          // the next plugin mutation.
        }
        if (filesPlaced) await _rollbackFiles(manifest.id, previousFiles);
        rethrow;
      }
    } finally {
      _reservedIds.remove(pkg.manifest.id);
      await pkg.dispose();
    }
  }

  Future<void> enable(String id) => _exclusive(() async {
        _reserveIdentity(id);
        try {
          await _enable(id);
        } finally {
          _reservedIds.remove(id);
        }
      });

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
      _reserveIdentity(id);
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
      await _saveState(_state.upsert(updated));
      _upsertMemory(updated);
      notifyListeners();
    } catch (_) {
      if (!development) Prefs().userPrompts = promptsSnapshot;
      try {
        if (!development) await Prefs().saveSelectionToolbar(toolbarSnapshot);
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
    await _authorizePrivateRemoval(id);
    final prompts = Prefs().userPrompts;
    final toolbar = Prefs().selectionToolbar;
    try {
      await _contributions.remove(record.applied);
      final updated =
          record.copyWith(status: PluginStatus.disabled, applied: const []);
      await _saveState(_state.upsert(updated));
      _upsertMemory(updated);
    } catch (_) {
      if (!development) Prefs().userPrompts = prompts;
      if (!development) await Prefs().saveSelectionToolbar(toolbar);
      rethrow;
    }
    if (development &&
        (_manifests[id]?.capabilities.contains(kLibraryPrivateCapability) ??
            false)) {
      PrivateLibrary.instance.clearOptionsOverlay(this);
    }
    notifyListeners();
  }

  Future<void> uninstall(String id) => _exclusive(() => _uninstall(id));

  Future<void> _uninstall(String id) async {
    _ensureUsable();
    final record = _require(id);
    await _authorizePrivateRemoval(id);
    final prompts = Prefs().userPrompts;
    final toolbar = Prefs().selectionToolbar;
    try {
      await _contributions.remove(record.applied);
      await _removeData(id);
    } catch (_) {
      if (!development) Prefs().userPrompts = prompts;
      if (!development) await Prefs().saveSelectionToolbar(toolbar);
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
      if (!development) {
        AnxLog.warning(
            'Could not delete files of $id: ${describeError(error)}');
      }
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
      throw PluginInstallError(
          PluginErrorCode.internal, 'Enable plugins first.');
    }
    if (_disposed || (development && !_sessionOpen)) {
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
      for (final runtime
          in _peer?._runtimes.toList() ?? <PluginScriptRuntime>[]) {
        runtime.cancelAll();
      }
      await _authorizePrivateRemoval(null, allScopes: true);
      await _closeDeveloperSession?.call();
      await _suspendPlugins();
      await Prefs().saveExperimentalPluginsEnabled(false);
    }
    notifyListeners();
  }

  Future<void> _authorizePrivateRemoval(String? id,
      {bool allScopes = false}) async {
    if ((!identical(this, _instance) && _peer == null) ||
        !PrivateLibrary.instance.active) {
      return;
    }
    if (!allScopes && _peer?._hasPrivateProvider == true) return;
    if (id != null) {
      if (!(_manifests[id]?.capabilities.contains(kLibraryPrivateCapability) ??
          false)) {
        return;
      }
      if (_plugins.any((record) =>
          record.id != id &&
          record.status == PluginStatus.enabled &&
          (_manifests[record.id]
                  ?.capabilities
                  .contains(kLibraryPrivateCapability) ??
              false))) {
        return;
      }
    }
    final context = navigatorKey.currentContext;
    if (context == null ||
        !await PrivateLibrary.instance.authorizeDeactivate(context)) {
      throw const PluginInstallError(
          PluginErrorCode.pluginUnavailable, 'Plugin deactivation cancelled.');
    }
    await PrivateLibrary.instance.clearProtection();
  }

  Future<void> _suspendPlugins() async {
    final state = _state;
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
        await _saveState(PluginState(plugins: next));
      }
      _plugins = next;
      _initialized = false;
      _manifests.clear();
      _manifestTexts.clear();
    } catch (_) {
      if (!development) Prefs().userPrompts = prompts;
      if (!development) await Prefs().saveSelectionToolbar(toolbar);
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
    if (development) PrivateLibrary.instance.clearOptionsOverlay(this);
    if (development) {
      for (final record in _plugins) {
        unawaited(_contributions.remove(record.applied).catchError((_) {}));
      }
    }
    for (final runtime in _runtimes.toList()) {
      runtime.cancelAll();
    }
    if (identical(this, _instance)) {
      PluginScriptRuntime.cancelExisting();
      PrivateLibrary.instance
          .setPluginActive(_peer?._hasPrivateProvider ?? false);
    }
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
