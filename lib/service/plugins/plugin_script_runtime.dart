import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_http_budget.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:path/path.dart' as p;

import 'plugin_host.dart';

class PluginScriptFailure implements Exception {
  const PluginScriptFailure(this.code);
  final String code;
  @override
  String toString() => 'PluginScriptFailure($code)';
}

class PluginScriptRuntime with WidgetsBindingObserver {
  PluginScriptRuntime({
    PluginHost? host,
    PluginScriptEngine Function()? engineFactory,
    PluginNetworkGuard? networkGuard,
    PluginHttpClient? httpClient,
    this.timeout = const Duration(seconds: 10),
  })  : _host = host,
        _engineFactory = engineFactory ?? WebViewPluginScriptEngine.new,
        _guard = networkGuard ?? PluginNetworkGuard(),
        _http = httpClient ?? PluginHttpClient(budget: PluginHttpBudget()) {
    WidgetsBinding.instance.addObserver(this);
  }

  static PluginScriptRuntime? _instance;
  static PluginScriptRuntime get instance =>
      _instance ??= PluginScriptRuntime();

  /// Lifecycle calls must not instantiate a WebView runtime at app startup.
  static void cancelExisting([String? id]) {
    if (id == null) {
      _instance?.cancelAll();
    } else {
      _instance?.cancelPlugin(id);
    }
  }

  final PluginHost? _host;
  PluginHost get host => _host ?? PluginHost.instance;
  final PluginScriptEngine Function() _engineFactory;
  final PluginNetworkGuard _guard;
  final PluginHttpClient _http;
  final Duration timeout;
  final _jobs = <String, _ScriptJob>{};
  static const maxInputBytes = 64 * 1024, maxResultBytes = 64 * 1024;
  bool isRunning(String id) => _jobs[id]?.result.isCompleted == false;

  bool _enabled(String id, String version) =>
      PluginHost.isEnabled &&
      Prefs().experimentalPluginsEnabled &&
      host.isScriptRunnable(id) &&
      host.byId(id)?.version == version;

  Future<Map<String, dynamic>> run({
    required String pluginId,
    required ScriptActionContribution action,
    Map<String, Object?> input = const {},
    PluginHostCall? hostCall,
    bool Function()? isContextValid,
  }) {
    final manifest = host.manifestFor(pluginId);
    final record = host.byId(pluginId);
    if (manifest == null ||
        record == null ||
        !_enabled(pluginId, record.version) ||
        !manifest.capabilities.contains(kScriptRunCapability) ||
        !manifest.contributions.any((c) => identical(c, action))) {
      _logFailure(pluginId, record?.version ?? 'unknown', action.id,
          'unavailable', 'validate', 0);
      return Future.error(const PluginScriptFailure('unavailable'));
    }
    if (_jobs.containsKey(pluginId) || _jobs.length >= 2) {
      _logFailure(pluginId, record.version, action.id, 'busy', 'queue', 0);
      return Future.error(const PluginScriptFailure('busy'));
    }
    final job = _ScriptJob(
        _engineFactory(), pluginId, record.version, action.id, isContextValid);
    _jobs[pluginId] = job;
    final limit = action.surface == PluginScriptSurface.dictionary &&
            timeout > const Duration(seconds: 2)
        ? const Duration(seconds: 2)
        : timeout;
    job.timer = Timer(limit, () => _abort(job, 'timeout'));
    unawaited(_execute(pluginId, manifest, action, input, hostCall, job));
    return job.result.future;
  }

  void _check(String id, _ScriptJob job) {
    if (job.cancel.isCancelled ||
        job.isContextValid?.call() == false ||
        job.result.isCompleted ||
        !_enabled(id, job.version) ||
        !identical(_jobs[id], job)) {
      throw const PluginScriptFailure('cancelled');
    }
  }

  Future<void> _execute(
      String id,
      PluginManifest manifest,
      ScriptActionContribution action,
      Map<String, Object?> input,
      PluginHostCall? hostCall,
      _ScriptJob job) async {
    try {
      final directory = host.paths.pluginDir(id);
      await host.trust.verify(directory, id, job.version);
      _check(id, job);
      job.stage = 'source';
      final file = File(p.join(directory.path, action.entry));
      if (await file.length() > PluginLimits.maxScriptBytes) {
        throw const PluginScriptFailure('size');
      }
      final bytes = await file.readAsBytes();
      final expected =
          (await host.trust.reviewedFiles(id, job.version))?[action.entry];
      if (bytes.length > PluginLimits.maxScriptBytes ||
          expected == null ||
          sha256.convert(bytes).toString() != expected) {
        throw const PluginScriptFailure('unavailable');
      }
      _check(id, job);
      job.stage = 'input';
      final config = Prefs().pluginConfig(id);
      final settings = <String, Object?>{
        for (final spec in manifest.settings)
          if (!spec.isSecret && spec.type != PluginSettingType.tip)
            spec.key: config[spec.key] ?? spec.defaultValue,
      };
      // Only named fields from the trusted UI cross the process boundary.
      final payload = <String, Object?>{
        'selection': input['selection'] is String ? input['selection'] : '',
        if (action.surface != PluginScriptSurface.dictionary &&
            action.scope == PluginSelectionScope.context)
          'context': input['context'] is String ? input['context'] : '',
        'settings': settings,
        'actionId': action.id,
        if (action.surface != PluginScriptSurface.dictionary &&
            input['book'] is Map)
          'book': _bookSummary(input['book'] as Map),
      };
      _bounded(payload, maxInputBytes);
      job.stage = 'execute';
      final result = await job.engine.execute(utf8.decode(bytes), payload,
          onCall: (method, args) =>
              action.surface == PluginScriptSurface.dictionary
                  ? Future.error(const PluginScriptFailure('permission'))
                  : _call(id, manifest, method, args, hostCall, job));
      _check(id, job);
      job.stage = 'result';
      _bounded(result, maxResultBytes);
      if (action.surface == PluginScriptSurface.dictionary) {
        final candidates = result['candidates'];
        if (result.length != 1 ||
            candidates is! List ||
            candidates.length > 12 ||
            candidates.any((word) =>
                word is! String ||
                word.trim().isEmpty ||
                word.length > 256 ||
                word.contains(RegExp(r'[\x00-\x1f\x7f]')))) {
          throw const PluginScriptFailure('result');
        }
      } else if (result.keys.any((key) => !{'title', 'text'}.contains(key)) ||
          (result['title'] != null && result['title'] is! String) ||
          (result['text'] != null && result['text'] is! String) ||
          (result['title'] as String? ?? '').length > 120) {
        throw const PluginScriptFailure('result');
      }
      job.result.complete(result);
    } on PluginScriptFailure catch (error) {
      _completeFailure(job, error);
    } catch (_) {
      _completeFailure(job, const PluginScriptFailure('execution'));
    } finally {
      job.timer?.cancel();
      job.cancel.cancel();
      try {
        await job.engine.dispose();
      } catch (_) {/* Keep failures private. */}
      if (identical(_jobs[id], job)) _jobs.remove(id);
    }
  }

  static Map<String, Object?> _bookSummary(Map book) => {
        for (final key in ['id', 'title', 'author', 'format'])
          if (book[key] is String || (key == 'id' && book[key] is int))
            key: book[key],
      };

  Future<Object?> _call(
      String id,
      PluginManifest manifest,
      String method,
      Map<String, dynamic> args,
      PluginHostCall? hostCall,
      _ScriptJob job) async {
    _check(id, job);
    _bounded(args, maxInputBytes);
    if (++job.calls > 16 || job.callBusy) {
      throw const PluginScriptFailure('quota');
    }
    final permission = switch (method) {
      'http.get' => 'net:http',
      'library.list' => kLibraryReadCapability,
      'notes.save' => kNoteWriteCapability,
      'privateLibrary.open' ||
      'privateLibrary.lock' =>
        kLibraryPrivateCapability,
      'articles.capture' => kArticleCaptureCapability,
      _ => throw const PluginScriptFailure('permission'),
    };
    if (!manifest.capabilities.contains(permission)) {
      throw const PluginScriptFailure('permission');
    }
    job.callBusy = true;
    final previousStage = job.stage;
    job.stage = 'host_call';
    try {
      Object? value;
      if (method == 'http.get') {
        if (++job.requests > 1 ||
            args.keys.any((key) => key != 'url') ||
            args['url'] is! String ||
            (args['url'] as String).length > 4096 ||
            manifest.network == null) {
          throw const PluginScriptFailure('quota');
        }
        job.stage = 'dns';
        final target = await _guard.validate(
            network: manifest.network!,
            uri: Uri.parse(args['url'] as String),
            headers: const {});
        _check(id, job);
        job.stage = 'http';
        final bytes = await _http.get(
            target: target,
            timeout: Duration(milliseconds: manifest.network!.timeoutMs),
            maxBytes:
                manifest.network!.maxResponseBytes.clamp(0, maxResultBytes),
            pluginId: id,
            cancel: job.cancel);
        value = {'text': utf8.decode(bytes)};
      } else {
        if (hostCall == null) throw const PluginScriptFailure('permission');
        value = await hostCall(method, args);
      }
      _check(id, job);
      _bounded(value, maxResultBytes);
      return value;
    } finally {
      job.callBusy = false;
      job.stage = previousStage;
    }
  }

  static void _bounded(Object? value, int bytes) {
    // The bridge admits only shallow JSON, with a byte and node budget.
    var nodes = 0;
    void visit(Object? node, int depth) {
      if (++nodes > 2000 || depth > 12) throw const PluginScriptFailure('size');
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key is! String) throw const PluginScriptFailure('result');
          visit(entry.value, depth + 1);
        }
      } else if (node is List) {
        for (final item in node) {
          visit(item, depth + 1);
        }
      } else if (node != null &&
          node is! String &&
          node is! bool &&
          node is! num) {
        throw const PluginScriptFailure('result');
      }
    }

    visit(value, 0);
    if (utf8.encode(jsonEncode(value)).length > bytes) {
      throw const PluginScriptFailure('size');
    }
  }

  void _abort(_ScriptJob job, String code) {
    job.cancel.cancel();
    job.timer?.cancel();
    _completeFailure(job, PluginScriptFailure(code));
    unawaited(job.engine.dispose().catchError((_) {}));
  }

  void _completeFailure(_ScriptJob job, PluginScriptFailure failure) {
    if (job.result.isCompleted) return;
    job.result.completeError(failure);
    final engine = job.engine;
    final stage = job.stage == 'execute' && engine is WebViewPluginScriptEngine
        ? engine.diagnosticStage
        : job.stage;
    _logFailure(job.pluginId, job.version, job.actionId, failure.code, stage,
        job.elapsed.elapsedMilliseconds);
  }

  static void _logFailure(String id, String version, String action, String code,
      String stage, int elapsed) {
    String token(String value) =>
        RegExp(r'^[A-Za-z0-9_.-]{1,80}$').hasMatch(value) ? value : 'unknown';
    final safeCode = const {
      'unavailable',
      'busy',
      'cancelled',
      'timeout',
      'execution',
      'permission',
      'quota',
      'size',
      'result'
    }.contains(code)
        ? code
        : 'execution';
    final message =
        'Plugin script failed: plugin=${token(id)} version=${token(version)} '
        'action=${token(action)} code=$safeCode stage=${token(stage)} elapsed_ms=$elapsed';
    if (safeCode == 'cancelled') {
      AnxLog.info(message);
    } else {
      AnxLog.warning(message);
    }
  }

  void cancelPlugin(String id) {
    final job = _jobs[id];
    if (job != null) _abort(job, 'cancelled');
  }

  void cancelAll() {
    for (final job in _jobs.values.toList()) {
      _abort(job, 'cancelled');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      cancelAll();
    }
  }

  void dispose() {
    cancelAll();
    WidgetsBinding.instance.removeObserver(this);
  }
}

class _ScriptJob {
  _ScriptJob(this.engine, this.pluginId, this.version, this.actionId,
      this.isContextValid);
  final PluginScriptEngine engine;
  final String pluginId, version, actionId;
  final elapsed = Stopwatch()..start();
  String stage = 'verify';
  final bool Function()? isContextValid;
  final result = Completer<Map<String, dynamic>>();
  final cancel = PluginCancelToken();
  Timer? timer;
  int calls = 0, requests = 0;
  bool callBusy = false;
}
