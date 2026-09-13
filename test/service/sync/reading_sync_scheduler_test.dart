import 'dart:async';
import 'package:anx_reader/service/sync/reading_sync_scheduler.dart';
import 'package:anx_reader/service/sync/sync_preflight.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final minutes in readingSyncIntervals) {
    test('waits the complete $minutes minute interval and repeats', () {
      fakeAsync((clock) {
        var calls = 0;
        final scheduler = ReadingSyncScheduler(
            sync: (_) async {
              calls++;
            },
            onError: (_, __) {});
        scheduler.update(
            enabled: true,
            foreground: true,
            readingVisible: true,
            minutes: minutes);
        clock.elapse(
            Duration(minutes: minutes) - const Duration(milliseconds: 1));
        expect(calls, 0);
        clock.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);
        clock.elapse(Duration(minutes: minutes));
        expect(calls, 2);
        scheduler.dispose();
        clock.elapse(const Duration(hours: 2));
        expect(calls, 2);
      });
    });
  }
  for (final disabled in ['setting', 'background', 'other page']) {
    test('$disabled pauses and resume waits a full interval without catch-up',
        () {
      fakeAsync((clock) {
        var calls = 0;
        final s = ReadingSyncScheduler(
            sync: (_) async {
              calls++;
            },
            onError: (_, __) {});
        s.update(
            enabled: true, foreground: true, readingVisible: true, minutes: 1);
        clock.elapse(const Duration(seconds: 45));
        s.update(
            enabled: disabled != 'setting',
            foreground: disabled != 'background',
            readingVisible: disabled != 'other page',
            minutes: 1);
        clock.elapse(const Duration(hours: 8));
        expect(calls, 0);
        s.update(
            enabled: true, foreground: true, readingVisible: true, minutes: 1);
        clock.elapse(const Duration(seconds: 59));
        expect(calls, 0);
        clock.elapse(const Duration(seconds: 1));
        expect(calls, 1);
        s.dispose();
      });
    });
  }
  test(
      'preference notifications do not reset the countdown; interval changes do',
      () {
    fakeAsync((clock) {
      var calls = 0;
      final s = ReadingSyncScheduler(
          sync: (_) async {
            calls++;
          },
          onError: (_, __) {});
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 1);
      clock.elapse(const Duration(seconds: 30));
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 1);
      clock.elapse(const Duration(seconds: 30));
      expect(calls, 1);
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 3);
      clock.elapse(const Duration(minutes: 2));
      expect(calls, 1);
      clock.elapse(const Duration(minutes: 1));
      expect(calls, 2);
      s.dispose();
    });
  });
  test(
      'a slow sync never overlaps; settings changed while running take effect afterward',
      () {
    fakeAsync((clock) {
      var calls = 0;
      final completer = Completer<void>();
      final s = ReadingSyncScheduler(
          sync: (_) {
            calls++;
            return completer.future;
          },
          onError: (_, __) {});
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 1);
      clock.elapse(const Duration(minutes: 10));
      expect(calls, 1);
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 2);
      completer.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 119));
      expect(calls, 1);
      clock.elapse(const Duration(seconds: 1));
      expect(calls, 2);
      s.dispose();
    });
  });
  test(
      'leaving during delayed preflight invalidates the captured request even after resume',
      () {
    fakeAsync((clock) {
      var uploads = 0;
      final s = ReadingSyncScheduler(
          sync: (allowed) async {
            final ready = await SyncPreflight().run(
                automatic: true,
                enabled: allowed,
                networkReady: () async => true,
                probe: () => Future<void>.delayed(const Duration(seconds: 5)));
            if (ready && allowed()) uploads++;
          },
          onError: (_, __) {});
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 1);
      clock.elapse(const Duration(seconds: 61));
      s.update(
          enabled: true, foreground: false, readingVisible: true, minutes: 1);
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 1);
      clock.elapse(const Duration(seconds: 5));
      expect(uploads, 0);
      clock.elapse(const Duration(seconds: 65));
      expect(uploads, 1);
      s.dispose();
    });
  });
  test('failure is contained and next interval remains scheduled', () {
    fakeAsync((clock) {
      var calls = 0, errors = 0;
      final s = ReadingSyncScheduler(sync: (_) async {
        calls++;
        throw StateError('synthetic');
      }, onError: (_, __) {
        errors++;
      });
      s.update(
          enabled: true, foreground: true, readingVisible: true, minutes: 1);
      clock.elapse(const Duration(minutes: 2));
      expect(calls, 2);
      expect(errors, 2);
      s.dispose();
    });
  });
}
