import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_catalog_signature.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:modu_reader/service/plugins/plugin_script_engine.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:modu_reader/service/plugins/plugin_trust.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

class SignedTestEngine implements PluginScriptEngine {
  String? executed;
  @override
  Future<Map<String, dynamic>> execute(
      String source, Map<String, Object?> input,
      {required PluginHostCall onCall}) async {
    executed = source;
    return {'text': input['selection']};
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = 'com.test.signed-plugin';
  late Directory temp;
  late SimpleKeyPair pair;
  late PluginCatalogSignature verifier;
  late PluginHost host;
  late PluginPaths paths;
  final ed = Ed25519();
  PluginHost makeHost() => PluginHost(
      paths: paths,
      trust: PluginTrust(signatureVerifier: verifier),
      appVersionResolver: () async => '1.3.10');
  setUp(() async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    temp = await Directory.systemTemp.createTemp('plugin-signed-updates');
    paths = PluginPaths(rootPath: '${temp.path}/plugins');
    pair = await ed.newKeyPair();
    verifier = PluginCatalogSignature(
        publicKeys: {'unit-test': (await pair.extractPublicKey()).bytes});
    host = makeHost();
    await host.initialize();
  });
  tearDown(() async {
    if (host.byId(id) != null) await host.uninstall(id);
    host.dispose();
    await temp.delete(recursive: true);
  });
  Map<String, String> files(String version) => {
        'manifest.json': manifestJson(
            id: id,
            version: version,
            minAppVersion: '1.3.10',
            capabilities: [
              'script:run',
              'ui:selection-action'
            ],
            contributes: [
              {
                'kind': 'scriptAction',
                'schema': 1,
                'id': 'run',
                'name': 'Test',
                'entry': 'main.js',
                'surface': 'selection'
              }
            ]),
        'main.js': 'return {text: input.selection}; // $version',
        'LICENSE': 'CC0-1.0\n',
      };
  Future<String> certificate(
      String version, Map<String, String> sources) async {
    final payload = utf8.encode(jsonEncode({
      'schemaVersion': 1,
      'repository': PluginTrust.projectSource,
      'plugins': [
        {
          'id': id,
          'version': version,
          'status': 'reviewed',
          'files': sources.map((name, content) => MapEntry(
              name, hashes.sha256.convert(utf8.encode(content)).toString())),
          'review': {
            'reviewer': 'Unit test',
            'kind': 'test',
            'reviewedAt': '2026-11-14T00:00:00Z'
          },
        }
      ]
    }));
    final signature = await ed.sign(payload, keyPair: pair);
    return jsonEncode({
      'schemaVersion': 1,
      'algorithm': 'Ed25519',
      'keyId': 'unit-test',
      'payload': base64Encode(payload),
      'signature': base64Encode(signature.bytes)
    });
  }

  test(
      'new plugin, update and offline restart work without changing the app version',
      () async {
    final first = files('1.0.0');
    final zip = await writePluginZip(temp, first);
    await expectLater(
        host.install(zip),
        throwsA(isA<PluginInstallError>()
            .having((e) => e.code, 'code', PluginErrorCode.untrustedPackage)));
    await host.trust.acceptCatalog(await certificate('1.0.0', first));
    await host.install(zip);
    final second = files('1.1.0');
    await host.trust.acceptCatalog(await certificate('1.1.0', second));
    await host.install(await writePluginZip(temp, second));
    expect(host.appVersion, '1.3.10');
    expect(host.byId(id)!.version, '1.1.0');
    host.dispose();
    host = makeHost();
    await host.initialize();
    expect(host.byId(id)!.status, PluginStatus.enabled);
    expect(await host.trust.reviewedFiles(id, '1.0.0'), isNotNull,
        reason: 'the earlier review proof survives a catalog update');
    final engine = SignedTestEngine();
    final runtime =
        PluginScriptRuntime(host: host, engineFactory: () => engine);
    final action = host
        .manifestFor(id)!
        .contributions
        .whereType<ScriptActionContribution>()
        .single;
    expect(
        await runtime.run(
            pluginId: id,
            action: action,
            input: {'selection': 'unchanged app'}),
        {'text': 'unchanged app'});
    expect(engine.executed, second['main.js']);
    runtime.dispose();
  });
  test('tampered cached proof cannot approve an installed plugin after restart',
      () async {
    final source = files('1.0.0');
    await host.trust.acceptCatalog(await certificate('1.0.0', source));
    await host.install(await writePluginZip(temp, source));
    await File('${paths.root.path}/.catalog-proofs/$id@1.0.0.json')
        .writeAsString('{}');
    host.dispose();
    host = makeHost();
    await host.initialize();
    expect(host.byId(id)!.status, PluginStatus.broken);
  });
  test('unsigned reviews and rewriting an existing version cannot expand trust',
      () async {
    final source = files('1.0.0');
    await expectLater(
        host.trust.acceptCatalog('{}'), throwsA(isA<FormatException>()));
    await host.trust.acceptCatalog(await certificate('1.0.0', source));
    final changed = {...source, 'main.js': 'return {text:"changed"};'};
    await expectLater(
        host.trust.acceptCatalog(await certificate('1.0.0', changed)),
        throwsA(isA<PluginInstallError>()));
    await expectLater(host.install(await writePluginZip(temp, changed)),
        throwsA(isA<PluginInstallError>()));
  });
}
