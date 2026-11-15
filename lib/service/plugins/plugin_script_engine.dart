import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:modu_reader/page/home_page.dart' show webViewEnvironment;
import 'package:modu_reader/utils/webView/anx_headless_webview.dart';

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
  WebViewPluginScriptEngine() {
    _result.future.ignore();
  }
  Future<void>? _disposing;
  AnxHeadlessWebView? _view;
  InAppWebViewController? _controller;
  final _result = Completer<Map<String, dynamic>>();
  bool _disposed = false, _started = false;
  int _messages = 0;
  String _diagnosticStage = 'idle';
  String get diagnosticStage => _diagnosticStage;

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
    if (Platform.isWindows && webViewEnvironment == null) {
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
      webViewEnvironment: webViewEnvironment,
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
                  (args.single as String).length > 65536 ||
                  utf8.encode(args.single as String).length > 65536) {
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
                  } catch (_) {
                    return {'error': 'Plugin request failed'};
                  } finally {
                    if (!_disposed && !_result.isCompleted) {
                      _diagnosticStage = 'worker';
                    }
                  }
                }
                _fail(message['kind'] == 'error'
                    ? 'worker_error'
                    : 'invalid_message');
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
        final payload =
            jsonEncode({'source': source, 'input': input, 'handler': handler})
                .replaceAll('\u2028', r'\u2028')
                .replaceAll('\u2029', r'\u2029');
        unawaited(() async {
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
          }
        }());
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
    final controller = _controller;
    if (controller != null) {
      unawaited(controller
          .evaluateJavascript(
              source: 'if (window.moduPluginStop) window.moduPluginStop()')
          .catchError((_) => null));
    }
    await _view?.dispose();
  }
}
