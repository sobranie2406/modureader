import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/service/plugins/plugin_config.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_prompt_template.dart';
import 'package:modu_reader/service/private_library.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

const _id = 'com.example.device-config';
String _manifest() => manifestJson(id: _id, capabilities: [
      'library:private',
      'library:private-control',
      'settings:device',
      'ui:book-action'
    ], contributes: [
      {
        'kind': 'bookAction',
        'schema': 1,
        'id': 'hide',
        'name': 'Hide',
        'command': 'privateLibrary.hide'
      }
    ], settings: [
      {'key': 'shared', 'type': 'text', 'defaultValue': 'shared default'},
      {
        'key': 'local',
        'type': 'text',
        'storage': 'device',
        'defaultValue': 'local default'
      },
      for (final key in ['privateOnly', 'autoImport', 'lockAfterHide'])
        {
          'key': key.toLowerCase(),
          'type': 'toggle',
          'storage': 'device',
          'binding': 'privateLibrary.$key',
          'defaultValue': key == 'lockAfterHide'
        },
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = PrivateLibrary.instance;
  late Directory temp;
  final hosts = <PluginHost>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    library.setPluginActive(true);
    temp = await Directory.systemTemp.createTemp('modu-device-config-');
  });
  tearDown(() async {
    PluginPromptTemplate.hostOverride = null;
    for (final host in hosts) {
      host.dispose();
    }
    hosts.clear();
    library.setPluginActive(false);
    await temp.delete(recursive: true);
  });
  Future<PluginHost> host({bool development = false}) async {
    final instance = PluginHost(
        development: development,
        trust: FixturePluginTrust(),
        paths: PluginPaths(rootPath: '${temp.path}/${hosts.length}'),
        appVersionResolver: () async => '1.3.10');
    hosts.add(instance);
    await instance.initialize();
    final package =
        await writePluginZip(temp, samplePackageFiles(manifest: _manifest()));
    await instance.install(package);
    return instance;
  }

  test('ordinary device values split storage, survive restart and never export',
      () async {
    final owner = await host();
    await owner.saveConfig(_id, {'shared': 'portable', 'local': 'this device'});
    expect(Prefs().pluginConfig(_id), {'shared': 'portable'});
    expect(jsonDecode(Prefs().prefs.getString(PluginConfig.deviceKeyFor(_id))!),
        {'local': 'this device'});
    expect(owner.configFor(_id), containsPair('local', 'this device'));
    PluginPromptTemplate.hostOverride = owner;
    expect(
        PluginPromptTemplate.renderForId('plugin:$_id:example',
            'Local {setting.local} / shared {setting.shared}'),
        'Local this device / shared portable');
    final restarted = PluginHost(
        trust: FixturePluginTrust(),
        paths: owner.paths,
        appVersionResolver: () async => '1.3.10');
    hosts.add(restarted);
    await restarted.initialize();
    expect(restarted.configFor(_id)['local'], 'this device');
    expect((await Prefs().buildPrefsBackupMap()).keys,
        isNot(contains(PluginConfig.deviceKeyFor(_id))));
    final exported =
        await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true);
    expect(exported, isNot(contains('this device')));
    expect(exported, isNot(contains(PluginConfig.devicePrefix)));
    await owner.uninstall(_id);
    expect(Prefs().prefs.containsKey(PluginConfig.deviceKeyFor(_id)), false);
  });

  test(
      'all device-prefixed keys reject portable imports and ignore full backups',
      () async {
    final key = PluginConfig.deviceKeyFor(_id);
    await Prefs().prefs.setString(key, '{"local":"keep"}');
    final incoming = {
      prefsBackupVersionKey: 1,
      key: {'type': 'string', 'value': '{"local":"replace"}'}
    };
    expect(
        () => GlobalSettingsTransfer.validate(incoming), throwsFormatException);
    await Prefs().applyPrefsBackupMap(incoming);
    expect(Prefs().prefs.getString(key), '{"local":"keep"}');
    expect((await Prefs().buildPrefsBackupMap()).containsKey(key), false);
  });

  test('broken local overrides fall back without changing portable settings',
      () async {
    final owner = await host();
    await Prefs().savePluginConfig(_id, {'shared': 'portable'});
    for (final value in ['not json', '[1]', '{"local":null}']) {
      await Prefs().prefs.setString(PluginConfig.deviceKeyFor(_id), value);
      expect(owner.configFor(_id)['shared'], 'portable');
      expect(owner.configFor(_id).containsKey('local'), false);
    }
    await Prefs().prefs.setInt(PluginConfig.deviceKeyFor(_id), 1);
    expect(owner.configFor(_id)['shared'], 'portable');
  });

  test(
      'bindings read existing native values and require a current unlocked session',
      () async {
    final owner = await host();
    expect(owner.configFor(_id), containsPair('lockafterhide', true));
    expect(owner.configFor(_id), containsPair('autoimport', false));
    await expectLater(
        owner.saveConfig(_id, {'autoimport': true}), throwsStateError);
    await library.unlock();
    await library.setOptions(privateOnly: true, lockAfterHide: false);
    final nativeBefore = Prefs().prefs.getString(PrivateLibrary.storageKey);
    expect(owner.configFor(_id)['privateonly'], true);
    expect(owner.configFor(_id)['lockafterhide'], false);
    expect(Prefs().prefs.getString(PrivateLibrary.storageKey), nativeBefore);
    await owner.saveConfig(_id, {'autoimport': true, 'shared': 'ok'});
    expect(library.storedPolicyOptions['autoImport'], true);
    expect(Prefs().pluginConfig(_id), {'shared': 'ok'});
    expect(Prefs().prefs.getString(PluginConfig.deviceKeyFor(_id)), '{}');
    library.lock();
    await expectLater(
        owner.saveConfig(_id, {'autoimport': false}), throwsStateError);
  });

  test(
      'development values and binding overlays stay in memory and clear on close',
      () async {
    final owner = await host(development: true);
    await library.unlock();
    final before = Prefs().prefs.getString(PrivateLibrary.storageKey);
    await owner.saveConfig(
        _id, {'shared': 'debug', 'local': 'debug local', 'autoimport': true});
    expect(owner.configFor(_id)['autoimport'], true);
    expect(library.storedPolicyOptions['autoImport'], false);
    expect(Prefs().prefs.getString(PrivateLibrary.storageKey), before);
    expect(Prefs().prefs.containsKey(PluginConfig.keyFor(_id)), false);
    expect(Prefs().prefs.containsKey(PluginConfig.deviceKeyFor(_id)), false);
    await owner.closeDevelopment(skipAuthorization: true);
    expect(library.policyOptions['autoImport'], false);
    expect(owner.configFor(_id), isEmpty);
  });

  test('queued stale binding edit cannot survive lock and re-unlock', () async {
    final owner = await host();
    await library.unlock();
    final saving = owner.saveConfig(_id, {'autoimport': true});
    library.lock();
    await library.unlock();
    await expectLater(saving, throwsStateError);
    expect(library.storedPolicyOptions['autoImport'], false);
  });
}
