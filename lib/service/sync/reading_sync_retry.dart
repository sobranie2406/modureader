import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:anx_reader/service/sync/sync_preflight.dart';

bool syncNetworkAllowed(List<ConnectivityResult> connections,
        {required bool onlyWifi}) =>
    connections.any((value) => value != ConnectivityResult.none) &&
    (!onlyWifi || connections.contains(ConnectivityResult.wifi));

/// Retries a complete reconciliation, never a captured PUT/request body.
class ReadingSyncRetry {
  ReadingSyncRetry({SyncDelay? delay}) : _delay = delay;
  final SyncDelay? _delay;
  Timer? _timer;
  Completer<void>? _waiting;
  int _generation = 0;

  void cancel() {
    _generation++;
    _timer?.cancel();
    _waiting?.complete();
    _waiting = null;
  }

  Future<void> wait(Duration duration) async {
    if (duration <= Duration.zero) return;
    if (_delay != null) return _delay(duration);
    final waiting = Completer<void>();
    _waiting = waiting;
    _timer = Timer(duration, () {
      if (identical(_waiting, waiting)) _waiting = null;
      waiting.complete();
    });
    await waiting.future;
  }

  Future<bool> run({
    required bool Function() enabled,
    required bool Function() reading,
    required Future<bool> Function() networkReady,
    required Future<bool> Function() synchronize,
    Duration Function()? policyDelay,
  }) async {
    final generation = _generation;
    bool active() => generation == _generation && enabled();
    for (var attempt = 0;; attempt++) {
      if (!active()) return false;
      if (reading() && (!await networkReady() || !active())) return false;
      try {
        return await synchronize();
      } catch (error) {
        // A lost connection or changed Wi-Fi policy is a silent deferral.
        if (!active()) return false;
        if (reading() && (!await networkReady() || !active())) return false;
        if (!reading() || attempt == 3) rethrow;
        var duration = Duration(seconds: [2, 5, 10][attempt]);
        final serverDelay = syncRetryAfter(error);
        final providerDelay = policyDelay?.call() ?? Duration.zero;
        if (serverDelay > duration) duration = serverDelay;
        if (providerDelay > duration) duration = providerDelay;
        await wait(duration);
      }
    }
  }
}

/// Also honor S3's Retry-After; WebDAV adds its persisted account cooldown.
Duration syncRetryAfter(Object error) {
  if (error is! DioException ||
      ![429, 503].contains(error.response?.statusCode)) {
    return Duration.zero;
  }
  final header = error.response?.headers.value('retry-after');
  final seconds = int.tryParse(header ?? '');
  if (seconds != null) return Duration(seconds: seconds.clamp(1, 604800));
  try {
    if (header != null) {
      final remaining = HttpDate.parse(header).difference(DateTime.now());
      if (remaining > Duration.zero) return remaining;
    }
  } catch (_) {}
  return const Duration(minutes: 1);
}

/// One notice per continuous reading failure, reset only by successful sync.
class ReadingSyncFeedback {
  bool _failureShown = false;
  void reset() => _failureShown = false;
  bool success({required bool reading, required bool enabled}) {
    reset();
    return enabled && !reading;
  }

  bool failure({required bool reading}) {
    if (!reading) return true;
    if (_failureShown) return false;
    _failureShown = true;
    return true;
  }
}
