import 'dart:io';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the checked-in sample plugin installs prompts, an action and settings',
      () async {
    final source = Directory('docs/examples/plugins/prompt-pack');
    expect(await source.exists(), isTrue,
        reason: 'sample plugin must ship with the repository');

    final files = <String, String>{};
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative =
          p.relative(entity.path, from: source.path).replaceAll('\\', '/');
      files[relative] = await entity.readAsString();
    }
    expect(files.keys, containsAll(['manifest.json', 'LICENSE', 'README.md']));

    final manifest = PluginManifest.parse(files['manifest.json']!);
    expect(manifest.version, '1.1.0');
    expect(manifest.license, 'CC0-1.0');
    expect(
        manifest.contributions.whereType<AiSkillContribution>(), hasLength(2));
    expect(manifest.contributions.whereType<SelectionActionContribution>(),
        hasLength(1));
    expect(manifest.settings, hasLength(4));

    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    Prefs().userPrompts = [];
    await Prefs().savePluginState(PluginState.empty);
    await Prefs().saveLocaleToPrefs('en');

    final temp = await Directory.systemTemp.createTemp('modu_sample_plugin_');
    final host = PluginHost(
      paths: PluginPaths(rootPath: p.join(temp.path, 'plugins')),
      appVersionResolver: () async => '1.3.1+10152',
    );
    addTearDown(() async {
      host.dispose();
      await temp.delete(recursive: true);
    });
    await host.initialize();

    final zip = await writePluginZip(temp, files);
    final result = await host.install(zip);
    expect(result.warnings, isEmpty);
    expect(result.record.applied, hasLength(3));

    final prompts = Prefs().userPrompts;
    expect(prompts, hasLength(2));
    expect(prompts.map((prompt) => prompt.id), [
      'plugin:com.example.prompt-pack:deep-summary',
      'plugin:com.example.prompt-pack:socratic-questions',
    ]);
    expect(prompts.every((prompt) => prompt.enabled), isTrue);
    expect(prompts.every((prompt) => prompt.content.isNotEmpty), isTrue);

    final action = Prefs().selectionToolbar.items.singleWhere((item) =>
        item.id == 'custom-plugin:com.example.prompt-pack:explain-selection');
    expect(action.name, 'Explain simply');
    expect(action.icon, 'lightbulb');
    expect(action.prompt, contains('{selection}'));
    expect(action.enabled, isTrue);
    expect(Prefs().pluginConfig('com.example.prompt-pack'), isEmpty);
  });
}
