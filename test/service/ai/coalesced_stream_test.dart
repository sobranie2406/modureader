import 'dart:async';
import 'package:anx_reader/service/ai/coalesced_stream.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first snapshot is immediate and bursts retain only the latest text',
      () {
    fakeAsync((clock) {
      final source = StreamController<String>();
      final received = <String>[];
      coalesceSnapshots(source.stream).listen(received.add);
      source.add('a');
      clock.flushMicrotasks();
      expect(received, ['a']);
      for (var i = 2; i <= 100; i++) {
        source.add('a' * i);
      }
      clock.flushMicrotasks();
      expect(received, hasLength(1));
      clock.elapse(const Duration(milliseconds: 80));
      expect(received, ['a', 'a' * 100]);
      source.close();
      clock.flushMicrotasks();
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('completion flushes final snapshot without waiting for the timer',
      () async {
    expect(
        await coalesceSnapshots(Stream.fromIterable(['a', 'ab', 'abc']))
            .toList(),
        ['a', 'abc']);
  });

  test('error is preceded by pending content and preserves error identity',
      () async {
    final source = StreamController<String>();
    final events = <Object>[];
    final finished = Completer<void>();
    final error = StateError('fixture');
    coalesceSnapshots(source.stream)
        .listen(events.add, onError: events.add, onDone: finished.complete);
    source.add('a');
    source.add('ab');
    source.addError(error);
    source.close();
    await finished.future;
    expect(events, ['a', 'ab', same(error)]);
  });

  test('cancel discards pending snapshots and cancels source and timer', () {
    fakeAsync((clock) {
      var cancelled = false;
      final source = StreamController<int>(onCancel: () => cancelled = true);
      final received = <int>[];
      final subscription =
          coalesceSnapshots(source.stream).listen(received.add);
      source.add(1);
      source.add(2);
      clock.flushMicrotasks();
      subscription.cancel();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(received, [1]);
      expect(cancelled, true);
      expect(clock.nonPeriodicTimerCount, 0);
      source.close();
      clock.flushMicrotasks();
    });
  });

  test('empty streams complete without synthesizing text', () async {
    expect(await coalesceSnapshots(const Stream<String>.empty()).toList(),
        isEmpty);
  });
}
