import 'package:modu_reader/utils/log/common.dart';
import 'package:modu_reader/utils/platform_utils.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Serializes enable/timeout/exit so a late enable cannot outlive the reader.
class ReaderWakelock {
  static const channel = MethodChannel('modu/reader_wakelock');
  static Future<void> _pending = Future<void>.value();

  static Future<void> setEnabled(bool enabled, {AnxPlatformEnum? platform}) {
    final target = platform ?? AnxPlatform.type;
    return _pending = _pending.then((_) async {
      try {
        if (target == AnxPlatformEnum.ohos) {
          await channel.invokeMethod<void>('toggle', {'enabled': enabled});
        } else {
          await WakelockPlus.toggle(enable: enabled);
        }
      } catch (error) {
        // A missing window/plugin must not interrupt opening or closing a book.
        AnxLog.warning('Reader wakelock failed: ${error.runtimeType}');
      }
    });
  }
}
