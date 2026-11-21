import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:modu_reader/page/home_page.dart' show webViewEnvironment;
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart'
    show PluginScriptFailure;
import 'package:modu_reader/utils/webView/anx_headless_webview.dart';
import 'package:modu_reader/utils/webView/webview_environment_boot.dart';

typedef PluginHostCall = Future<Object?> Function(
    String method, Map<String, dynamic> arguments);

abstract class PluginScriptEngine {
  Future<Map<String, dynamic>> execute(
      String source, Map<String, Object?> input,
      {required PluginHostCall onCall});
  Future<void> dispose();
}

/// A fresh view hosts only our bootstrap. Package code runs in a terminable
/// worker, with no DOM, native bridge or direct network access.
class WebViewPluginScriptEngine implements PluginScriptEngine {
  WebViewPluginScriptEngine(
      {this.maxMessageBytes = 64 * 1024, this.maxStartBytes}) {
    if (maxMessageBytes != 64 * 1024 && maxMessageBytes != 4 * 1024 * 1024) {
      throw ArgumentError.value(maxMessageBytes, 'maxMessageBytes');
    }
    _result.future.ignore();
  }
  final int maxMessageBytes;
  final int? maxStartBytes;
  Future<void>? _disposing;
  AnxHeadlessWebView? _view;
  InAppWebViewController? _controller;
  final _result = Completer<Map<String, dynamic>>();
  bool _disposed = false, _started = false;
  int _messages = 0;
  /// In-flight JavaScript evaluations. dispose() waits for these, because a
  /// platform message that is still pending when the native view is destroyed
  /// is reported by the engine as "Failed to respond to a message".
  final _pendingJs = <Future<void>>{};
  String _diagnosticStage = 'idle';
  String get diagnosticStage => _diagnosticStage;

  /// Codes a worker may report back. Anything else becomes 'execution', so a
  /// compromised or buggy script cannot invent a failure the UI would trust.
  static const Set<String> _workerCodes = {
    'unavailable',
    'busy',
    'cancelled',
    'timeout',
    'execution',
    'permission',
    'denied',
    'quota',
    'size',
    'result',
  };

  void _fail([String? stage]) {
    if (!_result.isCompleted) {
      if (stage != null) _diagnosticStage = stage;
      _result.completeError(StateError('Plugin script could not run'));
    }
  }

  @override
  Future<Map<String, dynamic>> execute(
      String source, Map<String, Object?> input,
      {required PluginHostCall onCall}) async {
    if (_disposed || _view != null) throw StateError('Plugin engine is closed');
    // Ask for the environment instead of only reading the cached one: a single
    // failed start earlier in the session used to leave the cached value null,
    // so every plugin run failed with "WebView2 is not available" until the app
    // was restarted. [WebViewEnvironmentBoot] retries and rate-limits attempts.
    final environment = Platform.isWindows
        ? await WebViewEnvironmentBoot.instance.ensure()
        : webViewEnvironment;
    if (_disposed) throw StateError('Plugin engine is closed');
    if (Platform.isWindows && environment == null) {
      throw StateError('WebView2 is not available');
    }
    _diagnosticStage = 'bootstrap_asset';
    final bootstrap =
        await rootBundle.loadString('assets/plugin-runtime/runtime.js');
    if (_disposed) throw StateError('Plugin engine is closed');
    final nonce = base64Url
        .encode(List.generate(24, (_) => Random.secure().nextInt(256)));
    final handler = 'plugin_$nonce';
    final origin = 'run-${nonce.toLowerCase().replaceAll('_', '-')}-local';
    final pageUrl = WebUri('https://$origin.modu-plugin.invalid/index.html');
    final html = '<!doctype html><meta charset="utf-8">'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
        'script-src \'nonce-$nonce\'; worker-src blob:; child-src blob:; '
        'connect-src \'none\'; frame-src \'none\'; object-src \'none\'; '
        'base-uri \'none\'; form-action \'none\'">'
        '<script nonce="$nonce">$bootstrap</script>';
    _diagnosticStage = 'webview_creation';
    _view = AnxHeadlessWebView(
      webViewEnvironment: environment,
      initialData: InAppWebViewInitialData(
          data: html, baseUrl: pageUrl, historyUrl: pageUrl),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        allowFileAccess: false,
        allowContentAccess: false,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        blockNetworkLoads: true,
        cacheEnabled: false,
        domStorageEnabled: false,
        databaseEnabled: false,
        geolocationEnabled: false,
        mediaPlaybackRequiresUserGesture: true,
        disableContextMenu: true,
      ),
      shouldOverrideUrlLoading: (_, action) async => !_started &&
              (action.request.url == pageUrl ||
                  action.request.url.toString() == 'about:blank')
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
      shouldInterceptRequest: (_, request) async {
        // Some Android providers request the in-memory document through this hook.
        if (!_disposed &&
            !_started &&
            request.isForMainFrame != false &&
            (request.method == null || request.method == 'GET') &&
            request.url == pageUrl) {
          return WebResourceResponse(
              statusCode: 200,
              reasonPhrase: 'OK',
              contentType: 'text/html',
              contentEncoding: 'utf-8',
              headers: {'Cache-Control': 'no-store'},
              data: Uint8List.fromList(utf8.encode(html)));
        }
        return WebResourceResponse(
            statusCode: 403, reasonPhrase: 'Blocked', data: Uint8List(0));
      },
      onCreateWindow: (_, __) async => false,
      onPermissionRequest: (_, request) async => PermissionResponse(
          resources: request.resources, action: PermissionResponseAction.DENY),
      onWebViewCreated: (controller) {
        _diagnosticStage = 'page_load';
        _controller = controller;
        controller.addJavaScriptHandler(
            handlerName: handler,
            callback: (args) async {
              if (_disposed || _result.isCompleted) return null;
              if (++_messages > 40 ||
                  args.length != 1 ||
                  args.single is! String ||
                  (args.single as String).length > maxMessageBytes ||
                  utf8.encode(args.single as String).length > maxMessageBytes) {
                _fail('invalid_message');
                return null;
              }
              try {
                final message = jsonDecode(args.single as String);
                if (message is! Map<String, dynamic>) {
                  throw const FormatException();
                }
                if (message['kind'] == 'result') {
                  final value = message['value'];
                  if (value is! Map<String, dynamic>) {
                    throw const FormatException();
                  }
                  _diagnosticStage = 'complete';
                  _result.complete(value);
                  return null;
                }
                if (message['kind'] == 'call' &&
                    message['method'] is String &&
                    message['arguments'] is Map<String, dynamic>) {
                  _diagnosticStage = 'host_call';
                  try {
                    final value = await onCall(message['method'] as String,
                        message['arguments'] as Map<String, dynamic>);
                    return _disposed ? null : {'value': value};
                  } on PluginScriptFailure catch (failure) {
                    // Carry the host's own code across the bridge. Collapsing
                    // every failure into one string made "the user has not
                    // granted this" indistinguishable from "the package is
                    // broken", which is exactly what left a real permission
                    // failure looking like a generic plugin crash.
                    return {'error': 'Plugin request failed', 'code': failure.code};
                  } catch (_) {
                    return {'error': 'Plugin request failed', 'code': 'execution'};
                  } finally {
                    if (!_disposed && !_result.isCompleted) {
                      _diagnosticStage = 'worker';
                    }
                  }
                }
                if (message['kind'] == 'error') {
                  // The worker names the code it was given; anything else is a
                  // script bug. Typed here so the runtime can log and report the
                  // real cause instead of a blanket 'execution'.
                  final code = message['code'];
                  _result.completeError(PluginScriptFailure(
                      code is String && _workerCodes.contains(code)
                          ? code
                          : 'execution'));
                  _diagnosticStage = 'worker_error';
                  return null;
                }
                _fail('invalid_message');
              } catch (_) {
                _fail('invalid_message');
              }
              return null;
            });
      },
      onLoadStop: (controller, _) {
        if (_disposed || _started) return;
        _started = true;
        _diagnosticStage = 'bootstrap_start';
        final payload = jsonEncode({
          'source': source,
          'input': input,
          'handler': handler,
          'maxMessageBytes': maxMessageBytes
        }).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');
        if (maxStartBytes != null &&
            utf8.encode(payload).length > maxStartBytes!) {
          _fail('invalid_message');
          return;
        }
        late final Future<void> started;
        started = () async {
          if (_disposed || _view?.isDisposed == true) return;
          try {
            final state = await controller.evaluateJavascript(source: '''
(() => {
  if (typeof window.moduPluginStart !== 'function') return 'missing_bootstrap';
  try { return window.moduPluginStart($payload); }
  catch (_) { return 'bootstrap_error'; }
})()
''');
            if (_disposed || _result.isCompleted) return;
            if (state == 'waiting_bridge') {
              _diagnosticStage = 'waiting_bridge';
            } else if (state == 'running') {
              _diagnosticStage = 'worker';
            } else {
              _fail('bootstrap_error');
            }
          } catch (_) {
            _fail('bootstrap_error');
          } finally {
            _pendingJs.remove(started);
          }
        }();
        _pendingJs.add(started);
        unawaited(started);
      },
      onConsoleMessage: (_, message) {
        if (message.messageLevel == ConsoleMessageLevel.ERROR) {
          // Retain a fixed diagnostic marker, never package console content.
          if (!_disposed && !_result.isCompleted) {
            _diagnosticStage = 'javascript_error';
          }
        }
      },
      onLoadError: (_, __, ___, ____) => _fail('page_load_error'),
      onLoadHttpError: (_, url, status, __) {
        if (url == pageUrl) {
          _fail('page_http_error_${status.clamp(100, 599)}');
        }
      },
    );
    await _view!.run();
    return _result.future;
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _fail();
    // A view that was already released (window closing, renderer gone) has no
    // native counterpart left: evaluating into it dereferences freed memory
    // inside the Windows plugin and takes the whole process down with an access
    // violation, so skip straight to releasing what we still own.
    final controller = _view?.isDisposed == true ? null : _controller;
    if (controller != null) {
      // Ask the worker to stop, but *await* the reply before tearing the view
      // down. A fire-and-forget call here leaves its platform message pending
      // when the native side is destroyed, and the Flutter engine reports that
      // as "Failed to respond to a message. This is a memory leak."
      //
      // The timeout keeps a wedged renderer from blocking shutdown: after it
      // elapses we dispose anyway and accept the leak rather than hang.
      try {
        await controller
            .evaluateJavascript(
                source: 'if (window.moduPluginStop) window.moduPluginStop()')
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Cancelled, timed out or already torn down: nothing to do.
      }
      // A bootstrap evaluation may still be in flight; it would outlive the
      // view for the same reason. Bounded so shutdown cannot hang on it.
      if (_pendingJs.isNotEmpty) {
        try {
          await Future.wait(_pendingJs.toList())
              .timeout(const Duration(seconds: 2));
        } catch (_) {
          // Whichever evaluation is stuck is abandoned with the view.
        }
      }
    }
    await _view?.dispose();
  }
}
