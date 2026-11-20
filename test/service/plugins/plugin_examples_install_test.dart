import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

/// End-to-end check that the example packages built into docs/examples/plugins
/// /dist actually install and enable through the real host, not just that their
/// manifests parse. Skipped when the packages have not been packed yet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dist = Directory('docs/examples/plugins/dist');
  final packages = dist.existsSync()
      ? (dist.listSync().whereType<File>().where((f) =>
          f.path.endsWith('.moduplugin')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];

  test('example packages are packed', () {
    expect(packages, hasLength(5),
        reason: 'run scripts/dev/pack_plugin.dart for each example');
  }, skip: packages.isEmpty);

  late Directory temp;
  late PluginHost host;

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().savePluginPermissions({});
    temp = await Directory.systemTemp.createTemp('modu_example_install_');
    host = PluginHost(
      trust: FixturePluginTrust(),
      paths: PluginPaths(rootPath: p.join(temp.path, 'plugins')),
      appVersionResolver: () async => '1.3.10',
    );
    await host.initialize();
  });

  tearDown(() async {
    host.dispose();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  for (final package in packages) {
    test('${p.basename(package.path)} installs, enables and uninstalls',
        () async {
      final result = await host.install(package);
      expect(result.record.status, PluginStatus.enabled);
      expect(result.warnings, isEmpty);

      final manifest = host.manifestFor(result.record.id);
      expect(manifest, isNotNull);
      // Every example must survive the review gate the host applies.
      expect(host.byId(result.record.id), isNotNull);

      // A freshly installed example starts with no runtime grants: the user has
      // to switch the privacy-sensitive ones on themselves.
      expect(host.grantedPermissions(result.record.id), isEmpty);

      await host.uninstall(result.record.id);
      expect(host.byId(result.record.id), isNull);
    }, skip: packages.isEmpty);
  }
}
