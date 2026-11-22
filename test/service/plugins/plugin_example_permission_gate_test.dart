import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:path/path.dart' as p;

/// Drives every documented example script the way a fresh device would:
/// every runtime capability starts **denied**, and only an explicit
/// permissions.request makes one usable.
///
/// This is the scenario that was broken. The examples called their host APIs
/// straight away, so on a device where nothing had been granted yet they threw
/// on the first call and the reader saw only "the plugin could not run". A
/// plugin must ask before it uses, and this test fails if it forgets.
void main() {
  /// Capabilities a manifest grants by installing rather than by consent.
  /// Mirrors PluginPermissionTier.install; kept literal so this test does not
  /// depend on the UI catalogue.
  const installTier = {
    'script:run',
    'ui:selection-action',
    'ui:book-action',
    'ai:prompt-pack',
    'settings:device',
    'dictionary:transform',
    'article:capture',
    'article:extract',
    'library:private',
    'library:private-control',
    'library:private-policy',
    'storage:plugin',
  };

  test('every example asks for what it needs before using it', () {
    // The Node harness is the executable version of this contract and runs in
    // CI-adjacent workflows; this test guards the source shape so a regression
    // is caught even where Node is unavailable.
    final examples = Directory('docs/examples/plugins');
    final offenders = <String>[];
    for (final directory in examples
        .listSync()
        .whereType<Directory>()
        .where((dir) => File(p.join(dir.path, 'manifest.json')).existsSync())) {
      final manifest = PluginManifest.parse(
          File(p.join(directory.path, 'manifest.json')).readAsStringSync());
      for (final action
          in manifest.contributions.whereType<ScriptActionContribution>()) {
        final source =
            File(p.join(directory.path, action.entry)).readAsStringSync();
        final calls = RegExp(r'modu\.([a-z][a-zA-Z]*\.[a-zA-Z]+)')
            .allMatches(source)
            .map((match) => match.group(1)!)
            .where((method) => method != 'permissions.request')
            .where((method) => method != 'permissions.status')
            .where((method) =>
                !installTier.contains(kPluginMethodCapabilities[method]))
            .toSet();
        if (calls.isEmpty) continue;
        // Any script touching a runtime capability must gate on consent first.
        if (!source.contains('permissions.request')) {
          offenders.add(
              '${p.join(directory.path, action.entry)} uses '
              '${calls.join(', ')} without asking for consent');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these examples would fail on a device where nothing is '
            'granted yet:\n${offenders.join('\n')}');
  });

  test('every example maps its calls to capabilities it declares', () {
    final examples = Directory('docs/examples/plugins');
    for (final directory in examples
        .listSync()
        .whereType<Directory>()
        .where((dir) => File(p.join(dir.path, 'manifest.json')).existsSync())) {
      final manifest = PluginManifest.parse(
          File(p.join(directory.path, 'manifest.json')).readAsStringSync());
      for (final action
          in manifest.contributions.whereType<ScriptActionContribution>()) {
        final source =
            File(p.join(directory.path, action.entry)).readAsStringSync();
        for (final call
            in RegExp(r'modu\.[a-z]+\.[a-zA-Z]+').allMatches(source)) {
          final capability =
              kPluginMethodCapabilities[call.group(0)!.substring(5)];
          // storage:plugin is implicit: declared for documentation, dropped from
          // the parsed set, and granted by installing.
          if (capability == null || kImplicitCapabilities.contains(capability)) {
            continue;
          }
          expect(manifest.capabilities, contains(capability),
              reason: '${p.join(directory.path, action.entry)} calls '
                  '${call.group(0)!}, which needs $capability');
        }
      }
    }
  });
}
