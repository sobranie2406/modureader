import 'dart:async';

import 'package:modu_reader/utils/platform_utils.dart';
import 'package:modu_reader/utils/reader_wakelock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Decode the installed plugin's Pigeon ToggleMessage at the native boundary.
class _ToggleCodec extends StandardMessageCodec {
  const _ToggleCodec();
  @override
  Object? readValueOfType(int type, ReadBuffer buffer) =>
      type == 129 ? readValue(buffer) : super.readValueOfType(type, buffer);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pluginChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    _ToggleCodec(),
  );
  final pluginValues = <bool>[];
  setUp(() {
    pluginValues.clear();
    messenger.setMockDecodedMessageHandler<Object?>(pluginChannel,
        (message) async {
      pluginValues.add(((message as List).single as List).single as bool);
      return <Object?>[null];
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(ReaderWakelock.channel, null);
    messenger.setMockDecodedMessageHandler<Object?>(pluginChannel, null);
  });

  Future<void> advance(WidgetTester tester,
      [Duration duration = Duration.zero]) async {
    await tester.pump(duration);
    // The shared platform queue can come from an earlier real-async test zone.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  test('OHOS uses its native channel; other platforms retain wakelock_plus',
      () async {
    final calls = <bool>[];
    messenger.setMockMethodCallHandler(ReaderWakelock.channel, (call) async {
      expect(call.method, 'toggle');
      calls.add((call.arguments as Map)['enabled'] as bool);
      return null;
    });
    await ReaderWakelock.setEnabled(true, platform: AnxPlatformEnum.ohos);
    await ReaderWakelock.setEnabled(false, platform: AnxPlatformEnum.ohos);
    expect(calls, [true, false]);
    expect(pluginValues, isEmpty);
    for (final platform
        in AnxPlatformEnum.values.where((p) => p != AnxPlatformEnum.ohos)) {
      await ReaderWakelock.setEnabled(true, platform: platform);
      await ReaderWakelock.setEnabled(false, platform: platform);
    }
    expect(pluginValues,
        [true, false, true, false, true, false, true, false, true, false]);
  });

  test('exit disable waits for an in-flight enable', () async {
    final calls = <bool>[];
    final entered = Completer<void>();
    final finish = Completer<void>();
    messenger.setMockMethodCallHandler(ReaderWakelock.channel, (call) async {
      final enabled = (call.arguments as Map)['enabled'] as bool;
      calls.add(enabled);
      if (enabled) {
        entered.complete();
        await finish.future;
      }
      return null;
    });
    final enable =
        ReaderWakelock.setEnabled(true, platform: AnxPlatformEnum.ohos);
    await entered.future;
    final disable =
        ReaderWakelock.setEnabled(false, platform: AnxPlatformEnum.ohos);
    expect(calls, [true]);
    finish.complete();
    await Future.wait([enable, disable]);
    expect(calls, [true, false]);
  });

  test('channel failure is contained and next release is still attempted',
      () async {
    final calls = <bool>[];
    messenger.setMockMethodCallHandler(ReaderWakelock.channel, (call) async {
      final enabled = (call.arguments as Map)['enabled'] as bool;
      calls.add(enabled);
      if (enabled) throw PlatformException(code: 'channel-error');
      return null;
    });
    await ReaderWakelock.setEnabled(true, platform: AnxPlatformEnum.ohos);
    await ReaderWakelock.setEnabled(false, platform: AnxPlatformEnum.ohos);
    expect(calls, [true, false]);
  });

  testWidgets('foreground reading and auto scroll share the screen lock',
      (tester) async {
    // auto scroll holds the screen after the ordinary timeout expires.
    {
      pluginValues.clear();
      final session = ReaderAwakeSession();
      session.reset(1);
      await advance(tester);
      session.setAutoScrolling(true);
      await advance(tester, const Duration(minutes: 2));
      expect(pluginValues, [true]);
      session.setAutoScrolling(false);
      await advance(tester);
      expect(pluginValues, [true, false]);
      session.dispose();
      await advance(tester);
    }
    // zero timeout still allows auto scroll to hold the screen.
    {
      pluginValues.clear();
      final session = ReaderAwakeSession();
      session.reset(0);
      session.setAutoScrolling(true);
      await advance(tester, const Duration(minutes: 10));
      expect(pluginValues, [true]);
      session.setAutoScrolling(false);
      await advance(tester);
      expect(pluginValues, [true, false]);
      session.dispose();
      await advance(tester);
    }
    // pausing retains an unexpired ordinary reading timeout.
    {
      pluginValues.clear();
      final session = ReaderAwakeSession();
      session.reset(5);
      session.setAutoScrolling(true);
      await advance(tester, const Duration(minutes: 1));
      session.setAutoScrolling(false);
      await advance(tester);
      expect(pluginValues, [true]);
      await advance(tester, const Duration(minutes: 4));
      expect(pluginValues, [true, false]);
      session.dispose();
      await advance(tester);
    }
    // background releases the screen and does not renew an expired timeout.
    {
      pluginValues.clear();
      final session = ReaderAwakeSession();
      session.reset(1);
      session.setAutoScrolling(true);
      await advance(tester);
      session.setForeground(false);
      session.setAutoScrolling(false);
      await advance(tester, const Duration(minutes: 2));
      session.setForeground(true);
      await advance(tester);
      expect(pluginValues, [true, false]);
      session.dispose();
      await advance(tester);
    }
    // returning to the reader preserves the original unexpired timeout.
    {
      pluginValues.clear();
      final session = ReaderAwakeSession();
      session.reset(5);
      await advance(tester);
      session.setForeground(false);
      await advance(tester, const Duration(minutes: 1));
      session.setForeground(true);
      await advance(tester);
      expect(pluginValues, [true, false, true]);
      await advance(tester, const Duration(minutes: 4));
      expect(pluginValues, [true, false, true, false]);
      session.dispose();
      await advance(tester);
    }
    // disposing releases the lock and rejects later resets and ticks.
    {
      pluginValues.clear();
      final session = ReaderAwakeSession();
      session.reset(5);
      session.setAutoScrolling(true);
      await advance(tester);
      session.dispose();
      await advance(tester);
      session.reset(5);
      session.setAutoScrolling(true);
      session.setForeground(true);
      await advance(tester, const Duration(minutes: 10));
      expect(pluginValues, [true, false]);
    }
  });
}
