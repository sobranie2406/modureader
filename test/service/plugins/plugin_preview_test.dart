import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/models/plugin_state.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';
import 'package:anx_reader/service/plugins/plugin_paths.dart';
import 'package:anx_reader/service/plugins/plugin_trust.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late PluginPaths paths;
  late PluginHost host;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    Prefs().userPrompts = [];
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().saveLocaleToPrefs('en');
    temp = await Directory.systemTemp.createTemp('modu_plugin_preview_');
    paths = PluginPaths(rootPath: p.join(temp.path, 'plugins'));
    host = PluginHost(
      trust: const FixturePluginTrust(),
      paths: paths,
      appVersionResolver: () async => '1.3.1+10152',
    );
    await host.initialize();
  });

  tearDown(() async {
    host.dispose();
    try {
      if (await temp.exists()) await temp.delete(recursive: true);
    } catch (_) {
      // Windows may hold the directory briefly; a leaked temp dir is harmless.
    }
  });

  Future<File> package({String version = '1.0.0', Map<String, String>? files}) {
    return writePluginZip(
      temp,
      files ??
          samplePackageFiles(manifest: manifestJson(version: version)),
      name: 'preview-$version.moduplugin',
    );
  }

  test('preview reports the package without installing anything', () async {
    final file = await package();
    final preview = await host.preview(file);

    expect(preview.manifest.id, 'com.example.prompt-pack');
    expect(preview.manifest.version, '1.0.0');
    expect(preview.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(preview.compressedBytes, greaterThan(0));
    expect(preview.readme, contains('Example prompt pack'));
    expect(preview.willReplace, isFalse);
    expect(preview.warnings, isEmpty);

    expect(host.plugins, isEmpty);
    expect(Prefs().userPrompts, isEmpty);
    expect(await paths.pluginDir('com.example.prompt-pack').exists(), isFalse);
    expect(await paths.staging.list().isEmpty, isTrue,
        reason: 'preview must clean its staging directory');
  });

  test('preview surfaces skipped contribution kinds as warnings', () async {
    final file = await package(
      files: samplePackageFiles(
        manifest: manifestJson(contributes: [
          aiSkill(id: 'deep-summary'),
          {'kind': 'futureKind', 'schema': 1, 'id': 'extra'},
        ]),
      ),
    );
    final preview = await host.preview(file);
    expect(preview.warnings, hasLength(1));
    expect(preview.warnings.single, contains('futureKind'));
    expect(preview.manifest.contributions, hasLength(2));
  });

  test('preview rejects untrusted packages before the confirmation page',
      () async {
    final verified = PluginHost(
      paths: paths,
      appVersionResolver: () async => '1.3.1+10152',
    );
    addTearDown(verified.dispose);
    await verified.initialize();
    await expectLater(
      verified.preview(await package()),
      throwsA(isA<PluginInstallError>().having((error) => error.code,
          'code', PluginErrorCode.untrustedPackage)),
    );
  });

  test('preview and install reject the same version states', () async {
    await host.install(await package());
    await expectLater(
      host.preview(await package()),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.alreadyInstalled)),
    );
    final same = await host.preview(await package(), allowSameVersion: true);
    expect(same.willReplace, isTrue);
    expect(same.installedVersion, '1.0.0');
    await expectLater(
      host.preview(await package(version: '0.9.0')),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.downgradeNotAllowed)),
    );
  });

  test('preview reports a package without README', () async {
    final file = await writePluginZip(temp, {
      'manifest.json': manifestJson(),
      'LICENSE': 'CC0 1.0 Universal\n',
    });
    final preview = await host.preview(file);
    expect(preview.readme, isNull);
  });

  test('the confirmation page installs only after approval', () async {
    final file = await package();
    final preview = await host.preview(file);
    // Cancelling leaves no trace; a later confirm performs the install.
    expect(host.plugins, isEmpty);
    final result = await host.install(file);
    expect(result.record.version, '1.0.0');
    expect(preview.manifest.version, result.record.version);
    expect(host.plugins, hasLength(1));
  });
}
