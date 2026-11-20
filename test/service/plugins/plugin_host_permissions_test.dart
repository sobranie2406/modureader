import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

const _id = 'com.example.permissions';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late PluginHost host;

  String manifestJsonFor(List<String> capabilities) => manifestJson(
        id: _id,
        capabilities: capabilities,
        contributes: const [],
      );

  Future<void> install(List<String> capabilities) async {
    final package = await writePluginZip(temp,
        samplePackageFiles(manifest: manifestJsonFor(capabilities)));
    await host.install(package, allowSameVersion: true);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().savePluginPermissions({});
    temp = await Directory.systemTemp.createTemp('modu_plugin_perms_');
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

  test('a runtime capability starts denied', () async {
    await install(['ai:invoke', 'note:read']);
    expect(host.grantedPermissions(_id), isEmpty);
    expect(host.hasPermission(_id, 'ai:invoke'), isFalse);
  });

  test('an install-tier capability needs no grant', () async {
    await install(['script:run', 'ai:prompt-pack']);
    expect(host.hasPermission(_id, 'script:run'), isTrue);
    expect(host.grantedPermissions(_id), isEmpty);
  });

  test('granting persists and is visible immediately', () async {
    await install(['ai:invoke', 'note:read']);
    await host.setPermission(_id, 'ai:invoke', true);
    expect(host.hasPermission(_id, 'ai:invoke'), isTrue);
    expect(host.grantedPermissions(_id), {'ai:invoke'});
    expect(Prefs().pluginPermissions[_id], {'ai:invoke'});

    await host.setPermission(_id, 'ai:invoke', false);
    expect(host.hasPermission(_id, 'ai:invoke'), isFalse);
    expect(Prefs().pluginPermissions.containsKey(_id), isFalse);
  });

  test('granting a capability the package did not declare is refused',
      () async {
    await install(['note:read']);
    await expectLater(host.setPermission(_id, 'ai:invoke', true),
        throwsA(isA<PluginInstallError>()));
    expect(host.hasPermission(_id, 'ai:invoke'), isFalse);
  });

  test('an install-tier capability cannot be granted at runtime', () async {
    await install(['script:run']);
    await expectLater(
        host.setPermission(_id, 'script:run', true),
        throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
            PluginErrorCode.permissionNotRuntime)));
  });

  test('uninstalling removes every grant', () async {
    await install(['ai:invoke', 'note:read']);
    await host.setPermission(_id, 'ai:invoke', true);
    await host.uninstall(_id);
    expect(Prefs().pluginPermissions.containsKey(_id), isFalse);
    expect(host.hasPermission(_id, 'ai:invoke'), isFalse);
  });

  test('revokeAllPermissions clears the plugin record', () async {
    await install(['ai:invoke', 'note:read']);
    await host.setPermission(_id, 'ai:invoke', true);
    await host.setPermission(_id, 'note:read', true);
    await host.revokeAllPermissions(_id);
    expect(host.grantedPermissions(_id), isEmpty);
  });

  test('reinstalling keeps the grants the user already made', () async {
    await install(['ai:invoke']);
    await host.setPermission(_id, 'ai:invoke', true);
    await install(['ai:invoke']);
    expect(host.hasPermission(_id, 'ai:invoke'), isTrue);
  });

  test('a fresh install never inherits grandfathered grants', () async {
    // library:read and note:write predate manual grants, so an upgraded plugin
    // keeps them; a brand new plugin must still ask.
    await install(['library:read', 'note:write']);
    expect(host.grantedPermissions(_id), isEmpty);
    expect(host.hasPermission(_id, 'library:read'), isFalse);
  });

  test('revoking everything does not resurrect on the next start', () async {
    await install(['library:read']);
    await host.setPermission(_id, 'library:read', true);
    await host.revokeAllPermissions(_id);
    host.dispose();

    final reopened = PluginHost(
      trust: FixturePluginTrust(),
      paths: PluginPaths(rootPath: p.join(temp.path, 'plugins')),
      appVersionResolver: () async => '1.3.10',
    );
    await reopened.initialize();
    expect(reopened.grantedPermissions(_id), isEmpty);
    reopened.dispose();
    host = reopened;
  });

  test('grants survive a restart', () async {
    await install(['ai:invoke']);
    await host.setPermission(_id, 'ai:invoke', true);
    host.dispose();

    final reopened = PluginHost(
      trust: FixturePluginTrust(),
      paths: PluginPaths(rootPath: p.join(temp.path, 'plugins')),
      appVersionResolver: () async => '1.3.10',
    );
    await reopened.initialize();
    expect(reopened.hasPermission(_id, 'ai:invoke'), isTrue);
    reopened.dispose();
    // Keep tearDown's host reference valid for disposal bookkeeping.
    host = reopened;
  });

  test('permission grants never enter the settings backup', () async {
    await install(['ai:invoke']);
    await host.setPermission(_id, 'ai:invoke', true);
    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup.containsKey('pluginPermissions'), isFalse);
  });
}
