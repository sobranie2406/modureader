import 'dart:convert';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/models/user_prompt.dart';
import 'package:modu_reader/service/plugins/plugin_contribution_handler.dart';
import 'package:modu_reader/service/plugins/plugin_contributions.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().userPrompts = [];
    await Prefs().savePluginState(PluginState.empty);
  });

  PluginManifest manifest({String version = '1.0.0', String? prompt}) =>
      PluginManifest.parse(manifestJson(
        version: version,
        contributes: [
          aiSkill(id: 'first', prompt: prompt ?? '第一段提示词'),
          aiSkill(id: 'second', enabled: false),
        ],
      ));

  test('materialises every aiSkill in manifest order with hashes', () async {
    final contributions = PluginContributions.standard();
    final applied = await contributions.apply(manifest());

    expect(applied, hasLength(2));
    expect(applied.first.id, 'plugin:com.example.prompt-pack:first');
    expect(applied.first.kind, kAiSkillContributionKind);
    expect(
      applied.first.contentSha256,
      sha256.convert(utf8.encode('第一段提示词')).toString(),
    );

    final prompts = Prefs().userPrompts;
    expect(prompts.map((prompt) => prompt.id), [
      'plugin:com.example.prompt-pack:first',
      'plugin:com.example.prompt-pack:second',
    ]);
    expect(prompts.first.order, 1);
    expect(prompts.last.order, 2);
    expect(prompts.first.enabled, isTrue);
    expect(prompts.last.enabled, isFalse);
  });

  test('appends plugin prompts after existing user prompts', () async {
    final now = DateTime.now();
    Prefs().userPrompts = [
      for (var i = 0; i < 3; i++) _prompt('user-$i', i + 5, now),
    ];
    await PluginContributions.standard().apply(manifest());
    expect(Prefs().userPrompts.first.id, 'user-0');
    expect(
        Prefs()
            .userPrompts
            .where((prompt) => prompt.id.startsWith('plugin:'))
            .map((prompt) => prompt.order),
        [8, 9]);
  });

  test('upgrade replaces owned prompts instead of duplicating them', () async {
    final contributions = PluginContributions.standard();
    await contributions.apply(manifest());

    // The host persists the registry before an upgrade.
    await Prefs().savePluginState(PluginState(plugins: [
      PluginRecord(
        id: 'com.example.prompt-pack',
        version: '1.0.0',
        name: const PluginText({'en': 'Example'}),
        license: 'CC0-1.0',
        installedAt: DateTime.now(),
        sha256: 'a' * 64,
        status: PluginStatus.enabled,
        applied: [
          AppliedContribution(
            kind: kAiSkillContributionKind,
            id: 'plugin:com.example.prompt-pack:first',
            contentSha256: sha256.convert(utf8.encode('第一段提示词')).toString(),
          ),
          AppliedContribution(
            kind: kAiSkillContributionKind,
            id: 'plugin:com.example.prompt-pack:second',
            contentSha256: 'b' * 64,
          ),
        ],
      ),
    ]));

    await contributions.apply(manifest(version: '1.1.0', prompt: '新版提示词'));
    final prompts = Prefs().userPrompts;
    expect(prompts, hasLength(2));
    expect(prompts.first.content, '新版提示词');
  });

  test('remove deletes untouched prompts and preserves edited ones', () async {
    final contributions = PluginContributions.standard();
    final applied = await contributions.apply(manifest());

    Prefs().userPrompts = [
      Prefs().userPrompts.first.copyWith(content: '用户改过'),
      Prefs().userPrompts.last,
    ];
    await contributions.remove(applied);

    final remaining = Prefs().userPrompts;
    expect(remaining, hasLength(1));
    expect(remaining.single.id, startsWith('custom-'));
    expect(remaining.single.content, '用户改过');
    expect(remaining.single.order, 0);
  });

  test('rolls back earlier handlers when a later one fails', () async {
    final first = _RecordingHandler('alpha');
    final second = _RecordingHandler('beta', fail: true);
    final contributions =
        PluginContributions(PluginContributionRegistry([first, second]));

    final manifest = PluginManifest(
      schemaVersion: 1,
      id: 'com.example.fake',
      version: '1.0.0',
      name: const PluginText({'en': 'Fake'}),
      description: const PluginText({}),
      author: null,
      license: 'MIT',
      minAppVersion: null,
      capabilities: const {},
      contributions: [
        const UnknownContribution(
          kind: 'alpha',
          schema: 1,
          id: 'one',
          index: 0,
          raw: {},
        ),
        const UnknownContribution(
          kind: 'beta',
          schema: 1,
          id: 'two',
          index: 1,
          raw: {},
        ),
      ],
      settings: const [],
      hostApi: 1,
      warnings: const [],
    );

    await expectLater(
      () => contributions.apply(manifest),
      throwsA(isA<PluginInstallError>()),
    );
    expect(first.removed, hasLength(1));
    expect(first.removed.single.id, 'com.example.fake:one');
  });
}

UserPrompt _prompt(String id, int order, DateTime now) => UserPrompt(
      id: id,
      name: id,
      content: id,
      order: order,
      createdAt: now,
      updatedAt: now,
    );

class _RecordingHandler implements PluginContributionHandler {
  _RecordingHandler(this.kind, {this.fail = false});

  @override
  final String kind;
  final bool fail;
  final List<AppliedContribution> removed = [];

  @override
  Set<String> get requiredCapabilities => const {};

  @override
  bool isApplied(AppliedContribution applied) => true;

  @override
  bool get runtimeOnly => false;

  @override
  void validate(
      PluginManifest manifest, List<PluginContribution> contributions) {}

  @override
  Future<List<AppliedContribution>> apply(
      PluginManifest manifest, List<PluginContribution> contributions) async {
    if (fail) throw const PluginInstallError(PluginErrorCode.internal, 'boom');
    return [
      for (final contribution in contributions)
        AppliedContribution(
            kind: kind,
            id: '${manifest.id}:${contribution.id}',
            contentSha256: 'hash'),
    ];
  }

  @override
  Future<void> remove(List<AppliedContribution> applied) async {
    removed.addAll(applied);
  }
}
