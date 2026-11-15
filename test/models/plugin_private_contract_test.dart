import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/handlers/book_action_handler.dart';
import 'package:modu_reader/service/plugins/handlers/script_action_handler.dart';

import '../service/plugins/plugin_test_utils.dart';

const _caps = [
  'library:private',
  'library:private-control',
  'library:private-policy',
  'settings:device',
  'script:run',
  'ui:book-action'
];
Map<String, Object?> _toggle(String key, {String? binding}) => {
      'key': key,
      'type': 'toggle',
      'storage': 'device',
      if (binding != null) 'binding': binding,
    };
Map<String, Object?> _policy({String id = 'import'}) => {
      'kind': 'scriptAction',
      'schema': 1,
      'id': id,
      'name': id,
      'entry': 'import.js',
      'surface': 'bookImport',
      'enabledSetting': 'auto_import',
    };
Map<String, Object?> _book() => {
      'kind': 'bookAction',
      'schema': 1,
      'id': 'hide',
      'name': 'Hide',
      'command': 'privateLibrary.setPrivate',
      'private': true,
      'when': 'public',
      'lockAfterSetting': 'lock_after_hide',
    };

PluginManifest _parse(
        {List<String> caps = _caps,
        List<Map<String, Object?>>? settings,
        List<Map<String, Object?>>? actions}) =>
    PluginManifest.parse(manifestJson(
      capabilities: caps,
      settings: settings ??
          [
            _toggle('auto_import', binding: 'privateLibrary.autoImport'),
            _toggle('lock_after_hide', binding: 'privateLibrary.lockAfterHide')
          ],
      contributes: actions ?? [_policy(), _book()],
    ));

void main() {
  test(
      'private package declares device bindings, import policy and book controls',
      () {
    final manifest = _parse();
    final policy =
        manifest.contributions.whereType<ScriptActionContribution>().single;
    final book =
        manifest.contributions.whereType<BookActionContribution>().single;
    expect(policy.surface, PluginScriptSurface.bookImport);
    expect(policy.enabledSetting, 'auto_import');
    expect(policy.scope, PluginSelectionScope.selection);
    expect(book.privateValue, true);
    expect(book.when, 'public');
    expect(book.lockAfter, false);
    expect(book.lockAfterSetting, 'lock_after_hide');
    expect(manifest.settings.first.isDevice, true);
    expect(manifest.settings.first.binding, 'privateLibrary.autoImport');
    ScriptActionContributionHandler().validate(manifest, [policy]);
    BookActionContributionHandler().validate(manifest, [book]);
  });

  test(
      'new permissions require private-library ownership and old SDK refuses them',
      () {
    for (final cap in [
      'library:private',
      'library:private-control',
      'library:private-policy',
      'settings:device',
      'script:run'
    ]) {
      expect(() => _parse(caps: _caps.where((c) => c != cap).toList()),
          throwsA(isA<PluginInstallError>()),
          reason: cap);
    }
    expect(
        () => PluginManifest.parse(
            manifestJson(capabilities: _caps, contributes: [], settings: []),
            allowedCapabilities:
                kP1SupportedCapabilities.difference({'settings:device'})),
        throwsA(isA<PluginInstallError>()));
  });

  test(
      'bindings are unique device-only toggles and secret storage stays separate',
      () {
    for (final setting in [
      {
        ..._toggle('auto_import', binding: 'privateLibrary.autoImport'),
        'storage': 'sync'
      },
      {..._toggle('auto_import'), 'binding': 'privateLibrary.unknown'},
      {
        ..._toggle('auto_import', binding: 'privateLibrary.autoImport'),
        'type': 'text'
      },
      {'key': 'token', 'type': 'secret', 'storage': 'device'},
      {..._toggle('auto_import'), 'storage': 'cloud'},
    ]) {
      expect(() => _parse(settings: [setting], actions: []),
          throwsA(isA<PluginInstallError>()));
    }
    expect(
        () => _parse(settings: [
              _toggle('one', binding: 'privateLibrary.autoImport'),
              _toggle('two', binding: 'privateLibrary.autoImport')
            ], actions: []),
        throwsA(isA<PluginInstallError>()));
    final ordinary = _parse(settings: [_toggle('future_option')], actions: []);
    expect(ordinary.settings.single.binding, null);
  });

  test(
      'book import is singular, selection-only, and enabledSetting references a toggle',
      () {
    for (final actions in [
      [_policy(), _policy(id: 'second')],
      [
        {..._policy(), 'scope': 'context'}
      ],
      [
        {..._policy(), 'enabledSetting': 'missing'}
      ],
      [
        {..._policy(), 'surface': 'library'}
      ],
    ]) {
      expect(
          () => _parse(actions: actions), throwsA(isA<PluginInstallError>()));
    }
    expect(
        () => _parse(settings: [
              {'key': 'auto_import', 'type': 'text'}
            ], actions: [
              _policy()
            ]),
        throwsA(isA<PluginInstallError>()));
  });

  test(
      'book control options reject ambiguities and legacy hide remains compatible',
      () {
    for (final action in [
      {..._book(), 'private': 'true'},
      {..._book(), 'lockAfter': true},
      {..._book(), 'when': 'visible'},
      {..._book(), 'lockAfterSetting': 'missing'},
      {..._book(), 'command': 'privateLibrary.hide'},
    ]) {
      expect(
          () => _parse(actions: [action]), throwsA(isA<PluginInstallError>()));
    }
    final legacy = _parse(caps: [
      'library:private',
      'ui:book-action'
    ], settings: [], actions: [
      {
        'kind': 'bookAction',
        'schema': 1,
        'id': 'hide',
        'name': 'Hide',
        'command': 'privateLibrary.hide'
      }
    ]);
    expect(legacy.contributions.single, isA<BookActionContribution>());
    BookActionContributionHandler().validate(legacy, legacy.contributions);
  });
}
