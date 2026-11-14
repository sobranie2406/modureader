import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';

import 'plugin_test_utils.dart';

void main() {
  PluginManifest manifest(String pluginId, List<String> actionIds) =>
      PluginManifest.parse(manifestJson(
        id: pluginId,
        capabilities: ['script:run', 'ui:selection-action'],
        contributes: [
          for (final id in actionIds)
            {
              'kind': 'scriptAction',
              'schema': 1,
              'id': id,
              'name': id,
              'entry': 'main.js'
            },
        ],
      ));

  test('runtime-only actions register and disappear independently per plugin',
      () async {
    final registry = PluginScriptActionRegistry();
    addTearDown(registry.dispose);
    final handler = ScriptActionContributionHandler(registry: registry);
    final first = manifest('com.example.first', ['one', 'two']);
    final second = manifest('com.example.second', ['other']);
    final applied = await handler.apply(first, first.contributions);
    await handler.apply(second, second.contributions);
    expect(handler.runtimeOnly, isTrue);
    expect(registry.forSurface(PluginScriptSurface.selection), hasLength(3));
    expect(applied.first.contentSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(handler.isApplied(applied.first), isTrue);
    await handler.remove(applied);
    expect(handler.isApplied(applied.first), isFalse);
    expect(registry.forPlugin(first.id), isEmpty);
    expect(registry.forPlugin(second.id).single.action.id, 'other');
  });

  test('reconciliation replaces previous action list without duplicates',
      () async {
    final registry = PluginScriptActionRegistry();
    addTearDown(registry.dispose);
    final handler = ScriptActionContributionHandler(registry: registry);
    final original = manifest('com.example.first', ['old', 'kept']);
    final update = manifest(original.id, ['kept', 'new']);
    await handler.apply(original, original.contributions);
    await handler.apply(update, update.contributions);
    await handler.apply(update, update.contributions);
    expect(registry.forPlugin(original.id).map((item) => item.action.id),
        ['kept', 'new']);
    expect(registry.byId('script:${original.id}:old'), isNull);
  });
}
