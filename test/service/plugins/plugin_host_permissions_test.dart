import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_permissions.dart';
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
        contributes: host.development
            ? const [
                {
                  'kind': 'scriptAction',
                  'schema': 1,
                  'id': 'echo',
                  'name': 'Echo',
                  'entry': 'main.js',
                  'surface': 'library',
                }
              ]
            : const [],
      );

  Future<void> install(List<String> capabilities) async {
    final package = await writePluginZip(temp, {
      ...samplePackageFiles(manifest: manifestJsonFor(capabilities)),
      if (host.development) 'main.js': 'return {text: "ok"};',
    });
    await host.install(package, allowSameVersion: true);
  }

  PluginHost makeHost({bool development = false}) => PluginHost(
        trust: FixturePluginTrust(),
        paths: PluginPaths(rootPath: p.join(temp.path, 'plugins')),
        appVersionResolver: () async => '1.3.10',
        development: development,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().savePluginPermissions({});
    temp = await Directory.systemTemp.createTemp('modu_plugin_perms_');
    host = makeHost();
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

  test('an implicit capability is granted whether or not it is declared',
      () async {
    // The parser drops 'storage:plugin' from manifest.capabilities, so a host
    // that answers from that set denies a capability the user cannot switch on.
    await install(['script:run']);
    expect(host.hasPermission(_id, kPluginStorageCapability), isTrue);
    expect(host.manifestFor(_id)!.capabilities,
        isNot(contains(kPluginStorageCapability)));
    await install(['script:run', kPluginStorageCapability]);
    expect(host.hasPermission(_id, kPluginStorageCapability), isTrue);
    expect(host.manifestFor(_id)!.capabilities,
        isNot(contains(kPluginStorageCapability)));
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

  test('older installations keep only existing legacy capabilities', () async {
    await install(['library:read', 'ai:invoke']);
    await Prefs().clearPluginPermissionSeeded(_id);
    host.dispose();
    host = makeHost();
    await host.initialize();
    expect(host.grantedPermissions(_id), {'library:read'});

    await install(['library:read', 'ai:invoke', 'note:write']);
    expect(host.grantedPermissions(_id), {'library:read'});
    await host.revokeAllPermissions(_id);
    host.dispose();
    host = makeHost();
    await host.initialize();
    expect(host.grantedPermissions(_id), isEmpty);
  });

  test('grants survive a restart', () async {
    await install(['ai:invoke']);
    await host.setPermission(_id, 'ai:invoke', true);
    host.dispose();

    host = makeHost();
    await host.initialize();
    expect(host.hasPermission(_id, 'ai:invoke'), isTrue);
  });

  test('grantPermissions applies a batch and reports what is in force',
      () async {
    await install(['ai:invoke', 'note:read', 'clipboard:write']);
    final granted =
        await host.grantPermissions(_id, ['ai:invoke', 'note:read']);
    expect(granted, {'ai:invoke', 'note:read'});
    expect(Prefs().pluginPermissions[_id], {'ai:invoke', 'note:read'});
  });

  test('grantPermissions still refuses an undeclared capability', () async {
    await install(['note:read']);
    await expectLater(host.grantPermissions(_id, ['note:read', 'ai:invoke']),
        throwsA(isA<PluginInstallError>()));
    expect(host.grantedPermissions(_id), isEmpty);
    expect(host.hasPermission(_id, 'ai:invoke'), isFalse);
  });

  test('an upgrade drops a grant the new version no longer declares', () async {
    await install(['ai:invoke', 'note:read']);
    await host.setPermission(_id, 'ai:invoke', true);
    await host.setPermission(_id, 'note:read', true);
    // The new version keeps only note:read.
    await install(['note:read']);
    expect(host.grantedPermissions(_id), {'note:read'});
    expect(host.hasPermission(_id, 'ai:invoke'), isFalse);
  });

  test('development grants are pruned and never reseeded', () async {
    host.dispose();
    host = makeHost(development: true);
    await host.initialize();
    await install(['script:run', 'library:read', 'ai:invoke']);
    expect(host.grantedPermissions(_id), isEmpty);
    await host.setPermission(_id, 'ai:invoke', true);
    await install(['script:run', 'library:read']);
    await install(['script:run', 'library:read', 'ai:invoke']);
    expect(host.grantedPermissions(_id), isEmpty);
    await host.setPermission(_id, 'ai:invoke', true);
    await host.uninstall(_id);
    await install(['script:run', 'library:read', 'ai:invoke']);
    expect(host.grantedPermissions(_id), isEmpty);
  });

  test('device permission state stays out of settings backup and restoration',
      () async {
    await install(['ai:invoke']);
    await host.setPermission(_id, 'ai:invoke', true);
    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup, isNot(contains(PluginPermissions.prefsKey)));
    expect(backup, isNot(contains(PluginPermissions.seededKey)));
    await Prefs().applyPrefsBackupMap({
      PluginPermissions.prefsKey: {'type': 'string', 'value': '{}'},
      PluginPermissions.seededKey: {'type': 'stringList', 'value': <String>[]},
    });
    expect(host.grantedPermissions(_id), {'ai:invoke'});
    expect(Prefs().pluginPermissionSeeded, {_id});
  });
}
