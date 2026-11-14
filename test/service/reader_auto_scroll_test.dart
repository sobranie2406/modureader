import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/service/reader_auto_scroll.dart';

void main() {
  test('starts at the selected speed and stops only once', () async {
    final speeds = <double>[];
    var stops = 0;
    final controller = ReaderAutoScroll(
      startReader: (speed) async {
        speeds.add(speed);
        return true;
      },
      stopReader: () => stops++,
    );
    addTearDown(controller.dispose);

    expect(controller.speed, 1);
    expect(controller.active, isFalse);
    expect(controller.running, isFalse);
    final initialGeneration = controller.generation;
    controller.setSpeed(1.8);
    expect(controller.generation, initialGeneration);
    expect(await controller.start(), isTrue);
    final startedGeneration = controller.generation;
    expect(startedGeneration, greaterThan(initialGeneration));
    expect(controller.running, isTrue);
    expect(controller.active, isTrue);
    expect(await controller.start(), isFalse);
    expect(controller.generation, startedGeneration);
    expect(speeds, [1.8]);

    controller.stop();
    final stoppedGeneration = controller.generation;
    expect(stoppedGeneration, greaterThan(startedGeneration));
    controller.stop();
    expect(controller.generation, stoppedGeneration);
    expect(stops, 1);
    expect(controller.running, isFalse);
    expect(controller.active, isFalse);
    expect(await controller.start(), isTrue);
    expect(controller.generation, greaterThan(stoppedGeneration));
    expect(speeds, [1.8, 1.8]);
  });

  for (final throws in [false, true]) {
    test('cleans up a ${throws ? 'throwing' : 'rejected'} reader start',
        () async {
      var stops = 0;
      final controller = ReaderAutoScroll(
        startReader: (_) async {
          if (throws) throw StateError('Reader unavailable');
          return false;
        },
        stopReader: () => stops++,
      );
      addTearDown(controller.dispose);

      expect(await controller.start(), isFalse);
      expect(controller.running, isFalse);
      expect(controller.active, isFalse);
      expect(stops, 1);
      controller.stop();
      expect(stops, 1);
    });
  }

  test('stopping a pending start prevents its late result from restarting',
      () async {
    final pending = Completer<bool>();
    var starts = 0;
    var stops = 0;
    var changes = 0;
    var readerRunning = false;
    final controller = ReaderAutoScroll(
      startReader: (_) {
        starts++;
        return pending.future.then((started) {
          readerRunning = started;
          return started;
        });
      },
      stopReader: () {
        stops++;
        readerRunning = false;
      },
    )..addListener(() => changes++);
    addTearDown(controller.dispose);

    final started = controller.start();
    expect(controller.active, isTrue);
    expect(controller.running, isFalse);
    expect(await controller.start(), isFalse);
    expect(starts, 1);
    controller.stop();
    expect(stops, 1);
    expect(readerRunning, isFalse);
    final changesAfterStop = changes;
    pending.complete(true);

    expect(await started, isFalse);
    expect(controller.active, isFalse);
    expect(controller.running, isFalse);
    expect(stops, 2);
    expect(readerRunning, isFalse);
    expect(changes, changesAfterStop);
  });

  test('a previous pending start cannot overwrite a newer running session',
      () async {
    final pending = Completer<bool>();
    var starts = 0;
    var stops = 0;
    final controller = ReaderAutoScroll(
      startReader: (_) => ++starts == 1 ? pending.future : Future.value(true),
      stopReader: () => stops++,
    );
    addTearDown(controller.dispose);

    final first = controller.start();
    final previousGeneration = controller.generation;
    controller.stop();
    final stoppedGeneration = controller.generation;
    expect(stoppedGeneration, greaterThan(previousGeneration));
    expect(await controller.start(), isTrue);
    final currentGeneration = controller.generation;
    expect(currentGeneration, greaterThan(stoppedGeneration));
    pending.complete(true);

    expect(await first, isFalse);
    expect(controller.running, isTrue);
    expect(controller.active, isTrue);
    expect(stops, 1);
    expect(controller.generation, currentGeneration);
  });

  test('a stop reported by the reader does not send another stop back',
      () async {
    var stops = 0;
    final controller = ReaderAutoScroll(
      startReader: (_) async => true,
      stopReader: () => stops++,
    );
    addTearDown(controller.dispose);
    await controller.start();

    controller.stop(fromReader: true);
    controller.stop();
    expect(stops, 0);
    expect(controller.active, isFalse);
  });

  test('speed stays finite and within 0.1 to 4 in tenths', () async {
    final speeds = <double>[];
    final saved = <double>[];
    final controller = ReaderAutoScroll(
      startReader: (speed) async {
        speeds.add(speed);
        return true;
      },
      stopReader: () {},
      onSpeedChanged: saved.add,
    );
    addTearDown(controller.dispose);

    for (final (input, expected) in <(double, double)>[
      (-100, 0.1),
      (0.1, 0.1),
      (0.14, 0.1),
      (0.16, 0.2),
      (1.25, 1.3),
      (3.96, 4),
      (4, 4),
      (1000, 4),
    ]) {
      controller.setSpeed(input);
      expect(controller.speed, expected);
      expect(controller.speed.isFinite, isTrue);
    }
    for (final invalid in [
      double.nan,
      double.infinity,
      double.negativeInfinity
    ]) {
      controller.setSpeed(invalid);
      expect(controller.speed, 4);
    }
    expect(saved, [0.1, 0.1, 0.1, 0.2, 1.3, 4, 4, 4]);
    expect(await controller.start(), isTrue);
    expect(speeds, [4]);
  });

  test('initial speed is normalized without saving a preference', () {
    for (final (input, expected) in <(double, double)>[
      (double.nan, 1),
      (double.infinity, 1),
      (double.negativeInfinity, 1),
      (-10, 0.1),
      (2.24, 2.2),
      (10, 4),
    ]) {
      final saved = <double>[];
      final controller = ReaderAutoScroll(
        speed: input,
        startReader: (_) async => true,
        stopReader: () {},
        onSpeedChanged: saved.add,
      );
      expect(controller.speed, expected);
      expect(saved, isEmpty);
      controller.dispose();
    }
  });

  test('disposing a running controller stops the reader and rejects more work',
      () async {
    var stops = 0;
    var starts = 0;
    final controller = ReaderAutoScroll(
      startReader: (_) async {
        starts++;
        return true;
      },
      stopReader: () => stops++,
    );
    await controller.start();
    controller.dispose();

    controller.setSpeed(2);
    controller.stop();
    expect(await controller.start(), isFalse);
    expect(stops, 1);
    expect(starts, 1);
    expect(controller.speed, 1);
    expect(controller.active, isFalse);
  });

  test('disposing during start ignores late completion and notifications',
      () async {
    final pending = Completer<bool>();
    var stops = 0;
    var changes = 0;
    var readerRunning = false;
    final controller = ReaderAutoScroll(
      startReader: (_) => pending.future.then((started) {
        readerRunning = started;
        return started;
      }),
      stopReader: () {
        stops++;
        readerRunning = false;
      },
    )..addListener(() => changes++);
    final started = controller.start();

    controller.dispose();
    final changesAfterDispose = changes;
    pending.complete(true);
    expect(await started, isFalse);
    expect(stops, 2);
    expect(readerRunning, isFalse);
    expect(changes, changesAfterDispose);
    expect(controller.active, isFalse);
  });
}
