import 'dart:async';

import 'package:anx_reader/service/tts/tts_reader_wait.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));

  test('slow background call reports the wait and foreground settlement once',
      () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final reply = Completer<String>();
    final reported = Completer<void>();
    final logs = <String>[];
    var calls = 0;
    final result = waitForTtsReader(
        'next',
        () {
          calls++;
          return reply.future;
        },
        reportAfter: const Duration(milliseconds: 1),
        report: (line) {
          logs.add(line);
          if (!reported.isCompleted) reported.complete();
        });
    await reported.future.timeout(const Duration(seconds: 1));
    expect(logs.single, contains('next waiting; lifecycle=paused'));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    reply.complete('private book text');
    expect(await result, 'private book text');
    expect(calls, 1); // Never repeat a cursor mutation on a diagnostic timer.
    expect(logs, hasLength(2));
    expect(logs.last, contains('next settled; lifecycle=resumed'));
    expect(logs.join(), isNot(contains('private book text')));
  });

  test('fast calls cancel the diagnostic timer and retain the original error',
      () async {
    final logs = <String>[];
    expect(
        await waitForTtsReader('next', () async => 'next',
            reportAfter: const Duration(milliseconds: 1), report: logs.add),
        'next');
    final error = StateError('private failure detail');
    await expectLater(
        waitForTtsReader('next', () async => throw error,
            reportAfter: const Duration(milliseconds: 1), report: logs.add),
        throwsA(same(error)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(logs, isEmpty);
  });

  test('failed diagnostic logging cannot interrupt a delayed reader result',
      () async {
    final result = waitForTtsReader('next', () async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return 'next';
    },
        reportAfter: const Duration(milliseconds: 1),
        report: (_) => throw StateError('logger'));
    expect(await result, 'next');
  });
}
