import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:modu_reader/service/dictionary/local_dictionary.dart';
import 'package:modu_reader/service/plugins/plugin_http_budget.dart';
import 'package:modu_reader/service/plugins/plugin_network_guard.dart';

/// Uses the validated address bytes while preserving the DNS name for TLS/SNI.
Future<ConnectionTask<Socket>> connectPluginTls({
  required PluginGuardResult target,
  required Duration timeout,
  required bool Function() isCancelled,
}) async {
  final pinned = target.addresses.first;
  if (pinned.host != target.uri.host) {
    throw const DictionaryFailure('configuration');
  }
  if (isCancelled()) throw const DictionaryFailure('cancelled');
  // HttpClient does not add TLS around a custom connectionFactory's socket.
  final task = await SecureSocket.startConnect(pinned, target.uri.port);
  final result = Completer<Socket>();
  SecureSocket? connected;
  var cancelled = false;
  Timer? timer;
  void abort(String code) {
    cancelled = true;
    task.cancel();
    connected?.destroy();
    timer?.cancel();
    if (!result.isCompleted) {
      result.completeError(DictionaryFailure(code));
    }
  }

  timer = Timer(timeout, () => abort('timeout'));
  task.socket.then<void>((secure) {
    connected = secure;
    if (cancelled || isCancelled()) {
      abort('cancelled');
      return;
    }
    final remote = secure.remoteAddress;
    final approved = target.addresses.any((address) =>
        address.address == remote.address && address.type == remote.type);
    if (!approved) {
      abort('configuration');
      return;
    }
    timer?.cancel();
    result.complete(secure);
  }, onError: (Object error, StackTrace stack) {
    timer?.cancel();
    if (!result.isCompleted) result.completeError(error, stack);
  });
  if (isCancelled()) abort('cancelled');
  return ConnectionTask.fromSocket(result.future, () => abort('cancelled'));
}

/// Performs the single GET a plugin source is allowed per lookup.
///
/// Everything is bounded: the response is streamed and cancelled as soon as it
/// exceeds the byte cap, redirects are refused, and the connection is made to an
/// address the guard already validated.
class PluginHttpClient {
  PluginHttpClient({
    HttpClient Function()? httpClientFactory,
    this.budget,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;

  /// Optional quota bookkeeping; null means no limits (tests only).
  final PluginHttpBudget? budget;

  /// Sends one request and returns the decoded body bytes.
  ///
  /// The returned bytes are **not** parsed: decoding and mapping belong to the
  /// caller, so a malformed document never reaches this layer's error paths.
  Future<Uint8List> get({
    required PluginGuardResult target,
    required Duration timeout,
    required int maxBytes,
    required String pluginId,
    CancelTokenLike? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const DictionaryFailure('cancelled');
    }
    budget?.acquire(pluginId);
    try {
      return await _get(
          target: target, timeout: timeout, maxBytes: maxBytes, cancel: cancel);
    } on DictionaryFailure {
      rethrow;
    } catch (_) {
      throw const DictionaryFailure('network');
    } finally {
      budget?.release(pluginId);
    }
  }

  Future<Uint8List> _get({
    required PluginGuardResult target,
    required Duration timeout,
    required int maxBytes,
    CancelTokenLike? cancel,
  }) async {
    final client = _httpClientFactory();
    final completer = Completer<Uint8List>();
    Timer? timer;
    var finished = false;

    void finish(FutureOr<void> Function() action) {
      if (finished) return;
      finished = true;
      timer?.cancel();
      action();
    }

    void fail(DictionaryFailure failure) {
      finish(() {
        if (!completer.isCompleted) completer.completeError(failure);
      });
    }

    // Pinning the connection to a validated address is what closes the
    // rebinding window: the name is resolved once, by the guard, and never
    // again by the HTTP stack.
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) => connectPluginTls(
        target: target,
        timeout: timeout,
        isCancelled: () => finished || (cancel?.isCancelled ?? false));

    timer = Timer(timeout, () {
      fail(const DictionaryFailure('timeout'));
      client.close(force: true);
    });

    cancel?.whenCancelled(() {
      finish(() {
        client.close(force: true);
        if (!completer.isCompleted) {
          completer.completeError(const DictionaryFailure('cancelled'));
        }
      });
    });

    () async {
      try {
        final request = await client.getUrl(target.uri);
        request.followRedirects = false;
        request.persistentConnection = false;
        // Host forces these; a manifest cannot set them.
        request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        target.headers.forEach(request.headers.set);

        final response = await request.close();
        final status = response.statusCode;
        if (status >= 300 && status < 400) {
          // Never read Location: a redirect is simply a failure.
          fail(const DictionaryFailure('network'));
          return;
        }
        if (status == 429) {
          fail(const DictionaryFailure('rateLimited'));
          return;
        }
        if (status < 200 || status >= 300) {
          fail(const DictionaryFailure('network'));
          return;
        }
        final declared = response.contentLength;
        if (declared > maxBytes) {
          fail(const DictionaryFailure('responseTooLarge'));
          return;
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response) {
          builder.add(chunk);
          if (builder.length > maxBytes) {
            fail(const DictionaryFailure('responseTooLarge'));
            return;
          }
        }
        finish(() {
          if (!completer.isCompleted) completer.complete(builder.takeBytes());
        });
      } on DictionaryFailure catch (failure) {
        fail(failure);
      } catch (_) {
        fail(const DictionaryFailure('network'));
      } finally {
        if (!finished) client.close(force: true);
      }
    }();

    try {
      return await completer.future;
    } finally {
      client.close(force: true);
    }
  }

  static const String _userAgent = 'ModuReader/1.2 (plugin dictionary source)';
}

/// Minimal cancellation hook, so this layer does not depend on Dio.
abstract class CancelTokenLike {
  void whenCancelled(void Function() callback);
  bool get isCancelled;
}

/// Synchronous implementation used by the lookup UI.
class PluginCancelToken implements CancelTokenLike {
  final _callbacks = <void Function()>[];
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in _callbacks) {
      callback();
    }
    _callbacks.clear();
  }

  @override
  void whenCancelled(void Function() callback) {
    if (_cancelled) {
      callback();
      return;
    }
    _callbacks.add(callback);
  }
}
