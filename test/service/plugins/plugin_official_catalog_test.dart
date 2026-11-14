import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_state.dart';
import 'package:modu_reader/service/plugins/plugin_catalog.dart';
import 'package:modu_reader/service/plugins/plugin_catalog_signature.dart';
import 'package:modu_reader/service/plugins/plugin_host.dart';
import 'package:modu_reader/service/plugins/plugin_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'published signed catalog admits both optional plugins with the production key',
      () async {
    SharedPreferences.setMockInitialValues(
        {'experimentalPluginsEnabled': true});
    await Prefs().initPrefs();
    final temp =
        await Directory.systemTemp.createTemp('official-plugin-review');
    final host = PluginHost(
        paths: PluginPaths(rootPath: '${temp.path}/plugins'),
        appVersionResolver: () async => '1.3.10');
    final ids = <String>[];
    try {
      await host.initialize();
      final envelope =
          await File('test/fixtures/plugins/catalog-published.signed.json')
              .readAsString();
      final catalog = await PluginCatalogSignature().decode(envelope);
      final entries = PluginCatalog.parse(jsonEncode(catalog));
      await host.trust.acceptCatalog(envelope);
      for (final name in ['dictionary-transform', 'web-clipper']) {
        final sources = <String, String>{};
        await for (final file
            in Directory('test/fixtures/plugins/$name').list()) {
          if (file is File) {
            sources[file.uri.pathSegments.last] = await file.readAsString();
          }
        }
        final manifest = PluginManifest.parse(sources['manifest.json']!);
        final entry = entries.singleWhere((entry) => entry.id == manifest.id);
        expect(entry.requiresAppUpdate('1.3.10'), false);
        expect(entry.requiresAppUpdate('1.3.9'), true);
        await host.install(await writePluginZip(temp, sources));
        ids.add(manifest.id);
        expect(host.byId(manifest.id)!.status, PluginStatus.enabled);
        expect(
            host.manifestFor(manifest.id)!.capabilities,
            contains(name == 'dictionary-transform'
                ? kDictionaryTransformCapability
                : kArticleCaptureCapability));
        expect(await host.trust.reviewedFiles(manifest.id, manifest.version),
            isNotNull);
      }
    } finally {
      for (final id in ids) {
        await host.uninstall(id);
      }
      host.dispose();
      await temp.delete(recursive: true);
    }
  });
}
