import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/dictionary/local_dictionary.dart';
import 'package:anx_reader/service/plugins/plugin_http_budget.dart';
import 'package:anx_reader/service/plugins/plugin_network_guard.dart';

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
    if (budget != null) budget!.acquire(pluginId);

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
    final pinned = target.addresses.first;
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final socket = await Socket.connect(pinned, uri.port,
          timeout: timeout);
      // Independent second check after connect: whatever answered must be one
      // of the addresses the guard approved. A proxy or a hijacked route that
      // landed somewhere else is refused here rather than trusted.
      final remote = socket.remoteAddress;
      final approved = target.addresses.any((address) =>
          address.address == remote.address && address.type == remote.type);
      if (!approved) {
        socket.destroy();
        throw const DictionaryFailure('configuration');
      }
      return ConnectionTask.fromSocket(Future.value(socket), () {
        socket.destroy();
      });
    };

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
          await response.drain<void>();
          fail(const DictionaryFailure('network'));
          return;
        }
        if (status == 429) {
          await response.drain<void>();
          fail(const DictionaryFailure('rateLimited'));
          return;
        }
        if (status < 200 || status >= 300) {
          await response.drain<void>();
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
      budget?.release(pluginId);
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