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
}
