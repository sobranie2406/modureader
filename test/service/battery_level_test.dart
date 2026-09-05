import 'package:anx_reader/service/battery_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('readBatteryLevelSafely', () {
    test('returns a valid battery percentage', () async {
      expect(
        await readBatteryLevelSafely(loader: () async => 73),
        73,
      );
    });

    test('returns null when the platform reports no battery', () async {
      expect(
        await readBatteryLevelSafely(
          loader: () async => throw TypeError(),
        ),
        isNull,
      );
    });

    test('rejects out-of-range platform values', () async {
      expect(
        await readBatteryLevelSafely(loader: () async => -1),
        isNull,
      );
      expect(
        await readBatteryLevelSafely(loader: () async => 101),
        isNull,
      );
    });
  });
}
