import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_host_api.dart';
import 'package:modu_reader/service/plugins/plugin_http_budget.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:path/path.dart' as p;

import 'plugin_host.dart';

/// Host methods implemented in Dart by [PluginHostApi].
///
/// Split from the reader-bound methods (`library.list`, `notes.save`, the
/// private-library bridge and `articles.capture`) which need the live reading
/// context and therefore still travel through the page-supplied callback.
const Set<String> kPluginServiceMethods = {
  'library.tags',
  'library.groups',
  'library.tag',
  'library.move',
  'books.content',
  'books.chapter',
  'notes.list',
  'reading.stats',
  'reading.history',
  'search.library',
  'knowledge.search',
  'dictionary.lookup',
  'ai.complete',
  'translate.text',
  'clipboard.write',
  'clipboard.read',
  'share.text',
  'ui.confirm',
  'ui.prompt',
  'ui.select',
  'ui.progress',
  'open.url',
  'storage.list',
  'storage.read',
  'storage.write',
  'storage.remove',
  'permissions.request',
  'permissions.status',
};

/// Methods whose latency is not the plugin's CPU time.
///
/// These either open native UI or wait on the user's own model, translation or
/// speech service. The execution clock pauses while one is pending, bounded by
/// the shared native-interaction budget, so a slow model server cannot turn a
/// correct plugin into a timeout failure.
const Set<String> kPluginInteractiveMethods = {
  'privateLibrary.updateOptions',
  'privateLibrary.selectBooks',
  'privateLibrary.setPrivate',
  'ui.confirm',
  'ui.prompt',
  'ui.select',
  'share.text',
  'clipboard.read',
  'ai.complete',
  'translate.text',
  'tts.speak',
  'permissions.request',
};

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
    this.nativeInteractionTimeout = const Duration(minutes: 2),
    this.onDiagnostic,
  })  : _host = host,
        _engineFactory = engineFactory,
        _guard = networkGuard ?? PluginNetworkGuard(),
        _http = httpClient ?? PluginHttpClient(budget: PluginHttpBudget()) {
    WidgetsBinding.instance.addObserver(this);
    this.host.registerRuntime(this);
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
  final PluginScriptEngine Function()? _engineFactory;
  final PluginNetworkGuard _guard;
  final PluginHttpClient _http;
  final Duration timeout;
  final Duration nativeInteractionTimeout;
  final void Function(Map<String, Object>)? onDiagnostic;
  void _diagnostic(
      String id, String action, String stage, String code, int elapsed) {
    try {
      onDiagnostic?.call({
        'id': id,
        'action': action,
        'stage': stage,
        'code': code,
        'elapsedMs': elapsed
      });
    } catch (_) {/* Observer only. */}
  }

  final _jobs = <String, _ScriptJob>{};
  static const maxInputBytes = 64 * 1024, maxResultBytes = 64 * 1024;
  static const maxArticleInputBytes = 16 * 1024 * 1024;
  static const maxArticleResultBytes = 4 * 1024 * 1024;
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
    PluginHostApi? hostApi,
    bool Function()? isContextValid,
    PluginCancelToken? cancel,
  }) {
    final manifest = host.manifestFor(pluginId);
    final record = host.byId(pluginId);
    if (manifest == null ||
        record == null ||
        !_enabled(pluginId, record.version) ||
        !manifest.capabilities.contains(kScriptRunCapability) ||
        (action.surface == PluginScriptSurface.article &&
            (!manifest.capabilities.contains(kArticleExtractCapability) ||
                action.scope != PluginSelectionScope.selection)) ||
        (action.surface == PluginScriptSurface.bookImport &&
            (!manifest.capabilities.contains(kLibraryPrivatePolicyCapability) ||
                !manifest.capabilities.contains(kLibraryPrivateCapability) ||
                action.scope != PluginSelectionScope.selection)) ||
        !manifest.contributions.any((c) => identical(c, action))) {
      _logFailure(pluginId, record?.version ?? 'unknown', action.id,
          'unavailable', 'validate', 0);
      return Future.error(const PluginScriptFailure('unavailable'));
    }
    if (_jobs.containsKey(pluginId) || _jobs.length >= 2) {
      _logFailure(pluginId, record.version, action.id, 'busy', 'queue', 0);
      return Future.error(const PluginScriptFailure('busy'));
    }
    if (cancel?.isCancelled == true) {
      return Future.error(const PluginScriptFailure('cancelled'));
    }
    final article = action.surface == PluginScriptSurface.article;
    final job = _ScriptJob(
        _engineFactory?.call() ??
            WebViewPluginScriptEngine(
                maxMessageBytes:
                    article ? maxArticleResultBytes : maxResultBytes,
                maxStartBytes: article ? maxArticleInputBytes : null),
        pluginId,
        record.version,
        action.id,
        isContextValid);
    _jobs[pluginId] = job;
    _diagnostic(pluginId, action.id, 'validate', 'started', 0);
    final limit = (action.surface == PluginScriptSurface.dictionary ||
                action.surface == PluginScriptSurface.bookImport) &&
            timeout > const Duration(seconds: 2)
        ? const Duration(seconds: 2)
        : timeout;
    job.remaining = limit;
    job.nativeRemaining = nativeInteractionTimeout;
    _resumeExecution(job);
    cancel?.whenCancelled(() {
      if (identical(_jobs[pluginId], job) && !job.result.isCompleted) {
        _abort(job, 'cancelled');
      }
    });
    unawaited(
        _execute(pluginId, manifest, action, input, hostCall, hostApi, job));
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
      PluginHostApi? hostApi,
      _ScriptJob job) async {
    try {
      _check(id, job);
      final directory = host.paths.pluginDir(id);
      await host.trust.verify(directory, id, job.version);
      _check(id, job);
      job.stage = 'source';
      final file = File(p.join(directory.path, action.entry));
      final article = action.surface == PluginScriptSurface.article;
      final maxSourceBytes = article
          ? PluginLimits.maxArticleScriptBytes
          : PluginLimits.maxScriptBytes;
      if (await file.length() > maxSourceBytes) {
        throw const PluginScriptFailure('size');
      }
      final bytes = await file.readAsBytes();
      final expected =
          (await host.trust.reviewedFiles(id, job.version))?[action.entry];
      if (bytes.length > maxSourceBytes ||
          expected == null ||
          sha256.convert(bytes).toString() != expected) {
        throw const PluginScriptFailure('unavailable');
      }
      _check(id, job);
      job.stage = 'input';
      final config = host.configFor(id);
      final settings = <String, Object?>{
        for (final spec in manifest.settings)
          if (!spec.isSecret && spec.type != PluginSettingType.tip)
            spec.key: config[spec.key] ?? spec.defaultValue,
      };
      // Only named fields from the trusted UI cross the process boundary.
      final importPolicy = action.surface == PluginScriptSurface.bookImport;
      final payload = article
          ? _articleInput(input, settings, action.id)
          : importPolicy
              ? {
                  'book': input['book'] is Map
                      ? _bookSummary(input['book'] as Map)
                      : throw const PluginScriptFailure('result'),
                  'settings': settings,
                  'actionId': action.id,
                }
              : <String, Object?>{
                  'selection':
                      input['selection'] is String ? input['selection'] : '',
                  if (action.surface != PluginScriptSurface.dictionary &&
                      action.scope == PluginSelectionScope.context)
                    'context':
                        input['context'] is String ? input['context'] : '',
                  'settings': settings,
                  'actionId': action.id,
                  if (action.surface != PluginScriptSurface.dictionary &&
                      input['book'] is Map)
                    'book': _bookSummary(input['book'] as Map),
                };
      _bounded(payload, article ? maxArticleInputBytes : maxInputBytes);
      job.stage = 'execute';
      final result = await job.engine.execute(utf8.decode(bytes), payload,
          onCall: (method, args) => article ||
                  importPolicy ||
                  action.surface == PluginScriptSurface.dictionary
              ? Future.error(const PluginScriptFailure('permission'))
              : _call(id, manifest, method, args, hostCall, hostApi, job));
      _check(id, job);
      job.stage = 'result';
      _bounded(result, article ? maxArticleResultBytes : maxResultBytes);
      if (article) {
        validateArticleResult(result);
      } else if (importPolicy) {
        if (result.length != 1 || result['private'] is! bool) {
          throw const PluginScriptFailure('result');
        }
      } else if (action.surface == PluginScriptSurface.dictionary) {
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
      _diagnostic(id, action.id, 'result', 'completed',
          job.elapsed.elapsedMilliseconds);
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

  static Map<String, Object?> _articleInput(Map<String, Object?> input,
      Map<String, Object?> settings, String actionId) {
    final html = input['html'], url = input['url'], plain = input['plainText'];
    if (html is! String ||
        url is! String ||
        plain is! bool ||
        url.length > 4096 ||
        url.contains(RegExp(r'[\x00-\x20\x7f]'))) {
      throw const PluginScriptFailure('result');
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasFragment) {
      throw const PluginScriptFailure('result');
    }
    if (utf8.encode(html).length > PluginLimits.maxArticleHtmlBytes) {
      throw const PluginScriptFailure('size');
    }
    return {
      'html': html,
      'url': url,
      'plainText': plain,
      'settings': settings,
      'actionId': actionId
    };
  }

  static void validateArticleResult(Map<String, dynamic> result) {
    final title = result['title'], markdown = result['markdown'];
    if (result.length != 2 ||
        title is! String ||
        markdown is! String ||
        title.trim().isEmpty ||
        title.runes.length > 200 ||
        title.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        markdown.trim().isEmpty ||
        markdown.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'))) {
      throw const PluginScriptFailure('result');
    }
    if (utf8.encode(markdown).length > PluginLimits.maxArticleMarkdownBytes) {
      throw const PluginScriptFailure('size');
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
      PluginHostApi? hostApi,
      _ScriptJob job) async {
    _check(id, job);
    _bounded(args, maxInputBytes);
    if (++job.calls > 16 || job.callBusy) {
      throw const PluginScriptFailure('quota');
    }
    final permission = switch (method) {
      'http.get' => 'net:http',
      'library.list' => kLibraryReadCapability,
      'library.tags' => kLibraryReadCapability,
      'library.groups' => kLibraryReadCapability,
      'library.tag' || 'library.move' => kLibraryWriteCapability,
      'books.content' => kBookContentCapability,
      'books.chapter' => kBookContentCapability,
      'notes.list' => kNoteReadCapability,
      'notes.save' => kNoteWriteCapability,
      'reading.stats' || 'reading.history' => kReadingReadCapability,
      'search.library' => kSearchLibraryCapability,
      'knowledge.search' => kKnowledgeQueryCapability,
      'ai.complete' => kAiInvokeCapability,
      'translate.text' => kTranslateInvokeCapability,
      'tts.speak' => kTtsInvokeCapability,
      'dictionary.lookup' => kDictionaryLookupCapability,
      'clipboard.read' => kClipboardReadCapability,
      'clipboard.write' => kClipboardWriteCapability,
      'share.text' => kShareTextCapability,
      'ui.confirm' || 'ui.prompt' || 'ui.select' => kUiDialogCapability,
      'ui.progress' => kUiProgressCapability,
      'open.url' => kUrlOpenCapability,
      // Implicit by design: every plugin already owns a private directory, so
      // `storage:plugin` is accepted in a manifest but never stored as a grant.
      'storage.list' ||
      'storage.read' ||
      'storage.write' ||
      'storage.remove' =>
        'storage:plugin',
      // Asking for consent is itself ungated on purpose: a plugin cannot grant
      // anything by asking, only surface a sheet the user always decides. If it
      // were gated, a plugin that lost a grant could never request it back.
      'permissions.request' || 'permissions.status' => kScriptRunCapability,
      'privateLibrary.open' ||
      'privateLibrary.lock' =>
        kLibraryPrivateCapability,
      'privateLibrary.state' ||
      'privateLibrary.updateOptions' ||
      'privateLibrary.selectBooks' ||
      'privateLibrary.setPrivate' =>
        kLibraryPrivateControlCapability,
      'articles.capture' => kArticleCaptureCapability,
      _ => throw const PluginScriptFailure('permission'),
    };
    if (!manifest.capabilities.contains(permission) ||
        (permission == kLibraryPrivateControlCapability &&
            !manifest.capabilities.contains(kLibraryPrivateCapability))) {
      throw const PluginScriptFailure('permission');
    }
    // A capability the user has not granted yet fails as `denied` rather than
    // `permission`, so the UI can offer to open the permission switches instead
    // of claiming the package is broken.
    if (!host.hasPermission(id, permission)) {
      throw const PluginScriptFailure('denied');
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
      } else if (kPluginServiceMethods.contains(method)) {
        // Implemented in Dart by the host itself, so these methods work from
        // the reading view, the plugin page and tests alike.
        if (hostApi == null) throw const PluginScriptFailure('permission');
        final interactive = kPluginInteractiveMethods.contains(method);
        if (interactive) _beginNativeInteraction(job);
        try {
          value = await hostApi.call(method, args);
        } catch (error) {
          throw error is PluginScriptFailure
              ? error
              : const PluginScriptFailure('execution');
        } finally {
          if (interactive) _endNativeInteraction(job);
        }
      } else {
        if (hostCall == null) throw const PluginScriptFailure('permission');
        final interactive = kPluginInteractiveMethods.contains(method);
        if (interactive) _beginNativeInteraction(job);
        try {
          value = await hostCall(method, args);
        } finally {
          if (interactive) _endNativeInteraction(job);
        }
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

  void _resumeExecution(_ScriptJob job) {
    if (job.result.isCompleted) return;
    if (job.remaining <= Duration.zero) {
      _abort(job, 'timeout');
      return;
    }
    job.executionClock
      ..reset()
      ..start();
    job.timer = Timer(job.remaining, () => _abort(job, 'timeout'));
  }

  void _beginNativeInteraction(_ScriptJob job) {
    job.timer?.cancel();
    job.remaining -= job.executionClock.elapsed;
    job.executionClock.stop();
    if (job.remaining <= Duration.zero ||
        job.nativeRemaining <= Duration.zero) {
      _abort(job, 'timeout');
      throw const PluginScriptFailure('timeout');
    }
    job.nativeClock
      ..reset()
      ..start();
    job.timer = Timer(job.nativeRemaining, () => _abort(job, 'timeout'));
  }

  void _endNativeInteraction(_ScriptJob job) {
    job.timer?.cancel();
    job.nativeRemaining -= job.nativeClock.elapsed;
    job.nativeClock.stop();
    if (!job.result.isCompleted) {
      if (job.nativeRemaining <= Duration.zero) {
        _abort(job, 'timeout');
      } else {
        _resumeExecution(job);
      }
    }
  }

  void _abort(_ScriptJob job, String code) {
    if (job.result.isCompleted) return;
    job.cancel.cancel();
    job.timer?.cancel();
    job.executionClock.stop();
    job.nativeClock.stop();
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

  void _logFailure(String id, String version, String action, String code,
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
      'denied',
      'quota',
      'size',
      'result'
    }.contains(code)
        ? code
        : 'execution';
    final message =
        'Plugin script failed: plugin=${token(id)} version=${token(version)} '
        'action=${token(action)} code=$safeCode stage=${token(stage)} elapsed_ms=$elapsed';
    _diagnostic(token(id), token(action), token(stage), safeCode, elapsed);
    if (host.development) return;
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
    host.unregisterRuntime(this);
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
  Duration remaining = Duration.zero, nativeRemaining = Duration.zero;
  final executionClock = Stopwatch(), nativeClock = Stopwatch();
  int calls = 0, requests = 0;
  bool callBusy = false;
}
