import 'dart:async';
import 'package:anx_reader/service/eink_refresh.dart';
import 'package:anx_reader/service/config_transfer/settings_value_validation.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/eink_refresh');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('missing native support returns false; does not fake a repaint',
      () async {
    final bridge = EinkRefresh(channel: channel);
    expect(await bridge.supported, isFalse);
    expect(await bridge.refresh(), isFalse);
  });
  test('probe cached, refresh invokes one-shot API on every request', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    final bridge = EinkRefresh(channel: channel);
    expect(await bridge.supported, isTrue);
    expect(await bridge.refresh(), isTrue);
    expect(await bridge.refresh(), isTrue);
    expect(calls, ['supported', 'refresh', 'refresh']);
  });
  test('OEM rejection and platform errors are not reported as success',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'supported') return true;
      throw PlatformException(code: 'restricted');
    });
    expect(await EinkRefresh(channel: channel).refresh(), isFalse);
    messenger.setMockMethodCallHandler(
        channel, (call) async => call.method == 'supported');
    expect(await EinkRefresh(channel: channel).refresh(), isFalse);
  });

  test('turning mode off during capability probe cancels refresh', () async {
    final probe = Completer<bool>();
    var enabled = true;
    var refreshes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'supported') return probe.future;
      refreshes++;
      return true;
    });
    final result =
        EinkRefresh(channel: channel).refresh(canRefresh: () => enabled);
    enabled = false;
    probe.complete(true);
    expect(await result, isFalse);
    expect(refreshes, 0);
  });

  test('automatic refresh is off by default', () {
    fakeAsync((time) {
      var calls = 0;
      final scheduler = EinkPageRefreshScheduler(() async {
        calls++;
        return true;
      });
      for (var p = 0; p < 200; p++) {
        scheduler.observe(p, readingAction: true);
      }
      time.elapse(const Duration(seconds: 1));
      expect(calls, 0);
      scheduler.dispose();
    });
  });
  test(
      'counts original-page transitions, not initial load, panels or style changes',
      () {
    fakeAsync((time) {
      var calls = 0;
      final scheduler = EinkPageRefreshScheduler(() async {
        calls++;
        return true;
      });
      scheduler.configure(active: true, interval: 2);
      scheduler.observe(0, readingAction: true);
      scheduler.observe(0, readingAction: true); // another panel
      scheduler.observe(1, readingAction: false); // synchronization/reflow
      scheduler.observe(2, readingAction: true);
      time.elapse(const Duration(seconds: 1));
      expect(calls, 0);
      scheduler.observe(3, readingAction: true);
      time.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      scheduler.observe(4, readingAction: true);
      scheduler.observe(5, readingAction: true);
      time.elapse(const Duration(seconds: 1));
      expect(calls, 2);
      scheduler.dispose();
    });
  });
  test('rapid turns coalesce and a chapter/page jump counts as one transition',
      () {
    fakeAsync((time) {
      var calls = 0;
      final scheduler = EinkPageRefreshScheduler(() async {
        calls++;
        return true;
      });
      scheduler.configure(active: true, interval: 2);
      scheduler.observe(0, readingAction: false);
      scheduler.observe(50, readingAction: true);
      time.elapse(const Duration(seconds: 1));
      expect(calls, 0);
      for (var p = 51; p < 58; p++) {
        scheduler.observe(p, readingAction: true);
        time.elapse(const Duration(milliseconds: 100));
      }
      expect(calls, 0);
      time.elapse(const Duration(seconds: 1));
      expect(calls, 1);
      scheduler.dispose();
    });
  });
  for (final action in ['inactive', 'off', 'dispose', 'manual', 'interval']) {
    test('$action cancels pending auto refresh', () {
      fakeAsync((time) {
        var calls = 0;
        final scheduler = EinkPageRefreshScheduler(() async {
          calls++;
          return true;
        });
        scheduler.configure(active: true, interval: 1);
        scheduler.observe(0, readingAction: false);
        scheduler.observe(1, readingAction: true);
        switch (action) {
          case 'inactive':
            scheduler.configure(active: false, interval: 1);
          case 'off':
            scheduler.configure(active: true, interval: 0);
          case 'dispose':
            scheduler.dispose();
          case 'manual':
            scheduler.reset();
          case 'interval':
            scheduler.configure(active: true, interval: 5);
        }
        time.elapse(const Duration(seconds: 1));
        expect(calls, 0);
        scheduler.dispose();
      });
    });
  }
  test('refresh exception does not interrupt next page refresh', () {
    fakeAsync((time) {
      var calls = 0;
      final scheduler = EinkPageRefreshScheduler(() async {
        calls++;
        throw StateError('OEM');
      });
      scheduler.configure(active: true, interval: 1);
      scheduler.observe(0, readingAction: false);
      scheduler.observe(1, readingAction: true);
      time.elapse(const Duration(seconds: 1));
      scheduler.observe(2, readingAction: true);
      time.elapse(const Duration(seconds: 1));
      expect(calls, 2);
      scheduler.dispose();
    });
  });
  test('backup accepts interval limits and rejects invalid ranges', () {
    for (final n in [0, 1, 50, 100]) {
      expect(
          () => validateSettingsValue('eInkRefreshPages', n), returnsNormally);
    }
    for (final n in [-1, 101, '10', 1.5, null]) {
      expect(() => validateSettingsValue('eInkRefreshPages', n),
          throwsFormatException);
    }
  });
}
