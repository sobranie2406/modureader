import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';

import '../service/plugins/plugin_test_utils.dart';

Map<String, Object?> _action(
        {String id = 'hide',
        Object? command = 'privateLibrary.hide',
        Object? name = 'Hide in private library',
        int schema = 1}) =>
    {
      'kind': 'bookAction',
      'schema': schema,
      'id': id,
      'name': name,
      'command': command,
    };

Matcher _fails(PluginErrorCode code) => throwsA(
    isA<PluginInstallError>().having((error) => error.code, 'code', code));

void main() {
  PluginManifest parse(List<Map<String, Object?>> actions,
          {List<String> capabilities = const [
            'ui:book-action',
            'library:private'
          ],
          Set<String> allowed = kP1SupportedCapabilities}) =>
      PluginManifest.parse(
          manifestJson(capabilities: capabilities, contributes: actions),
          allowedCapabilities: allowed);

  test('book menu declarations require no script or new host schema', () {
    final manifest = parse([
      _action(name: {'en': 'Hide book', 'zh-CN': '隐藏书籍'})
    ]);
    final action = manifest.contributions.single as BookActionContribution;
    expect(action.command, 'privateLibrary.hide');
    expect(action.name.resolve('en'), 'Hide book');
    expect(action.name.resolve('zh-CN'), '隐藏书籍');
    expect(manifest.schemaVersion, 1);
    expect(manifest.hostApi, 1);
    expect(manifest.capabilities, isNot(contains(kScriptRunCapability)));
  });

  test('both book-menu and private-library grants are mandatory', () {
    for (final capabilities in <List<String>>[
      [],
      ['ui:book-action'],
      ['library:private']
    ]) {
      expect(() => parse([_action()], capabilities: capabilities),
          _fails(PluginErrorCode.capabilityUnavailable));
    }
  });

  test('an older adapter cannot silently skip the required menu permission',
      () {
    expect(
        () => parse([_action()],
            allowed: {...kP1SupportedCapabilities}
              ..remove(kBookActionCapability)),
        _fails(PluginErrorCode.capabilityUnavailable));
  });

  test('only the declared native hide command and schema one are accepted', () {
    for (final command in <Object?>[
      null,
      '',
      'privateLibrary.lock',
      'http.get',
      'privateLibrary.hide ',
      {'command': 'privateLibrary.hide'}
    ]) {
      expect(() => parse([_action(command: command)]),
          _fails(PluginErrorCode.invalidContribution));
    }
    expect(() => parse([_action(schema: 2)]),
        _fails(PluginErrorCode.invalidContribution));
  });

  test('book menu names and identifiers obey bounded known-kind validation',
      () {
    for (final id in ['', '../hide', 'UPPER', 'x' * 65]) {
      expect(() => parse([_action(id: id)]),
          _fails(PluginErrorCode.invalidContribution));
    }
    expect(
        () => parse([_action(name: '')]), throwsA(isA<PluginInstallError>()));
    expect(() => parse([_action(name: 'x' * 31)]),
        _fails(PluginErrorCode.nameTooLong));
  });

  test('book menu limits and duplicate IDs cannot be bypassed', () {
    expect(
        parse(List.generate(PluginLimits.maxBookActionsPerPlugin,
            (index) => _action(id: 'hide-$index'))).contributions,
        hasLength(PluginLimits.maxBookActionsPerPlugin));
    expect(
        () => parse(List.generate(PluginLimits.maxBookActionsPerPlugin + 1,
            (index) => _action(id: 'hide-$index'))),
        _fails(PluginErrorCode.tooManyContributions));
    expect(() => parse([_action(), _action()]),
        _fails(PluginErrorCode.duplicateContribution));
  });

  test('unknown contributions stay forward compatible beside book actions', () {
    final manifest = parse([
      _action(),
      {'kind': 'futureBookUI', 'schema': 4}
    ]);
    expect(manifest.contributions.first, isA<BookActionContribution>());
    expect(manifest.contributions.last, isA<UnknownContribution>());
    expect(manifest.warnings, hasLength(1));
    expect(
        parse([
          {'kind': 'futureBookUI', 'schema': 4}
        ], capabilities: []).contributions.single,
        isA<UnknownContribution>());
  });

  test('book and legacy script actions coexist without sharing IDs', () {
    final manifest = parse([
      _action(),
      {
        'kind': 'scriptAction',
        'schema': 1,
        'id': 'hide',
        'name': 'Open library',
        'entry': 'main.js',
        'surface': 'library',
      }
    ], capabilities: [
      'ui:book-action',
      'library:private',
      'script:run'
    ]);
    expect(manifest.contributions.whereType<BookActionContribution>(),
        hasLength(1));
    expect(manifest.contributions.whereType<ScriptActionContribution>(),
        hasLength(1));
  });
}
