import 'dart:io';

import 'package:flutter/foundation.dart';

enum AnxPlatformEnum { android, ios, macos, windows, ohos, linux }

class AnxPlatform {
  static AnxPlatformEnum get type => kIsWeb
      ? throw UnsupportedError('Web is not a native platform')
      : fromOperatingSystem(Platform.operatingSystem);

  /// HarmonyOS NEXT uses the OHOS Flutter engine, not the Android runtime.
  /// Keep this mapping testable without pretending the host is a real device.
  static AnxPlatformEnum fromOperatingSystem(String operatingSystem) =>
      switch (operatingSystem) {
        'android' => AnxPlatformEnum.android,
        'ios' => AnxPlatformEnum.ios,
        'macos' => AnxPlatformEnum.macos,
        'windows' => AnxPlatformEnum.windows,
        'linux' => AnxPlatformEnum.linux,
        'ohos' => AnxPlatformEnum.ohos,
        _ => throw UnsupportedError('Unsupported platform: $operatingSystem'),
      };

  static bool get isAndroid => type == AnxPlatformEnum.android;
  static bool get isIOS => type == AnxPlatformEnum.ios;
  static bool get isMacOS => type == AnxPlatformEnum.macos;
  static bool get isWindows => type == AnxPlatformEnum.windows;
  static bool get isOhos => type == AnxPlatformEnum.ohos;
  static bool get isLinux => type == AnxPlatformEnum.linux;

  static bool get isMobile => isAndroid || isIOS || isOhos;

  static bool get isDesktop => isWindows || isMacOS || isLinux;
}
