import 'dart:async';
import 'dart:isolate';
import 'package:anx_reader/service/knowledge/isolate_worker.dart';
import 'package:flutter_test/flutter_test.dart';

void _testWorker(List<Object?> args) async {
  var count = 0;
  await serveIsolateWorker(args[0] as SendPort, (method, value) async {
    switch (method) {
      case 'busy':
        final clock = Stopwatch()..start();
        while (clock.elapsedMilliseconds < 120) {
          count++;
        }
        return count;
      case 'slow':
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return ++count;
      case 'fail':
        throw StateError('test failure');
      case 'exit':
        Isolate.exit();
      case 'close':
        return count;
      default:
        return ++count;
    }
  });
}

void _failedStart(List<Object?> args) {
  throw StateError('startup failed');
}

void main() {
  test('CPU work does not starve owner event loop; worker reused across calls',
      () async {
    final worker = await IsolateWorker.start(_testWorker, null);
    addTearDown(worker.dispose);
    var ticks = 0;
    final timer =
        Timer.periodic(const Duration(milliseconds: 2), (_) => ticks++);
    final result = await worker.call('busy', null) as int;
    timer.cancel();
    expect(ticks, greaterThan(3));
    expect(await worker.call('next', null), result + 1);
    expect(await worker.call('close', null), result + 1);
  });

  test(
      'serial close follows active operation; errors do not hang or poison actor',
      () async {
    final worker = await IsolateWorker.start(_testWorker, null);
    addTearDown(worker.dispose);
    await expectLater(worker.call('fail', null), throwsStateError);
    final work = worker.call('slow', null);
    final close = worker.call('close', null);
    expect(await work, 1);
    expect(await close, 1);
  });

  test('unexpected worker exit fails pending requests instead of hanging',
      () async {
    final worker = await IsolateWorker.start(_testWorker, null);
    addTearDown(worker.dispose);
    await expectLater(
        worker.call('exit', null).timeout(const Duration(seconds: 3)),
        throwsStateError);
    await expectLater(worker.call('next', null), throwsStateError);
  });

  test('startup failure is reported', () async {
    await expectLater(
        IsolateWorker.start(_failedStart, null)
            .timeout(const Duration(seconds: 3)),
        throwsStateError);
  });

  test('unsendable data fails cleanly, subsequent calls still work', () async {
    final port = ReceivePort();
    addTearDown(port.close);
    await expectLater(
        IsolateWorker.start(_testWorker, port), throwsArgumentError);
    final worker = await IsolateWorker.start(_testWorker, null);
    addTearDown(worker.dispose);
    await expectLater(worker.call('next', port), throwsArgumentError);
    expect(await worker.call('next', null), 1);
    await worker.call('close', null);
  });
}
