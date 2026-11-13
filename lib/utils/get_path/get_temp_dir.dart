import 'dart:io';
import 'package:modu_reader/utils/platform_utils.dart';

import 'package:path_provider/path_provider.dart';

Future<Directory> getAnxTempDir() async {
  switch (AnxPlatform.type) {
    case AnxPlatformEnum.android:
    case AnxPlatformEnum.ohos:
    case AnxPlatformEnum.linux:
    case AnxPlatformEnum.windows:
    case AnxPlatformEnum.macos:
    case AnxPlatformEnum.ios:
      return await getTemporaryDirectory();
  }
}
