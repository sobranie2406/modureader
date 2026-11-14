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

  void _fail() {
    if (!_result.isCompleted) {
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
    final bootstrap =
        await rootBundle.loadString('assets/plugin-runtime/runtime.js');
    if (_disposed) throw StateError('Plugin engine is closed');
    final nonce = base64Url
        .encode(List.generate(24, (_) => Random.secure().nextInt(256)));
    final handler = 'plugin_$nonce';
    final html = '<!doctype html><meta charset="utf-8">'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
        'script-src \'nonce-$nonce\'; worker-src blob:; child-src blob:; '
        'connect-src \'none\'; frame-src \'none\'; object-src \'none\'; '
        'base-uri \'none\'; form-action \'none\'">'
        '<script nonce="$nonce">$bootstrap</script>';
    _view = AnxHeadlessWebView(
      webViewEnvironment: webViewEnvironment,
      initialData: InAppWebViewInitialData(data: html),
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
      shouldOverrideUrlLoading: (_, action) async =>
          !_started && action.request.url.toString() == 'about:blank'
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL,
      shouldInterceptRequest: (_, request) async => WebResourceResponse(
          statusCode: 403, reasonPhrase: 'Blocked', data: Uint8List(0)),
      onCreateWindow: (_, __) async => false,
      onPermissionRequest: (_, request) async => PermissionResponse(
          resources: request.resources, action: PermissionResponseAction.DENY),
      onWebViewCreated: (controller) {
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
                _fail();
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
                  _result.complete(value);
                  return null;
                }
                if (message['kind'] == 'call' &&
                    message['method'] is String &&
                    message['arguments'] is Map<String, dynamic>) {
                  final value = await onCall(message['method'] as String,
                      message['arguments'] as Map<String, dynamic>);
                  return _disposed ? null : {'value': value};
                }
                _fail();
              } catch (_) {
                // Never echo package exceptions, query text or host credentials.
                return {'error': 'Plugin request failed'};
              }
              return null;
            });
      },
      onLoadStop: (controller, _) {
        if (_disposed || _started) return;
        _started = true;
        final payload =
            jsonEncode({'source': source, 'input': input, 'handler': handler})
                .replaceAll('\u2028', r'\u2028')
                .replaceAll('\u2029', r'\u2029');
        unawaited(controller
            .evaluateJavascript(source: 'window.moduPluginStart($payload)')
            .catchError((_) {
          _fail();
          return null;
        }));
      },
      onLoadError: (_, __, ___, ____) => _fail(),
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
          .evaluateJavascript(source: 'if (window.moduPluginStop) window.moduPluginStop()')
          .catchError((_) => null));
    }
    await _view?.dispose();
  }
}
