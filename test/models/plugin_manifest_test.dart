import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import '../service/plugins/plugin_test_utils.dart';

void main() {
  PluginManifest parse(String manifest,
          {Set<String> allowed = kP1SupportedCapabilities}) =>
      PluginManifest.parse(manifest, allowedCapabilities: allowed);

  test('parses a valid package with contributions and settings', () {
    final manifest = parse(manifestJson(settings: [
      {
        'key': 'tone',
        'type': 'select',
        'options': ['brief', 'detailed']
      },
      {'key': 'max_words', 'type': 'number', 'defaultValue': 300},
      {'key': 'enabled', 'type': 'toggle', 'defaultValue': true},
      {'key': 'hint', 'type': 'tip'},
    ]));
    expect(manifest.id, 'com.example.prompt-pack');
    expect(manifest.version, '1.0.0');
    expect(manifest.license, 'CC0-1.0');
    expect(manifest.capabilities, {'ai:prompt-pack'});
    expect(manifest.contributions, hasLength(2));
    expect(manifest.contributions.first, isA<AiSkillContribution>());
    expect(manifest.settings, hasLength(4));
    expect(manifest.warnings, isEmpty);
    expect(manifest.hostApi, 1);
  });

  test('rejects missing or invalid required fields', () {
    expect(
      () => parse(manifestJson(license: '')),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.missingLicense)),
    );
    expect(
      () => parse(manifestJson(version: '1.0')),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidVersion)),
    );
    expect(
      () => parse(manifestJson(id: 'Bad Id')),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidPluginId)),
    );
    expect(
      () => parse(manifestJson(schemaVersion: 2)),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.unsupportedSchema)),
    );
    expect(
      () => parse(manifestJson(hostApi: 2)),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.unsupportedHostApi)),
    );
  });

  test('rejects unknown abilities but ignores unknown contribution kinds', () {
    expect(
      () =>
          parse(manifestJson(capabilities: ['ai:prompt-pack', 'camera:read'])),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.unknownCapability)),
    );
    // net:http became supported in P3a, so the "known but unavailable" example
    // is now script:run. Declaring net:http alone is still rejected, because a
    // network capability without a network block cannot be honoured.
    expect(
      () => parse(manifestJson(capabilities: ['script:run'])),
      throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
          PluginErrorCode.capabilityUnavailable)),
    );
    expect(
      () => parse(manifestJson(capabilities: ['net:http'])),
      throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
          PluginErrorCode.invalidManifest)),
    );
    final toolbar = parse(manifestJson(
      capabilities: ['ai:prompt-pack', 'ui:selection-action'],
      contributes: [selectionAction(id: 'explain')],
    ));
    expect(toolbar.capabilities, {'ai:prompt-pack', 'ui:selection-action'});
    expect(toolbar.contributions.single, isA<SelectionActionContribution>());

    final manifest = parse(manifestJson(contributes: [
      {
        'kind': 'futureThing',
        'schema': 1,
        'id': 'future',
        'anything': true,
      },
      aiSkill(id: 'known'),
    ]));
    expect(manifest.contributions, hasLength(2));
    expect(manifest.contributions.first, isA<UnknownContribution>());
    expect(manifest.warnings, hasLength(1));
    expect(manifest.warnings.single, contains('futureThing'));
  });

  test('accepts the implicit storage capability without storing it', () {
    final manifest =
        parse(manifestJson(capabilities: ['ai:prompt-pack', 'storage:plugin']));
    expect(manifest.capabilities, {'ai:prompt-pack'});
  });

  test('localises names with exact, prefix, English and first-value fallback',
      () {
    final manifest = parse(manifestJson(name: const {
      'zh-CN': '中文名',
      'en': 'English name',
    }));
    expect(manifest.name.resolve('zh-CN'), '中文名');
    expect(manifest.name.resolve('zh-Hans'), '中文名');
    expect(manifest.name.resolve('zh-TW'), '中文名');
    expect(manifest.name.resolve('fr'), 'English name');
    expect(manifest.name.resolve(null), 'English name');

    final noEnglish = PluginText.parse(const {'de': 'Deutsch'}, field: 'name');
    expect(noEnglish.resolve('fr'), 'Deutsch');
  });

  test('enforces prompt length, name length and contribution caps', () {
    expect(
      () => parse(manifestJson(contributes: [aiSkill(prompt: 'x' * 8001)])),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.promptTooLong)),
    );
    expect(
      () => parse(manifestJson(name: 'x' * 41)),
      throwsA(isA<PluginInstallError>()
          .having((error) => error.code, 'code', PluginErrorCode.nameTooLong)),
    );
    final tooMany = List.generate(31, (index) => aiSkill(id: 'skill-$index'));
    expect(
      () => parse(manifestJson(contributes: tooMany)),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.tooManyContributions)),
    );
    expect(
      () => parse(manifestJson(contributes: [
        aiSkill(id: 'dup'),
        aiSkill(id: 'dup'),
      ])),
      throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
          PluginErrorCode.duplicateContribution)),
    );
  });

  test('setting schema is parsed strictly and password is not supported', () {
    expect(
      () => parse(manifestJson(settings: [
        {'key': 'key', 'type': 'password'}
      ])),
      throwsA(isA<PluginInstallError>().having((error) => error.code, 'code',
          PluginErrorCode.unsupportedSettingType)),
    );
    expect(
      () => parse(manifestJson(settings: [
        {'key': 'key', 'type': 'select', 'options': []}
      ])),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidSetting)),
    );
    expect(
      () => parse(manifestJson(settings: [
        {'key': 'dup', 'type': 'tip'},
        {'key': 'dup', 'type': 'tip'},
      ])),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.duplicateSetting)),
    );
  });

  test('minAppVersion is compared without build metadata', () {
    final manifest = parse(manifestJson(minAppVersion: '1.3.1'));
    expect(() => manifest.ensureCompatibleWith('1.3.1+10152'), returnsNormally);
    expect(() => manifest.ensureCompatibleWith('1.4.0'), returnsNormally);
    expect(
      () => manifest.ensureCompatibleWith('1.3.0+999'),
      throwsA(isA<PluginInstallError>()
          .having((error) => error.code, 'code', PluginErrorCode.appTooOld)),
    );
  });

  test('manifest size and JSON shape are bounded', () {
    final huge = ' ' * (PluginLimits.maxManifestBytes + 1);
    expect(
      () => parse(huge),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.manifestTooLarge)),
    );
    expect(
      () => parse('[]'),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidManifest)),
    );
    expect(
      () => parse('{'),
      throwsA(isA<PluginInstallError>().having(
          (error) => error.code, 'code', PluginErrorCode.invalidManifest)),
    );
  });
}
