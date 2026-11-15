import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_development_trust.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_package.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/utils/get_path/get_cache_dir.dart';
import 'package:path/path.dart' as p;

class PluginDeveloperLog {
  PluginDeveloperLog(
      {required this.id,
      required this.action,
      required this.stage,
      required this.code,
      required this.elapsedMs})
      : time = DateTime.now();
  final DateTime time;
  final String id, action, stage, code;
  final int elapsedMs;
  String get message => '$id · $action · $code · $stage (${elapsedMs}ms)';
}

/// Opt-in for this process only. No developer state is stored in preferences.
class PluginDeveloperSession extends ChangeNotifier {
  PluginDeveloperSession(
      {PluginHost? officialHost,
      Future<Directory> Function()? cacheDirectory,
      PluginScriptEngine Function()? engineFactory})
      : _officialHost = officialHost,
        _cacheDirectory = cacheDirectory ?? getAnxCacheDir,
        _engineFactory = engineFactory;
  static final instance = PluginDeveloperSession();
  final PluginHost? _officialHost;
  final Future<Directory> Function() _cacheDirectory;
  final PluginScriptEngine Function()? _engineFactory;
  PluginHost get _official => _officialHost ?? PluginHost.instance;
  PluginHost? _host;
  PluginScriptRuntime? _runtime;
  PluginDevelopmentTrust? _trust;
  Directory? _directory;
  bool _enabled = false, _disposed = false;
  int _operations = 0;
  void _alive() {
    if (_disposed) throw StateError('Development session closed.');
  }

  Future<void> _pending = Future.value();
  final _logs = <PluginDeveloperLog>[];
  bool get enabled => _enabled;
  bool get busy => _operations != 0;
  PluginHost? get host => _host;
  PluginScriptRuntime? get runtime => _runtime;
  List<PluginDeveloperLog> get logs => List.unmodifiable(_logs);

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _log(Map<String, Object> event) {
    if (!_enabled || _disposed) return;
    _logs.add(PluginDeveloperLog(
        id: event['id'] as String? ?? '',
        action: event['action'] as String? ?? '',
        stage: event['stage'] as String? ?? '',
        code: event['code'] as String? ?? '',
        elapsedMs: event['elapsedMs'] as int? ?? 0));
    if (_logs.length > 200) _logs.removeAt(0);
    _changed();
  }

  void clearLogs() {
    _logs.clear();
    _changed();
  }

  Future<T> _exclusive<T>(Future<T> Function() action) {
    _operations++;
    _changed();
    final future = _pending.then((_) async {
      if (_disposed) throw StateError('Development session closed.');
      return action();
    });
    _pending = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return future.whenComplete(() {
      _operations--;
      _changed();
    });
  }

  Future<void> setEnabled(bool value) => _exclusive(() async {
        if (value == _enabled) return;
        if (!value) {
          await _close();
          return;
        }
        if (!PluginHost.isEnabled || !Prefs().experimentalPluginsEnabled) {
          throw const PluginInstallError(
              PluginErrorCode.pluginUnavailable, 'Enable plugins first.');
        }
        if (PluginHost.hasDevelopmentSession) {
          throw StateError('A development session is already active.');
        }
        final cache = await _cacheDirectory();
        _alive();
        final base = Directory(p.join(cache.path, 'plugin-development-v1'));
        // Old bytes never grant consent in a new application process.
        if (await base.exists()) await base.delete(recursive: true);
        await base.create(recursive: true);
        final directory = await base.createTemp('session-');
        final trust = PluginDevelopmentTrust();
        final developer = PluginHost(
            development: true,
            paths: PluginPaths(rootPath: directory.path),
            trust: trust,
            appVersionResolver: () async => _official.appVersion);
        try {
          await developer.initialize();
          _alive();
          PluginHost.attachDevelopment(_official, developer,
              onGlobalDisable: () =>
                  _exclusive(() => _close(authorized: true)));
          _directory = directory;
          _host = developer;
          _trust = trust;
          _runtime = PluginScriptRuntime(
              host: developer,
              engineFactory: _engineFactory,
              onDiagnostic: _log);
          _enabled = true;
          developer.addListener(_changed);
        } catch (_) {
          developer.dispose();
          if (await directory.exists()) await directory.delete(recursive: true);
          rethrow;
        }
        _changed();
      });

  PluginHost _requireHost() {
    final value = _host;
    if (!_enabled || value == null || _disposed) {
      throw const PluginInstallError(PluginErrorCode.pluginUnavailable,
          'Enable developer debugging first.');
    }
    return value;
  }

  Future<PluginPreview> preview(File package) =>
      _exclusive(() => _requireHost().preview(package, allowSameVersion: true));
  Future<PluginInstallResult> install(File package,
          {required String expectedSha256}) =>
      _exclusive(() => _install(package, expectedSha256));
  Future<PluginInstallResult> reload(File package,
          {required String expectedSha256}) =>
      install(package, expectedSha256: expectedSha256);
  Future<PluginInstallResult> _install(File file, String expected) async {
    final owner = _requireHost(), trust = _trust!;
    final package = await PluginPackageReader(paths: owner.paths).read(file);
    final manifest = package.manifest;
    final previous = trust.sealFor(manifest.id, manifest.version);
    try {
      _alive();
      if (package.sha256 != expected) {
        throw const PluginInstallError(PluginErrorCode.invalidPackage,
            'Package changed after permission confirmation. Select it again.');
      }
      await trust.acceptPackage(package);
      _alive();
      final result = await owner.install(file,
          allowSameVersion: true, expectedSha256: expected);
      _log({
        'id': manifest.id,
        'action': '',
        'stage': 'install',
        'code': 'installed',
        'elapsedMs': 0
      });
      return result;
    } catch (_) {
      trust.restore(manifest.id, manifest.version, previous);
      _log({
        'id': manifest.id,
        'action': '',
        'stage': 'install',
        'code': 'rejected',
        'elapsedMs': 0
      });
      rethrow;
    } finally {
      await package.dispose();
    }
  }

  Future<void> uninstall(String id) => _exclusive(() async {
        await _requireHost().uninstall(id);
        _trust!.forget(id);
      });
  Future<void> _close({bool authorized = false}) async {
    final owner = _host;
    if (!_enabled || owner == null) return;
    await owner.closeDevelopment(skipAuthorization: authorized);
    _enabled = false;
    _runtime?.dispose();
    _runtime = null;
    owner.removeListener(_changed);
    PluginHost.detachDevelopment(owner);
    owner.dispose();
    _host = null;
    _trust?.clear();
    _trust = null;
    _logs.clear();
    final directory = _directory;
    _directory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _runtime?.dispose();
    _host?.removeListener(_changed);
    if (_host != null) {
      PluginHost.detachDevelopment(_host!);
      _host!.dispose();
    }
    _trust?.clear();
    _logs.clear();
    // No authorization or user-data mutation during process disposal.
    super.dispose();
  }
}
