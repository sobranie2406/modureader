import 'dart:async';
import 'dart:io';
import 'package:anx_reader/service/sync/sync_preflight.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException responseError(int code) {
  final request = RequestOptions(path: '/synthetic');
  return DioException(
      requestOptions: request,
      response: Response(requestOptions: request, statusCode: code),
      type: DioExceptionType.badResponse);
}

void main() {
  test('automatic starts delay, coalesce, and yield to a manual request',
      () async {
    final timer = Completer<void>();
    final delays = <Duration>[];
    final gate = AutoSyncStartGate(delay: (duration) {
      delays.add(duration);
      return timer.future;
    });
    final first = gate.wait(() => true);
    expect(await gate.wait(() => true), isFalse);
    gate.invalidate(); // Manual synchronization starts immediately elsewhere.
    timer.complete();
    expect(await first, isFalse);
    expect(delays, [const Duration(seconds: 2)]);
  });

  test('quick background/resume replaces the stale timer without losing work',
      () async {
    final timers = <Completer<void>>[];
    final gate = AutoSyncStartGate(delay: (_) {
      final timer = Completer<void>();
      timers.add(timer);
      return timer.future;
    });
    final stale = gate.wait(() => true);
    gate.invalidate();
    final resumed = gate.wait(() => true);
    expect(timers, hasLength(2));
    timers[0].complete();
    expect(await stale, isFalse);
    // Finishing the stale timer must not release the new timer's guard.
    expect(await gate.wait(() => true), isFalse);
    timers[1].complete();
    expect(await resumed, isTrue);
  });

  test('disabled or background automatic work is not started', () async {
    var enabled = false;
    final timer = Completer<void>();
    final gate = AutoSyncStartGate(delay: (_) => timer.future);
    expect(await gate.wait(() => enabled), isFalse);
    enabled = true;
    final start = gate.wait(() => enabled);
    enabled = false;
    timer.complete();
    expect(await start, isFalse);
  });

  test('startup waits for the network before probing; retries are bounded',
      () async {
    var networkChecks = 0, probes = 0;
    final delays = <int>[];
    final preflight = SyncPreflight(delay: (duration) async {
      delays.add(duration.inSeconds);
    });
    expect(
        await preflight.run(
            automatic: true,
            enabled: () => true,
            networkReady: () async => ++networkChecks == 3,
            probe: () async {
              probes++;
            }),
        isTrue);
    expect(networkChecks, 3);
    expect(probes, 1);
    expect(delays, [2, 5]);
  });

  test('persistent offline ends after three checks, never calls the server',
      () async {
    var checks = 0, probes = 0;
    await expectLater(
        SyncPreflight(delay: (_) async {}).run(
            automatic: true,
            enabled: () => true,
            networkReady: () async {
              checks++;
              return false;
            },
            probe: () async {
              probes++;
            }),
        throwsA(isA<SyncNetworkUnavailable>()));
    expect(checks, 3);
    expect(probes, 0);
  });

  for (final code in [401, 403]) {
    test(
        'a transient HTTP $code is confirmed once without classifying it as offline',
        () async {
      var probes = 0;
      expect(
          await SyncPreflight(delay: (_) async {}).run(
              automatic: true,
              enabled: () => true,
              networkReady: () async => true,
              probe: () async {
                if (++probes == 1) throw responseError(code);
              }),
          isTrue);
      expect(probes, 2);
      expect(isTemporarySyncError(responseError(code)), isFalse);
    });
    test('persistent HTTP $code remains an auth error after one confirmation',
        () async {
      var probes = 0;
      await expectLater(
          SyncPreflight(delay: (_) async {}).run(
              automatic: true,
              enabled: () => true,
              networkReady: () async => true,
              probe: () async {
                probes++;
                throw responseError(code);
              }),
          throwsA(predicate(isSyncAuthError)));
      expect(probes, 2);
    });
  }

  test('manual failure is returned immediately without automatic retries',
      () async {
    var probes = 0;
    await expectLater(
        SyncPreflight(delay: (_) async {
          fail('Manual request delayed');
        }).run(
            automatic: false,
            enabled: () => true,
            networkReady: () async => true,
            probe: () async {
              probes++;
              throw responseError(503);
            }),
        throwsA(isA<DioException>()));
    expect(probes, 1);
  });

  test('leaving the foreground cancels backoff and prevents further probes',
      () async {
    var enabled = true, probes = 0;
    expect(
        await SyncPreflight(delay: (_) async {
          enabled = false;
        }).run(
            automatic: true,
            enabled: () => enabled,
            networkReady: () async => true,
            probe: () async {
              probes++;
              throw const SocketException('synthetic');
            }),
        isFalse);
    expect(probes, 1);
  });

  test(
      'certificate, conflict and ETag capability errors are not network failures',
      () {
    expect(
        isTemporarySyncError(DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.badCertificate)),
        isFalse);
    expect(isTemporarySyncError(responseError(412)), isFalse);
    expect(isTemporarySyncError(UnsupportedError('ETag')), isFalse);
    expect(isTemporarySyncError(responseError(503)), isTrue);
  });

  test('lifecycle sync wiring starts on resume rather than on pause', () {
    final source = File('lib/main.dart').readAsStringSync();
    final lifecycle = source.substring(
        source.indexOf('Future<void> didChangeAppLifecycleState'),
        source.indexOf('Widget build(BuildContext context)',
            source.indexOf('Future<void> didChangeAppLifecycleState')));
    final split = lifecycle.split('state == AppLifecycleState.resumed');
    expect(split.first, contains('pauseAutomaticSync()'));
    expect(split.first, isNot(contains('.syncData(')));
    expect(split.last, contains('.syncData('));
  });
}
