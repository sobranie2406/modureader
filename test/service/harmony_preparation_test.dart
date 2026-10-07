import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/utils/get_path/get_download_path.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import '../../scripts/dev/check_harmony.dart' show ohosPluginStatus;

class _HarmonyPaths extends PathProviderPlatform {
  int documentsCalls = 0;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    documentsCalls++;
    return '/data/storage/el2/base/files/modu';
  }

  @override
  Future<String?> getDownloadsPath() async =>
      throw StateError('No public path on OHOS');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('OHOS is a native platform, never an Android or desktop alias', () {
    expect(AnxPlatform.fromOperatingSystem('ohos'), AnxPlatformEnum.ohos);
    expect(AnxPlatform.fromOperatingSystem('android'), AnxPlatformEnum.android);
    expect(AnxPlatform.fromOperatingSystem('linux'), AnxPlatformEnum.linux);
    expect(() => AnxPlatform.fromOperatingSystem('unknown'),
        throwsUnsupportedError);
  });

  test('OHOS staging uses the sandbox, not desktop HOME or public Downloads',
      () async {
    final original = PathProviderPlatform.instance;
    addTearDown(() => PathProviderPlatform.instance = original);
    final paths = _HarmonyPaths();
    PathProviderPlatform.instance = paths;
    expect(await getDownloadPath(platform: AnxPlatformEnum.ohos),
        '/data/storage/el2/base/files/modu');
    expect(paths.documentsCalls, 1);
  });

  test(
      'audit does not confuse Android plugins or empty OHOS entries with support',
      () {
    expect(ohosPluginStatus(null), 'no-plugin-declaration');
    expect(
        ohosPluginStatus({
          'plugin': {
            'platforms': {
              'android': {'pluginClass': 'Example'}
            }
          }
        }),
        'missing-ohos');
    expect(
        ohosPluginStatus({
          'plugin': {
            'platforms': {'ohos': {}}
          }
        }),
        'invalid-ohos-declaration');
    expect(
        ohosPluginStatus({
          'plugin': {
            'platforms': {
              'ohos': {'pluginClass': 'Example'}
            }
          }
        }),
        'declares-ohos');
    expect(
        ohosPluginStatus({
          'plugin': {
            'platforms': {
              'ohos': {'default_package': 'example_ohos'}
            }
          }
        }),
        'federated-ohos');
  });

  test('Harmony app identity is Modu and contains no inherited cloud client ID',
      () {
    final app =
        jsonDecode(File('ohos/AppScope/app.json5').readAsStringSync())['app'];
    expect(app['bundleName'], 'com.modu.reader');
    expect(app['vendor'], 'Modu');
    expect(app['versionName'], isNot('1.0.0'));
    expect(File('ohos/entry/src/main/module.json5').readAsStringSync(),
        isNot(contains('client_id')));
  });

  test('audit reads current manifest without changing dependency sources', () {
    final spec = Pubspec.parse(File('pubspec.yaml').readAsStringSync());
    expect(spec.dependencies.containsKey('flutter_inappwebview'), true);
    expect(spec.dependencyOverrides.containsKey('hf_tokenizers'), true);
  });
}
