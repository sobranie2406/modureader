import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

Future<String> getAppVersion() async {
  // Build flags override pubspec.yaml, which is bundled unchanged as an asset.
  // Updates and diagnostics must identify the installed binary, not its source.
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.trim().isNotEmpty) {
      return info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    }
  } on MissingPluginException {
    // Unit tests or a platform without package metadata use the source version.
  } on PlatformException {
    // A failed metadata lookup must not block startup or the About dialog.
  }
  final pubspecContent = await rootBundle.loadString('pubspec.yaml');
  final pubspec = Pubspec.parse(pubspecContent);
  return pubspec.version.toString();
}
