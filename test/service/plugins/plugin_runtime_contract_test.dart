// The reason messages are assembled from adjacent literals so each one stays
// readable next to the regex it explains.
// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/service/plugins/plugin_script_runtime.dart';
import 'package:path/path.dart' as p;

/// Accepted in a manifest but never stored as a grant.
const String kPluginStorageCapability = 'storage:plugin';

/// The three places that have to agree for a plugin call to work:
///
/// 1. ../assets/plugin-runtime/runtime.js — what the worker can actually call;
/// 2. [kPluginMethodCapabilities] — what the Dart host authorises;
/// 3. the package manifest — what the user was shown and granted.
///
/// They drifted once: storage.* was implemented in Dart and documented, but
/// never exposed on modu, so every plugin that saved anything failed with
/// "the plugin could not run". These tests fail loudly on that class of bug
/// instead of leaving it for a reader to hit.
void main() {
  final runtime = File('assets/plugin-runtime/runtime.js').readAsStringSync();

  /// Every request('group.method') the bootstrap can issue.
  Set<String> exposedMethods() {
    final matches = RegExp(r"request\('([a-z][a-zA-Z]*\.[a-zA-Z]+)'")
        .allMatches(runtime);
    return {for (final match in matches) match.group(1)!};
  }

  /// Every name:Object.freeze namespace the bootstrap publishes.
  Set<String> exposedNamespaces() {
    final matches =
        RegExp(r'^\s+([a-z][a-zA-Z]*):Object\.freeze', multiLine: true)
            .allMatches(runtime);
    return {for (final match in matches) match.group(1)!};
  }

  test('every host method is reachable from the script runtime', () {
    final missing = kPluginMethodCapabilities.keys.toSet()
        .difference(exposedMethods());
    expect(missing, isEmpty,
        reason: 'implemented in Dart but missing on modu.*, so no plugin can '
            'call them: ' + missing.join(', '));
  });

  test('the runtime exposes nothing the host would refuse', () {
    final extra =
        exposedMethods().difference(kPluginMethodCapabilities.keys.toSet());
    expect(extra, isEmpty,
        reason: 'exposed to plugins but unimplemented, so every call fails: ' +
            extra.join(', '));
  });

  test('each namespace a method names is actually published', () {
    final namespaces = exposedNamespaces();
    final used = {
      for (final method in exposedMethods()) method.split('.').first,
    };
    expect(used.difference(namespaces), isEmpty,
        reason: 'a method exists but its modu.* namespace does not');
  });

  test('every reachable method maps to a known capability', () {
    for (final entry in kPluginMethodCapabilities.entries) {
      expect(kKnownCapabilities, contains(entry.value),
          reason: entry.key +
              ' maps to ' +
              entry.value +
              ', which no manifest can declare');
    }
  });

  test('the storage namespace is published, not just implemented', () {
    // The regression this file exists for.
    for (final method in [
      'storage.list',
      'storage.read',
      'storage.write',
      'storage.remove',
    ]) {
      expect(kPluginMethodCapabilities, contains(method));
      expect(exposedMethods(), contains(method));
    }
    expect(exposedNamespaces(), contains('storage'));
  });

  test('every method a documented example calls is declared and exposed', () {
    final exposed = exposedMethods();
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
            in RegExp(r'modu\.([a-z][a-zA-Z]*\.[a-zA-Z]+)').allMatches(source)) {
          final method = call.group(1)!;
          final where = directory.path + '/' + action.entry;
          // Every called method must be exposed by the runtime...
          expect(exposed, contains(method),
              reason: where + ' calls ' + method +
                  ', which the runtime does not expose');
          // ...and the package must declare what that method requires.
          final capability = kPluginMethodCapabilities[method];
          expect(capability, isNotNull,
              reason: method + ' has no capability mapping');
          // storage:plugin is implicit: every plugin owns its directory, so the
          // parser deliberately drops the token from the parsed set. A package
          // still names it in the manifest for documentation, and the host
          // accepts it either way.
          if (capability == kPluginStorageCapability) continue;
          expect(manifest.capabilities, contains(capability),
              reason: where + ' calls ' + method + ', which needs ' +
                  capability! + ', but the manifest does not declare it');
        }
      }
    }
  });
}
