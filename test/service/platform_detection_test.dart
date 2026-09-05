import 'dart:io';

import 'package:anx_reader/utils/platform_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native host is recognized, including Linux CI and desktop users', () {
    const platforms = {
      'android': AnxPlatformEnum.android,
      'ios': AnxPlatformEnum.ios,
      'macos': AnxPlatformEnum.macos,
      'windows': AnxPlatformEnum.windows,
      'linux': AnxPlatformEnum.linux,
      'ohos': AnxPlatformEnum.ohos,
    };
    expect(AnxPlatform.type, platforms[Platform.operatingSystem]);
    expect(AnxPlatform.isLinux, Platform.isLinux);
    expect(AnxPlatform.isDesktop,
        Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    expect(AnxPlatform.isMobile, !AnxPlatform.isDesktop);
  });
}
