import 'dart:io';
import 'dart:async';

import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class AnxHeadlessWebView {
  static final _instances = <AnxHeadlessWebView>{};
  static bool _stopping = false;
  Future<void>? _running;
  Future<void>? _disposing;
  bool _disposed = false;

  static Future<void> disposeAll() async {
    _stopping = true;
    await Future.wait(_instances.toList().map((view) => view.dispose()));
  }

  static void resumeAccepting() => _stopping = false;
  HeadlessInAppWebView? _headlessWebView;
  OverlayEntry? _overlayEntry;

  final URLRequest initialUrlRequest;
  final InAppWebViewSettings? initialSettings;
  final void Function(InAppWebViewController controller)? onWebViewCreated;
  final void Function(InAppWebViewController controller, Uri? url)? onLoadStop;
  final void Function(
          InAppWebViewController controller, ConsoleMessage consoleMessage)?
      onConsoleMessage;
  final void Function(InAppWebViewController controller, Uri? url, int code,
      String message)? onLoadError;
  final void Function(InAppWebViewController controller, Uri? url,
      int statusCode, String description)? onLoadHttpError;
  final WebViewEnvironment? webViewEnvironment;

  AnxHeadlessWebView({
    required this.initialUrlRequest,
    this.initialSettings,
    this.onWebViewCreated,
    this.onLoadStop,
    this.onConsoleMessage,
    this.onLoadError,
    this.onLoadHttpError,
    this.webViewEnvironment,
  });

  Future<void> run() {
    if (_stopping || _disposed) {
      return Future.error(StateError('Background reader is closing'));
    }
    if (Platform.isWindows && _instances.any((view) => view._disposed)) {
      return Future.error(StateError('上一后台阅读器仍在释放，请稍后重试'));
    }
    _instances.add(this);
    return _running ??= _run();
  }

  Future<void> _run() async {
    bool useOverlay = false;
    try {
      if (Platform.operatingSystem == 'ohos') {
        useOverlay = true;
      }
    } catch (e) {
      // ignore
    }

    if (Platform.isWindows && webViewEnvironment == null) {
      AnxLog.severe(
          'AnxHeadlessWebView: webViewEnvironment is null on Windows, falling back to Overlay');
      _runOverlay();
      return;
    }

    if (useOverlay) {
      _runOverlay();
    } else {
      _headlessWebView = HeadlessInAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: initialUrlRequest,
        initialSettings: initialSettings,
        onWebViewCreated: onWebViewCreated,
        onLoadStop: onLoadStop,
        onConsoleMessage: onConsoleMessage,
        onLoadError: onLoadError,
        onLoadHttpError: onLoadHttpError,
      );
      try {
        await _headlessWebView?.run();
      } catch (e) {
        // Creating a second Windows native view after a failed creation can
        // race a late WebView2 callback. Surface the failure instead.
        if (Platform.isWindows || _disposed) rethrow;
        AnxLog.info(
            "HeadlessInAppWebView failed to run, falling back to Overlay: $e");
        _headlessWebView = null;
        _runOverlay();
      }
    }
  }

  void _runOverlay() {
    final context = navigatorKey.currentContext;
    if (context == null) {
      AnxLog.severe("No context available for AnxHeadlessWebView overlay");
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Offstage(
        offstage: true,
        child: SizedBox(
          width: 1,
          height: 1,
          child: InAppWebView(
            initialUrlRequest: initialUrlRequest,
            initialSettings: initialSettings,
            onLoadStop: onLoadStop,
            onConsoleMessage: onConsoleMessage,
            onLoadError: onLoadError,
            onLoadHttpError: onLoadHttpError,
            onWebViewCreated: (controller) {
              onWebViewCreated?.call(controller);
            },
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  Future<void> dispose() {
    _disposed = true;
    return _disposing ??= _dispose();
  }

  Future<void> _dispose() async {
    // Windows plugin dispose is a no-op until run() has completed. Wait for
    // late creation before disposing; callers may bound their own wait, but
    // retain this instance until native cleanup really finishes.
    try {
      await _running;
    } catch (_) {
      // A failed creation may still have allocated a native controller.
    }
    if (_headlessWebView != null) {
      await _headlessWebView?.dispose();
      _headlessWebView = null;
    }
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
    _instances.remove(this);
  }
}
