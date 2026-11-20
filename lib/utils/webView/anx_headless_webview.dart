import 'dart:io';
import 'dart:async';

import 'package:modu_reader/main.dart';
import 'package:modu_reader/utils/log/common.dart';
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

  final URLRequest? initialUrlRequest;
  final InAppWebViewInitialData? initialData;
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
  final FutureOr<NavigationActionPolicy?> Function(
          InAppWebViewController controller, NavigationAction navigationAction)?
      shouldOverrideUrlLoading;
  final FutureOr<WebResourceResponse?> Function(
          InAppWebViewController controller, WebResourceRequest request)?
      shouldInterceptRequest;
  final FutureOr<bool?> Function(InAppWebViewController controller,
      CreateWindowAction createWindowAction)? onCreateWindow;
  final FutureOr<PermissionResponse?> Function(
          InAppWebViewController controller, PermissionRequest request)?
      onPermissionRequest;
  final WebViewEnvironment? webViewEnvironment;

  AnxHeadlessWebView({
    this.initialUrlRequest,
    this.initialData,
    this.initialSettings,
    this.onWebViewCreated,
    this.onLoadStop,
    this.onConsoleMessage,
    this.onLoadError,
    this.onLoadHttpError,
    this.shouldOverrideUrlLoading,
    this.shouldInterceptRequest,
    this.onCreateWindow,
    this.onPermissionRequest,
    this.webViewEnvironment,
  });

  // The HarmonyOS WebView fork requires a Future result for these callbacks.
  static Future<T> Function(A, B)? _asyncCallback<T, A, B>(
    FutureOr<T> Function(A, B)? callback,
  ) =>
      callback == null
          ? null
          : (first, second) async => callback(first, second);

  Future<void> run() {
    if (_stopping || _disposed) {
      return Future.error(StateError('Background reader is closing'));
    }
    // Assigned before the first await so concurrent callers share one attempt
    // and dispose() always has a future to wait on.
    return _running ??= _start();
  }

  Future<void> _start() async {
    // WebView2 tolerates only one create/destroy at a time. Instead of failing
    // outright while a previous view finishes releasing — which made a quick
    // second action, or a retry right after a failure, report "the previous
    // background reader is still closing" — wait for those disposals, bounded
    // so a stuck one cannot block forever.
    //
    // The wait only happens when there really is a disposal in flight: yielding
    // on every start would let a caller that disposes immediately race ahead of
    // creation and skip it entirely.
    if (hasPendingDisposal) await _awaitPendingDisposals();
    if (_stopping || _disposed) {
      throw StateError('Background reader is closing');
    }
    // No await between the check and the insert, so a concurrent dispose cannot
    // leave a disposed instance registered.
    _instances.add(this);
    try {
      await _run();
    } catch (_) {
      // A failed creation owns no native view, so it must not stay registered:
      // leaving it here would keep a dead view alive for the whole session.
      _instances.remove(this);
      rethrow;
    }
  }

  static bool get hasPendingDisposal {
    for (final view in _instances) {
      if (view._disposed) return true;
    }
    return false;
  }

  Future<void> _awaitPendingDisposals() async {
    final pending = [
      for (final view in _instances)
        if (view._disposed) view._disposing,
    ].whereType<Future<void>>().toList();
    if (pending.isEmpty) return;
    try {
      await Future.wait(pending).timeout(_creationGrace + _creationGrace);
    } catch (_) {
      // Falls through to the check below, which reports the real state.
    }
    if (hasPendingDisposal) {
      throw StateError('上一后台阅读器仍在释放，请稍后重试');
    }
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
      // Fail loudly instead of using the overlay path: creating a second native
      // window after a failed environment start races a late WebView2 callback,
      // and a silent overlay that renders nothing left callers waiting forever
      // for a load that could never happen.
      AnxLog.severe('AnxHeadlessWebView: WebView2 environment is unavailable');
      throw StateError('WebView2 环境不可用，请重试或重启应用');
    }

    if (useOverlay) {
      _runOverlay();
    } else {
      _headlessWebView = HeadlessInAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: initialUrlRequest,
        initialData: initialData,
        initialSettings: initialSettings,
        onWebViewCreated: onWebViewCreated,
        onLoadStop: onLoadStop,
        onConsoleMessage: onConsoleMessage,
        onReceivedError: _onReceivedError,
        onReceivedHttpError: _onReceivedHttpError,
        onRenderProcessGone: _onRenderProcessGone,
        shouldOverrideUrlLoading: _asyncCallback(shouldOverrideUrlLoading),
        shouldInterceptRequest: _asyncCallback(shouldInterceptRequest),
        onCreateWindow: _asyncCallback(onCreateWindow),
        onPermissionRequest: _asyncCallback(onPermissionRequest),
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

  void _onReceivedError(InAppWebViewController controller,
      WebResourceRequest request, WebResourceError error) {
    // Match the old page-load callbacks; failed images must not abort import.
    if (request.isForMainFrame == false) return;
    onLoadError?.call(controller, request.url, error.type.toNativeValue() ?? -1,
        error.description);
  }

  void _onRenderProcessGone(
      InAppWebViewController controller, RenderProcessGoneDetail detail) {
    if (_disposed) return;
    // Fail pending import/search immediately; release even if its owner throws.
    try {
      onLoadError?.call(controller, null, -1, 'WebView renderer stopped');
    } finally {
      unawaited(dispose());
    }
  }

  void _onReceivedHttpError(InAppWebViewController controller,
      WebResourceRequest request, WebResourceResponse response) {
    if (request.isForMainFrame == false) return;
    onLoadHttpError?.call(controller, request.url, response.statusCode ?? 0,
        response.reasonPhrase ?? '');
  }

  void _runOverlay() {
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Silently returning made run() succeed with no view at all, so every
      // caller waited for a load stop that never came.
      AnxLog.severe("No context available for AnxHeadlessWebView overlay");
      throw StateError('没有可用的界面上下文，后台阅读器无法启动');
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Offstage(
        offstage: true,
        child: SizedBox(
          width: 1,
          height: 1,
          child: InAppWebView(
            webViewEnvironment: webViewEnvironment,
            initialUrlRequest: initialUrlRequest,
            initialData: initialData,
            initialSettings: initialSettings,
            onLoadStop: onLoadStop,
            onConsoleMessage: onConsoleMessage,
            onReceivedError: _onReceivedError,
            onReceivedHttpError: _onReceivedHttpError,
            onRenderProcessGone: _onRenderProcessGone,
            shouldOverrideUrlLoading: _asyncCallback(shouldOverrideUrlLoading),
            shouldInterceptRequest: _asyncCallback(shouldInterceptRequest),
            onCreateWindow: _asyncCallback(onCreateWindow),
            onPermissionRequest: _asyncCallback(onPermissionRequest),
            onWebViewCreated: (controller) {
              onWebViewCreated?.call(controller);
            },
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  Future<void> dispose() {
    _disposed = true;
    return _disposing ??= _dispose();
  }

  /// How long dispose waits for a late native creation before giving up.
  ///
  /// A WebView2 environment that fails to initialise ("the device is not ready",
  /// 0x80070015) never completes run(), so without a bound this instance would
  /// stay in [_instances] marked disposed forever — and because [run] refuses to
  /// start while any disposed instance is still registered, every later
  /// background WebView would fail for the rest of the session.
  static const Duration _creationGrace = Duration(seconds: 5);

  Future<void> _dispose() async {
    try {
      // Windows plugin dispose is a no-op until run() has completed. Wait for
      // late creation before disposing; callers may bound their own wait, but
      // retain this instance until native cleanup really finishes.
      try {
        await _running?.timeout(_creationGrace);
      } catch (_) {
        // A failed or wedged creation may still have allocated a controller.
      }
      if (_headlessWebView != null) {
        await _headlessWebView?.dispose();
        _headlessWebView = null;
      }
      if (_overlayEntry != null) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      }
    } finally {
      // Always unregister, otherwise one failed dispose wedges every later
      // background WebView.
      _instances.remove(this);
    }
  }
}
