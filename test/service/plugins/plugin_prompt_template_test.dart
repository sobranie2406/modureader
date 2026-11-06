import 'dart:io';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/plugin_state.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';
import 'package:anx_reader/service/plugins/plugin_paths.dart';
import 'package:anx_reader/service/plugins/plugin_prompt_template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

const String _pluginId = 'com.example.prompt-pack';
const String _promptId = 'plugin:com.example.prompt-pack:deep-summary';
const String _actionId =
    'custom-plugin:com.example.prompt-pack:explain-selection';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prompt rendering never substitutes secret values', () {
    final raw = jsonDecode(manifestJson(settings: [
      {'key': 'token', 'type': 'secret', 'label': 'API key'},
    ])) as Map<String, dynamic>;
    raw['capabilities'] = ['ai:prompt-pack', 'net:http'];
    raw['network'] = {
      'domains': ['api.example.com']
    };
    final manifest = PluginManifest.parse(jsonEncode(raw));
    expect(
        PluginPromptTemplate.render('Value: {setting.token}',
            manifest: manifest, values: {'token': 'test-only-secret'}),
        'Value: {setting.token}');
  });

  group('id handling', () {
    test('splits plugin-owned ids and leaves user ids alone', () {
      expect(
          PluginPromptTemplate.splitId(_promptId), (_pluginId, 'deep-summary'));
      expect(PluginPromptTemplate.splitId(_actionId),
          (_pluginId, 'explain-selection'));
      expect(PluginPromptTemplate.splitId('1712345678901'), isNull);
      expect(PluginPromptTemplate.splitId('custom-preset-summary'), isNull);
      expect(PluginPromptTemplate.splitId('plugin:'), isNull);
      expect(PluginPromptTemplate.splitId('plugin:only-id'), isNull);
    });

    test('builds the ids used for uninstall', () {
      expect(
          PluginPromptTemplate.promptId(_pluginId, 'deep-summary'), _promptId);
      expect(PluginPromptTemplate.actionId(_pluginId, 'explain-selection'),
          _actionId);
    });
  });

  group('rendering', () {
    late Directory temp;
    late PluginHost host;

    setUp(() async {
      SharedPreferences.setMockInitialValues(
          {'experimentalPluginsEnabled': true});
      await Prefs().initPrefs();
      Prefs().userPrompts = <dynamic>[].cast();
      await Prefs().savePluginState(PluginState.empty);
      await Prefs().saveLocaleToPrefs('en');
      temp = await Directory.systemTemp.createTemp('modu_plugin_template_');
      host = PluginHost(
        trust: const FixturePluginTrust(),
        paths: PluginPaths(rootPath: p.join(temp.path, 'plugins')),
        appVersionResolver: () async => '1.3.1+10152',
      );
      await host.initialize();
      PluginPromptTemplate.hostOverride = host;
      final package = await writePluginZip(
        temp,
        samplePackageFiles(
          manifest: manifestJson(
            capabilities: const ['ai:prompt-pack', 'ui:selection-action'],
            settings: [
              {
                'key': 'tone',
                'type': 'select',
                'label': {'en': 'Tone'},
                'options': ['concise', 'detailed'],
                'defaultValue': 'concise',
              },
              {
                'key': 'max_words',
                'type': 'number',
                'label': {'en': 'Max words'},
                'defaultValue': 300,
              },
              {
                'key': 'hint',
                'type': 'tip',
                'description': {'en': 'Stored only.'},
              },
            ],
            contributes: [
              aiSkill(
                  id: 'deep-summary',
                  prompt:
                      'Take a {setting.tone} tone, at most {setting.max_words} words.'),
              selectionAction(
                  id: 'explain-selection',
                  prompt: 'Explain {selection} in a {setting.tone} way.'),
            ],
          ),
        ),
      );
      await host.install(package);
    });

    tearDown(() async {
      PluginPromptTemplate.hostOverride = null;
      host.dispose();
      try {
        if (await temp.exists()) await temp.delete(recursive: true);
      } catch (_) {
        // Windows may hold the directory briefly; a leaked temp dir is harmless.
      }
    });

    test('falls back to manifest defaults when nothing was saved', () {
      final prompt = Prefs().userPrompts.single;
      expect(PluginPromptTemplate.resolveUserPrompt(prompt),
          'Take a concise tone, at most 300 words.');
    });

    test('uses the saved value and survives a settings change', () async {
      await Prefs().savePluginConfig(_pluginId, {'tone': 'detailed'});
      final prompt = Prefs().userPrompts.single;
      expect(PluginPromptTemplate.resolveUserPrompt(prompt),
          'Take a detailed tone, at most 300 words.');
      expect(prompt.content, contains('{setting.tone}'),
          reason: 'stored content keeps the template for the hash guard');
    });

    test('renders selection actions before {selection} is substituted', () {
      final item = Prefs()
          .selectionToolbar
          .items
          .singleWhere((entry) => entry.id == _actionId);
      expect(PluginPromptTemplate.renderForId(item.id, item.prompt),
          'Explain {selection} in a concise way.');
    });

    test('keeps unknown keys and tip settings verbatim', () {
      expect(
        PluginPromptTemplate.renderForId(_promptId,
            'A {setting.tone} {setting.missing} {setting.hint} prompt'),
        'A concise {setting.missing} {setting.hint} prompt',
      );
    });

    test('leaves the placeholder when the plugin is not installed', () {
      expect(
        PluginPromptTemplate.renderForId(
            'plugin:com.example.absent:deep-summary', 'Tone {setting.tone}'),
        'Tone {setting.tone}',
      );
    });

    test('leaves user prompts untouched', () {
      final userPrompt = Prefs().userPrompts.single;
      expect(
          PluginPromptTemplate.resolveUserPrompt(userPrompt.copyWith(
            id: '1712345678901',
            content: 'Keep {setting.tone} literal',
          )),
          'Keep {setting.tone} literal');
    });
  });
}
