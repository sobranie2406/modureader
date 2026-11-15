import 'dart:async';
import 'dart:convert';

import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/article_capture.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_http_client.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';

/// Coordinates native acquisition and one offline, terminable plugin job.
class PluginArticleExtractor {
  PluginArticleExtractor(
      {required this.host,
      PluginScriptRuntime? runtime,
      this.timeout = const Duration(seconds: 15)})
      : _runtime = runtime;
  final PluginHost host;
  final PluginScriptRuntime? _runtime;
  final Duration timeout;
  static int _active = 0;

  ScriptActionContribution? _action(String pluginId) {
    final manifest = host.manifestFor(pluginId);
    if (!host.isScriptRunnable(pluginId) ||
        manifest == null ||
        !manifest.capabilities.containsAll({
          kScriptRunCapability,
          kArticleCaptureCapability,
          kArticleExtractCapability
        })) {
      return null;
    }
    final actions = manifest.contributions
        .whereType<ScriptActionContribution>()
        .where((action) => action.surface == PluginScriptSurface.article)
        .toList();
    return actions.length == 1 ? actions.single : null;
  }

  bool available(String pluginId) => _action(pluginId) != null;

  Future<CapturedArticle> capture(String url,
      {required String pluginId,
      required ArticleCaptureService service,
      required PluginCancelToken cancel,
      required bool Function() isContextValid}) async {
    final action = _action(pluginId);
    if (action == null) throw const ArticleCaptureFailure('upgrade');
    if (cancel.isCancelled || !isContextValid()) {
      throw const ArticleCaptureFailure('cancelled');
    }
    if (_active >= 2) throw const ArticleCaptureFailure('busy');
    _active++;
    final manifest = host.manifestFor(pluginId);
    final token = PluginCancelToken();
    final interrupted = Completer<CapturedArticle>();
    interrupted.future.ignore();
    var stopped = false, finished = false;
    String? stopCode;
    void abort(String code) {
      if (finished || stopped) return;
      stopped = true;
      stopCode = code;
      token.cancel();
      interrupted.completeError(ArticleCaptureFailure(code));
    }

    cancel.whenCancelled(() => abort('cancelled'));
    final timer = Timer(timeout, () => abort('timeout'));
    bool current() =>
        !stopped &&
        !cancel.isCancelled &&
        isContextValid() &&
        identical(manifest, host.manifestFor(pluginId)) &&
        identical(action, _action(pluginId));
    void check() {
      if (!current()) throw const ArticleCaptureFailure('cancelled');
    }

    void ownerChanged() {
      if (!current()) abort('cancelled');
    }

    host.addListener(ownerChanged);
    Future<CapturedArticle> acquire() async {
      check();
      final document = await service.fetchDocument(url, cancel: token);
      check();
      if (utf8.encode(document.content).length >
          ArticleCaptureService.maxBytes) {
        throw const ArticleCaptureFailure('size');
      }
      final runtime = _runtime ?? PluginHost.runtimeFor(pluginId);
      if (!identical(runtime.host, host)) {
        throw const ArticleCaptureFailure('upgrade');
      }
      final result = await runtime.run(
          pluginId: pluginId,
          action: action,
          input: {
            'html': document.content,
            'url': document.sourceUrl.toString(),
            'plainText': document.plainText
          },
          isContextValid: current,
          cancel: token);
      check();
      PluginScriptRuntime.validateArticleResult(result);
      return CapturedArticle(result['title'] as String, document.sourceUrl,
          result['markdown'] as String);
    }

    try {
      return await Future.any([acquire(), interrupted.future]);
    } on ArticleCaptureFailure catch (error) {
      throw ArticleCaptureFailure(stopCode ?? error.code);
    } on PluginScriptFailure catch (error) {
      if (stopCode != null) throw ArticleCaptureFailure(stopCode!);
      throw ArticleCaptureFailure(switch (error.code) {
        'cancelled' || 'timeout' || 'busy' || 'size' || 'result' => error.code,
        'unavailable' => 'upgrade',
        _ => 'extract',
      });
    } finally {
      finished = true;
      host.removeListener(ownerChanged);
      timer.cancel();
      token.cancel();
      _active--;
    }
  }
}
