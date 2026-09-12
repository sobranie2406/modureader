import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

typedef SyncDelay = Future<void> Function(Duration);

class SyncNetworkUnavailable implements Exception {}

bool isTemporarySyncError(Object error) {
  if (error is SyncNetworkUnavailable ||
      error is SocketException ||
      error is TimeoutException) return true;
  if (error is! DioException) return false;
  if ([
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout
  ].contains(error.type)) return true;
  return [408, 429, 500, 502, 503, 504].contains(error.response?.statusCode);
}

bool isSyncAuthError(Object error) =>
    error is DioException && [401, 403].contains(error.response?.statusCode);

/// Delays/coalesces automatic starts without holding the transfer lock.
/// A manual request or leaving the foreground invalidates a pending start.
class AutoSyncStartGate {
  AutoSyncStartGate({SyncDelay? delay})
      : _delay = delay ?? Future<void>.delayed;
  final SyncDelay _delay;
  int _generation = 0;
  int? _pendingGeneration;
  int get generation => _generation;
  void invalidate() {
    _generation++;
    _pendingGeneration = null;
  }

  Future<bool> wait(bool Function() enabled) async {
    if (_pendingGeneration != null || !enabled()) return false;
    final generation = _generation;
    _pendingGeneration = generation;
    try {
      await _delay(const Duration(seconds: 2));
      return generation == _generation && enabled();
    } finally {
      if (_pendingGeneration == generation) _pendingGeneration = null;
    }
  }
}

/// Retries ONLY the read-only connection probe. Never retries a database PUT
/// or a partly completed synchronization as an unconditional upload.
class SyncPreflight {
  SyncPreflight({SyncDelay? delay}) : _delay = delay ?? Future<void>.delayed;
  final SyncDelay _delay;
  Future<bool> run(
      {required bool automatic,
      required bool Function() enabled,
      required Future<bool> Function() networkReady,
      required Future<void> Function() probe}) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!enabled()) return false;
      try {
        if (!await networkReady()) throw SyncNetworkUnavailable();
        if (!enabled()) return false;
        await probe();
        return enabled();
      } catch (error) {
        if (!enabled()) return false;
        // Confirm a startup auth rejection once; do not label it "offline"
        // or repeatedly hammer a server with invalid credentials.
        final retry = automatic &&
            attempt < 2 &&
            (isTemporarySyncError(error) ||
                (attempt == 0 && isSyncAuthError(error)));
        if (!retry) rethrow;
        await _delay(Duration(seconds: attempt == 0 ? 2 : 5));
      }
    }
    return false;
  }
}
