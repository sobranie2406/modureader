import 'dart:async';
import 'package:anx_reader/service/sync/reading_sync_retry.dart';
import 'package:anx_reader/service/sync/sync_feedback.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException failure(int status) {
  final request = RequestOptions(path: '/private-book?key=secret');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: status),
  );
}

void main() {
  for (final (network, wifiOnly, allowed) in [
    (<ConnectivityResult>[], false, false),
    ([ConnectivityResult.none], false, false),
    ([ConnectivityResult.wifi], false, true),
    ([ConnectivityResult.wifi], true, true),
    ([ConnectivityResult.mobile], false, true),
    ([ConnectivityResult.mobile], true, false),
    ([ConnectivityResult.ethernet], false, true),
    ([ConnectivityResult.vpn, ConnectivityResult.wifi], true, true),
    ([ConnectivityResult.vpn], true, false),
  ]) {
    test('network=$network, Wi-Fi-only=$wifiOnly -> $allowed', () {
      expect(syncNetworkAllowed(network, onlyWifi: wifiOnly), allowed);
    });
  }

  for (final status in [401, 405, 500]) {
    test('reader retries the reconciliation three times then reports $status',
        () async {
      var calls = 0;
      final delays = <int>[];
      final error = failure(status);
      final runner = ReadingSyncRetry(delay: (duration) async {
        delays.add(duration.inSeconds);
      });
      await expectLater(
          runner.run(
            enabled: () => true,
            reading: () => true,
            networkReady: () async => true,
            synchronize: () async {
              calls++;
              throw error;
            },
          ),
          throwsA(same(error)));
      expect(calls, 4);
      expect(delays, [2, 5, 10]);
      final message = syncFailureMessage(error, chinese: true);
      expect(message, contains('HTTP $status'));
      expect(message, isNot(contains('secret')));
    });
  }

  test('success during a retry stops the cycle without a failure', () async {
    var calls = 0;
    expect(
        await ReadingSyncRetry(delay: (_) async {}).run(
          enabled: () => true,
          reading: () => true,
          networkReady: () async => true,
          synchronize: () async {
            if (++calls < 3) throw failure(500);
            return true;
          },
        ),
        true);
    expect(calls, 3);
  });

  test('offline and Wi-Fi-only failures do not attempt any synchronization',
      () async {
    for (final network in [
      [ConnectivityResult.none],
      [ConnectivityResult.mobile]
    ]) {
      expect(
          await ReadingSyncRetry().run(
            enabled: () => true,
            reading: () => true,
            networkReady: () async =>
                syncNetworkAllowed(network, onlyWifi: true),
            synchronize: () async {
              fail('Must not contact the server');
            },
          ),
          false);
    }
  });

  test('network lost during upload defers without a failure notice', () async {
    var connected = true, calls = 0;
    expect(
        await ReadingSyncRetry().run(
          enabled: () => true,
          reading: () => true,
          networkReady: () async => connected,
          synchronize: () async {
            calls++;
            connected = false;
            throw failure(500);
          },
        ),
        false);
    expect(calls, 1);
  });

  test('changed network policy during backoff prevents a second attempt',
      () async {
    var allowed = true, calls = 0;
    expect(
        await ReadingSyncRetry(delay: (_) async {
          allowed = false;
        }).run(
          enabled: () => true,
          reading: () => true,
          networkReady: () async => allowed,
          synchronize: () async {
            calls++;
            throw failure(500);
          },
        ),
        false);
    expect(calls, 1);
  });

  test('leaving foreground/account change cancels the retry', () async {
    var enabled = true, calls = 0;
    expect(
        await ReadingSyncRetry(delay: (_) async {
          enabled = false;
        }).run(
          enabled: () => enabled,
          reading: () => true,
          networkReady: () async => true,
          synchronize: () async {
            calls++;
            throw failure(500);
          },
        ),
        false);
    expect(calls, 1);
  });

  test('pause cancels a long cooldown without waiting for its timer', () async {
    final runner = ReadingSyncRetry();
    var calls = 0;
    final first = Completer<void>();
    final result = runner.run(
      enabled: () => true,
      reading: () => true,
      networkReady: () async => true,
      policyDelay: () => const Duration(hours: 1),
      synchronize: () async {
        calls++;
        first.complete();
        throw failure(503);
      },
    );
    await first.future;
    await Future<void>.delayed(Duration.zero);
    runner.cancel();
    expect(await result.timeout(const Duration(seconds: 1)), false);
    expect(calls, 1);
  });

  test('server and account cooldowns are respected before every retry',
      () async {
    final error = failure(429);
    error.response!.headers.set('retry-after', '90');
    var calls = 0;
    final delays = <Duration>[];
    await expectLater(
        ReadingSyncRetry(delay: (duration) async {
          delays.add(duration);
        }).run(
          enabled: () => true,
          reading: () => true,
          networkReady: () async => true,
          policyDelay: () => const Duration(minutes: 10),
          synchronize: () async {
            calls++;
            throw error;
          },
        ),
        throwsA(same(error)));
    expect(calls, 4);
    expect(delays, List.filled(3, const Duration(minutes: 10)));
    expect(syncRetryAfter(error), const Duration(seconds: 90));
  });

  test('non-reader network failures retain the existing feedback path',
      () async {
    final error = failure(500);
    var calls = 0;
    await expectLater(
      ReadingSyncRetry().run(
        enabled: () => true,
        reading: () => false,
        networkReady: () async => false,
        synchronize: () async {
          calls++;
          throw error;
        },
      ),
      throwsA(same(error)),
    );
    expect(calls, 1);
    final feedback = ReadingSyncFeedback();
    expect(feedback.failure(reading: true), true);
    expect(feedback.failure(reading: true), false);
    expect(feedback.failure(reading: false), true);
    expect(feedback.failure(reading: false), true);
  });

  test('non-reader failure retains its existing immediate feedback path',
      () async {
    var calls = 0;
    await expectLater(
        ReadingSyncRetry(delay: (_) async {
          fail('No retry');
        }).run(
          enabled: () => true,
          reading: () => false,
          networkReady: () async => true,
          synchronize: () async {
            calls++;
            throw failure(405);
          },
        ),
        throwsA(isA<DioException>()));
    expect(calls, 1);
  });

  test(
      'reading success is silent; repeated failures notify once until recovery',
      () {
    final feedback = ReadingSyncFeedback();
    expect(feedback.success(reading: true, enabled: true), false);
    expect(feedback.failure(reading: true), true);
    expect(feedback.failure(reading: true), false);
    expect(feedback.failure(reading: true), false);
    expect(feedback.success(reading: true, enabled: false), false);
    expect(feedback.failure(reading: true), true);
    expect(feedback.success(reading: false, enabled: true), true);
    expect(feedback.success(reading: false, enabled: false), false);
  });
}
