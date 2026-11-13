import 'dart:convert';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/models/user_prompt.dart';
import 'package:modu_reader/service/plugins/handlers/ai_prompt_handler.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/service/config_transfer/settings_modules.dart';
import 'package:modu_reader/service/config_transfer/settings_value_validation.dart';
import 'package:modu_reader/service/plugins/plugin_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../service/plugins/plugin_test_utils.dart' as plugins;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final record = PluginRecord(
    id: 'com.example.prompt-pack',
    version: '1.0.0',
    name: const PluginText({'en': 'Example prompt pack'}),
    license: 'CC0-1.0',
    installedAt: DateTime.utc(2026, 10, 23, 12),
    sha256: 'a' * 64,
    status: PluginStatus.enabled,
    applied: [
      AppliedContribution(
        kind: 'aiSkill',
        id: 'plugin:com.example.prompt-pack:deep-summary',
        contentSha256: 'b' * 64,
      ),
    ],
  );

  Map<String, Object> pluginPrefs() => {
        'pluginState': jsonEncode(PluginState(plugins: [record]).toJson()),
        'pluginConfig_com.example.prompt-pack':
            jsonEncode({'tone': 'brief', 'max_words': 300}),
      };

  Future<void> initialize([Map<String, Object>? values]) async {
    SharedPreferences.setMockInitialValues(values ?? {});
    await Prefs().initPrefs();
  }

  setUp(() => initialize());

  test('plugin state, module ownership and config keys round trip', () async {
    await initialize(pluginPrefs());
    expect(settingsModuleForKey('pluginState'), 'plugins');
    expect(settingsModuleForKey('pluginConfig_com.example.prompt-pack'),
        'plugins');

    final file = await GlobalSettingsTransfer.export(Prefs(), scope: 'plugins');
    final data = await GlobalSettingsTransfer.decode(file);
    expect(
        data.keys.where((key) => key != prefsBackupVersionKey),
        unorderedEquals([
          'pluginState',
          'pluginConfig_com.example.prompt-pack',
        ]));
    expect(GlobalSettingsTransfer.includedScopes(data), ['plugins']);

    await initialize();
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(
        Prefs().pluginState.byId('com.example.prompt-pack')!.version, '1.0.0');
    expect(Prefs().pluginConfig('com.example.prompt-pack'),
        {'tone': 'brief', 'max_words': 300});
    expect(Prefs().prefs.getString('pluginConfig_com.example.prompt-pack'),
        isNotNull);
  });

  test('an absent plugin state exports an explicit reset', () async {
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), scope: 'plugins'));
    expect(data['pluginState'], {'type': 'reset', 'value': null});
  });

  test('experimental consent is neither exported nor accepted in a backup',
      () async {
    await Prefs().saveExperimentalPluginsEnabled(true);
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    expect(data.containsKey('experimentalPluginsEnabled'), isFalse);
    expect(
        () => GlobalSettingsTransfer.validate({
              prefsBackupVersionKey: 1,
              'experimentalPluginsEnabled': {'type': 'bool', 'value': true},
            }),
        throwsFormatException);
    expect(
        (await Prefs().buildPrefsBackupMap())
            .containsKey('experimentalPluginsEnabled'),
        isFalse);
    await Prefs().saveExperimentalPluginsEnabled(false);
    await Prefs().applyPrefsBackupMap({
      'experimentalPluginsEnabled': {'type': 'bool', 'value': true},
    });
    expect(Prefs().experimentalPluginsEnabled, isFalse);
  });

  for (final reset in [false, true]) {
    test(
        'restore ${reset ? 'reset' : 'full backup'} cannot leave active plugin prompts while off',
        () async {
      const content = 'Reviewed prompt';
      await Prefs().savePluginState(PluginState(plugins: [
        record.copyWith(applied: [
          AppliedContribution(
              kind: 'aiSkill',
              id: record.applied.single.id,
              contentSha256: AiPromptContributionHandler.contentHash(content)),
        ])
      ]));
      Prefs().userPrompts = [
        UserPrompt(
            id: record.applied.single.id,
            name: 'Sample',
            content: content,
            order: 0,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026))
      ];
      final data = reset
          ? <String, dynamic>{
              prefsBackupVersionKey: 1,
              'pluginState': {'type': 'reset', 'value': null},
            }
          : await GlobalSettingsTransfer.decode(
              await GlobalSettingsTransfer.export(Prefs()));
      await GlobalSettingsTransfer.apply(Prefs(), data);
      expect(Prefs().experimentalPluginsEnabled, isFalse);
      expect(Prefs().userPrompts, isEmpty);
      if (!reset) {
        expect(
            Prefs().pluginState.plugins.single.status, PluginStatus.disabled);
      }
    });
  }

  test('importing a plugin state for a missing package keeps the record',
      () async {
    await initialize(pluginPrefs());
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs(), scope: 'plugins'));
    await initialize();
    await GlobalSettingsTransfer.apply(Prefs(), data);
    final restored = Prefs().pluginState.byId('com.example.prompt-pack');
    expect(restored, isNotNull);
    expect(restored!.status, PluginStatus.disabled);
    expect(restored.applied, isEmpty);
    expect(Prefs().experimentalPluginsEnabled, isFalse);
  });

  for (final invalid in <String, Object>{
    'wrong schema': {'schemaVersion': 2, 'plugins': <Object>[]},
    'missing list': {'schemaVersion': 1},
    'duplicate ids': {
      'schemaVersion': 1,
      'plugins': [record.toJson(), record.toJson()],
    },
    'bad id': {
      'schemaVersion': 1,
      'plugins': [
        {...record.toJson(), 'id': 'Bad Id'},
      ],
    },
    'damaged record': {
      'schemaVersion': 1,
      'plugins': [
        {...record.toJson(), 'installedAt': 'not-a-date'},
      ],
    },
  }.entries) {
    test('rejects invalid plugin state: ${invalid.key}', () {
      expect(
        () => validateSettingsValue('pluginState', jsonEncode(invalid.value)),
        throwsFormatException,
      );
      expect(
        () => GlobalSettingsTransfer.validate({
          prefsBackupVersionKey: 1,
          'pluginState': {
            'type': 'string',
            'value': jsonEncode(invalid.value),
          },
        }),
        throwsFormatException,
      );
    });
  }

  test('rejects more than the plugin record limit', () {
    expect(
      () => validateSettingsValue(
          'pluginState',
          jsonEncode({
            'schemaVersion': 1,
            'plugins': [
              for (var i = 0; i < PluginState.maxRecords + 1; i++)
                {...record.toJson(), 'id': 'com.example.p$i'},
            ],
          })),
      throwsFormatException,
    );
  });

  for (final invalid in <String, Object>{
    'not an object': ['tone'],
    'nested value': {
      'tone': ['brief']
    },
    'bad key': {'Tone': 'brief'},
    'too long text': {'tone': 'x' * (PluginConfig.maxTextLength + 1)},
    'too many entries': {
      for (var i = 0; i < PluginConfig.maxEntries + 1; i++) 'key_$i': i,
    },
  }.entries) {
    test('rejects invalid plugin config shape: ${invalid.key}', () {
      expect(
        () => PluginConfig.validate(
            'com.example.prompt-pack', jsonEncode(invalid.value)),
        throwsFormatException,
      );
    });
  }

  test('missing plugin config validates object shape only', () {
    expect(
      () => validateSettingsValue(
          'pluginConfig_com.example.unknown',
          jsonEncode({
            'future_key': 'value',
            'future_number': 3,
          })),
      returnsNormally,
    );
  });

  test('installed plugin config is checked against manifest setting types', () {
    final manifest = PluginManifest.parse(plugins.manifestJson(settings: [
      {
        'key': 'tone',
        'type': 'select',
        'options': ['brief', 'detailed']
      },
      {'key': 'max_words', 'type': 'number'},
      {'key': 'enabled', 'type': 'toggle'},
    ]));
    PluginManifest? resolver(String id) =>
        id == 'com.example.prompt-pack' ? manifest : null;

    expect(
      () => validateSettingsValue('pluginConfig_com.example.prompt-pack',
          jsonEncode({'tone': 'brief', 'max_words': 300, 'enabled': false}),
          pluginManifest: resolver),
      returnsNormally,
    );
    for (final invalid in <Object>{
      {'tone': 3},
      {'max_words': '300'},
      {'enabled': 'yes'},
      {'tone': 'unknown-option'},
    }) {
      expect(
        () => validateSettingsValue(
            'pluginConfig_com.example.prompt-pack', jsonEncode(invalid),
            pluginManifest: resolver),
        throwsFormatException,
      );
    }

    final sanitized = PluginConfig.sanitize(manifest, {
      'tone': 'removed-option',
      'max_words': 12.5,
      'enabled': false,
      'unknown_future_key': 'kept',
    });
    expect(sanitized, {
      'max_words': 12.5,
      'enabled': false,
      'unknown_future_key': 'kept',
    });
  });

  test('uninstalling a plugin removes its state and saved settings', () async {
    await initialize(pluginPrefs());
    await Prefs().savePluginState(PluginState(plugins: [record]));
    expect(Prefs().pluginConfig('com.example.prompt-pack'), isNotEmpty);

    await Prefs().removePluginData('com.example.prompt-pack');

    expect(Prefs().pluginState.byId('com.example.prompt-pack'), isNull);
    expect(Prefs().pluginConfig('com.example.prompt-pack'), isEmpty);
    expect(Prefs().prefs.containsKey('pluginConfig_com.example.prompt-pack'),
        isFalse);
  });
}
