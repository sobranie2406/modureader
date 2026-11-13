import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:modu_reader/utils/platform_utils.dart';

String installedAppVersion(String version, String build,
    {String harmonyReleaseVersion = ''}) {
  final source = RegExp(r'^(\d+\.\d+\.\d+)(?:-[\w.]+)?\+(\d+)$')
      .firstMatch(harmonyReleaseVersion);
  // Harmony accepts numeric versionName only; never mask a build override.
  if (source != null && source[1] == version && source[2] == build) {
    return harmonyReleaseVersion;
  }
  return build.isEmpty ? version : '$version+$build';
}

Future<String> getAppVersion() async {
  // Build flags override pubspec.yaml, which is bundled unchanged as an asset.
  // Updates and diagnostics must identify the installed binary, not its source.
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.trim().isNotEmpty) {
      return installedAppVersion(info.version, info.buildNumber,
          harmonyReleaseVersion: AnxPlatform.isOhos
              ? const String.fromEnvironment('MODU_HARMONY_RELEASE_VERSION')
              : '');
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
