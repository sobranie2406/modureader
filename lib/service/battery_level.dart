import 'package:battery_plus/battery_plus.dart';

typedef BatteryLevelLoader = Future<int> Function();

/// Reads a usable battery percentage, or returns `null` when the current
/// device does not expose a battery.
///
/// On macOS, battery_plus 6.x reports the native string `UNAVAILABLE` on
/// machines without a battery. Its Dart method-channel implementation expects
/// an integer, so that response surfaces as a [TypeError]. Treating it as an
/// unavailable reading keeps desktop readers from producing uncaught errors.
Future<int?> readBatteryLevelSafely({BatteryLevelLoader? loader}) async {
  try {
    final level = await (loader ?? () => Battery().batteryLevel)();
    if (level < 0 || level > 100) return null;
    return level;
  } catch (_) {
    return null;
  }
}
