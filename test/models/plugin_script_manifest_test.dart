import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';

import '../service/plugins/plugin_test_utils.dart';

Map<String, Object?> scriptAction({
  String entry = 'main.js',
  String? surface,
  String? scope,
  int schema = 1,
}) =>
    {
      'kind': 'scriptAction',
      'schema': schema,
      'id': 'run',
      'name': 'Run',
      'entry': entry,
      if (surface != null) 'surface': surface,
      if (scope != null) 'scope': scope,
    };

void main() {
  PluginManifest parse(Map<String, Object?> action,
          {List<String> capabilities = const [
            'script:run',
            'ui:selection-action'
          ]}) =>
      PluginManifest.parse(
          manifestJson(capabilities: capabilities, contributes: [action]));

  test('v1 scripts default to selection-only without changing legacy formats',
      () {
    final manifest = parse(scriptAction());
    final action = manifest.contributions.single as ScriptActionContribution;
    expect(manifest.schemaVersion, 1);
    expect(manifest.hostApi, 1);
    expect(action.entry, 'main.js');
    expect(action.surface, PluginScriptSurface.selection);
    expect(action.scope, PluginSelectionScope.selection);
    expect(PluginManifest.parse(manifestJson()).contributions.first,
        isA<AiSkillContribution>());
  });

  test('context is opt-in and library actions need no selection capability',
      () {
    expect(
        (parse(scriptAction(scope: 'context')).contributions.single
                as ScriptActionContribution)
            .scope,
        PluginSelectionScope.context);
    final manifest = parse(scriptAction(surface: 'library'), capabilities: [
      'script:run',
      'library:private',
      'library:read',
      'note:write'
    ]);
    expect((manifest.contributions.single as ScriptActionContribution).surface,
        PluginScriptSurface.library);
  });

  test('script and selection capabilities are required', () {
    for (final capabilities in <List<String>>[
      [],
      ['script:run'],
      ['ui:selection-action']
    ]) {
      expect(() => parse(scriptAction(), capabilities: capabilities),
          throwsA(isA<PluginInstallError>()));
    }
    expect(() => parse(scriptAction(surface: 'library'), capabilities: []),
        throwsA(isA<PluginInstallError>()));
  });

  test(
      'dictionary transforms require their permission and selection-only input',
      () {
    final manifest = parse(scriptAction(surface: 'dictionary'),
        capabilities: ['script:run', 'dictionary:transform']);
    expect((manifest.contributions.single as ScriptActionContribution).surface,
        PluginScriptSurface.dictionary);
    expect(() => parse(scriptAction(surface: 'dictionary')),
        throwsA(isA<PluginInstallError>()));
    expect(
        () => parse(scriptAction(surface: 'dictionary', scope: 'context'),
            capabilities: ['script:run', 'dictionary:transform']),
        throwsA(isA<PluginInstallError>()));
    expect(
        parse(scriptAction(surface: 'library'),
            capabilities: ['script:run', 'article:capture']).capabilities,
        contains(kArticleCaptureCapability));
  });

  test('only safe package-relative JavaScript entries are accepted', () {
    expect(
        (parse(scriptAction(entry: 'scripts/clean-text.js'))
                .contributions
                .single as ScriptActionContribution)
            .entry,
        'scripts/clean-text.js');
    for (final entry in [
      '../main.js',
      '/main.js',
      'scripts/../main.js',
      'scripts/./main.js',
      'scripts//main.js',
      r'scripts\main.js',
      'C:/main.js',
      'https://example.com/main.js',
      'main.js?x',
      '%2e%2e/main.js',
      'main.json',
      '',
      '${'x' * 257}.js',
    ]) {
      expect(() => parse(scriptAction(entry: entry)),
          throwsA(isA<PluginInstallError>()),
          reason: entry);
    }
  });

  test('unsupported action schemas, surfaces and scopes fail closed', () {
    for (final action in [
      scriptAction(schema: 2),
      scriptAction(surface: 'background'),
      scriptAction(scope: 'all-books'),
    ]) {
      expect(() => parse(action), throwsA(isA<PluginInstallError>()));
    }
  });
}
