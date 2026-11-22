import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Creates and owns the single Windows WebView2 environment.
///
/// Two rules matter here, and both come from real failures:
///
/// * The environment is created **once** and must never be created twice. A
///   second `CreateCoreWebView2EnvironmentWithOptions` call for the same user
///   data folder can fail with `ERROR_NOT_READY` (`0x80070015`) while the first
///   browser process is still starting.
/// * A failure is **retryable**. The previous code created the environment
///   inside a post-frame callback with no `catch`, so a single failure left the
///   global `webViewEnvironment` null for the rest of the session and every
///   background WebView (plugins, article capture, book import, AI search)
///   failed until the app restarted.
///
/// The profile folder lives next to the application's own data rather than in
/// `%TEMP%`: temporary folders are cleaned by the OS and by disk-cleanup tools,
/// and a profile directory that disappears mid-session is one of the ways the
/// browser process ends up refusing to start.
class WebViewEnvironmentBoot {
  WebViewEnvironmentBoot._();

  static final WebViewEnvironmentBoot instance = WebViewEnvironmentBoot._();

  /// Do not hammer the browser process after a hard failure.
  static const Duration _retryCooldown = Duration(seconds: 10);

  WebViewEnvironment? _environment;
  Future<WebViewEnvironment?>? _pending;

  /// A test-supplied environment, so engine and runtime tests do not need a
  /// real WebView2 install. Never set from application code.
  WebViewEnvironment? _override;

  /// Replaces the environment for the duration of a test. Pass null to clear.
  void debugSetEnvironment(WebViewEnvironment? environment) {
    _override = environment;
  }

  String? _lastError;
  DateTime? _failedAt;

  /// Null until [ensure] succeeds at least once.
  WebViewEnvironment? get environment => _override ?? _environment;

  /// True when the platform has a usable WebView2 runtime.
  bool get isSupported => _platformNeedsEnvironment;

  /// Last failure, for diagnostics only. Never contains user content.
  String? get lastError => _lastError;

  static bool get _platformNeedsEnvironment {
    try {
      return AnxPlatform.isWindows;
    } catch (_) {
      return false;
    }
  }

  /// Returns the environment, creating it if needed.
  ///
  /// Concurrent callers share one in-flight attempt, so a burst of plugin runs
  /// cannot start several environments at once. Pass [force] to ignore the
  /// cooldown after a reported failure (the viewer-facing retry button).
  Future<WebViewEnvironment?> ensure({bool force = false}) {
    if (!_platformNeedsEnvironment) return Future.value(null);
    final override = _override;
    if (override != null) return Future.value(override);
    final ready = _environment;
    if (ready != null) return Future.value(ready);
    final failedAt = _failedAt;
    if (!force &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < _retryCooldown) {
      return Future.value(null);
    }
    return _pending ??= _create().whenComplete(() => _pending = null);
  }

  Future<WebViewEnvironment?> _create() async {
    try {
      final available = await WebViewEnvironment.getAvailableVersion();
      if (available == null) {
        _fail('WebView2 runtime is not installed');
        return null;
      }
      final folder = await _profileDirectory();
      final created = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: folder.path),
      );
      _environment = created;
      _lastError = null;
      _failedAt = null;
      AnxLog.info('WebView2 environment ready: $available');
      return created;
    } catch (error) {
      // A previous profile can be left behind by a crashed browser process.
      // Retrying once with a clean folder is cheap and fixes the common case.
      try {
        final folder = await _profileDirectory();
        if (await folder.exists()) {
          await folder.rename('${folder.path}-broken-'
              '${DateTime.now().millisecondsSinceEpoch}');
        }
        final created = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
              userDataFolder: (await _profileDirectory()).path),
        );
        _environment = created;
        _lastError = null;
        _failedAt = null;
        AnxLog.info('WebView2 environment ready after profile reset');
        return created;
      } catch (retryError) {
        _fail(_describe(retryError));
        return null;
      }
    }
  }

  Future<Directory> _profileDirectory() async {
    final support = await getApplicationSupportDirectory();
    final folder = Directory(p.join(support.path, 'webview2-profile'));
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  // Native messages can contain the user's profile directory.
  static String _describe(Object error) => error.runtimeType.toString();

  void _fail(String message) {
    _lastError = message;
    _failedAt = DateTime.now();
    _environment = null;
    AnxLog.severe('WebView2 environment unavailable: $message');
  }

  /// Releases the environment. Only safe once every native view is gone.
  Future<void> dispose() async {
    final current = _environment;
    _environment = null;
    if (current == null) return;
    try {
      await current.dispose();
    } catch (error) {
      AnxLog.warning(
          'Could not dispose WebView2 environment: ${_describe(error)}');
    }
  }
}
