import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_permissions.dart';
import 'package:path/path.dart' as p;

/// The example packages under docs/examples/plugins are the worked examples of
/// the P6 host API. They must stay installable, so this test validates every
/// manifest against the real parser and asserts the contract each example
/// claims to demonstrate.
void main() {
  final root = Directory('docs/examples/plugins');
  final directories = root
      .listSync()
      .whereType<Directory>()
      .where((dir) => File(p.join(dir.path, 'manifest.json')).existsSync())
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('the example plugins exist', () {
    expect(directories, isNotEmpty);
  });

  for (final directory in directories) {
    final name = p.basename(directory.path);

    group('example: $name', () {
      late PluginManifest manifest;

      setUpAll(() {
        final raw = File(p.join(directory.path, 'manifest.json')).readAsStringSync();
        manifest = PluginManifest.parse(raw);
      });

      test('parses with no forward-compatibility warnings', () {
        expect(manifest.id, matches(pluginIdPattern));
        expect(manifest.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
        expect(manifest.license, isNotEmpty);
        expect(manifest.warnings, isEmpty);
        expect(manifest.contributions.whereType<UnknownContribution>(), isEmpty);
      });

      test('declares a README, licence and every script entry', () {
        for (final file in ['README.md', 'LICENSE']) {
          expect(File(p.join(directory.path, file)).existsSync(), isTrue,
              reason: '$name needs $file');
        }
        for (final action
            in manifest.contributions.whereType<ScriptActionContribution>()) {
          final entry = File(p.join(directory.path, action.entry));
          expect(entry.existsSync(), isTrue,
              reason: '$name declares ${action.entry}');
          expect(entry.lengthSync(), lessThanOrEqualTo(
              PluginLimits.maxScriptBytes));
        }
      });

      test('uses only capabilities the host understands', () {
        for (final capability in manifest.capabilities) {
          expect(kKnownCapabilities, contains(capability));
          expect(pluginPermissionSpec(capability), isNotNull,
              reason: 'no permission catalogue entry for $capability');
        }
      });

      test('a scripted example ships its scripts and declares script:run', () {
        final scripts =
            manifest.contributions.whereType<ScriptActionContribution>();
        // prompt-pack predates the script host and stays the declarative
        // sample; everything newer must actually run code.
        if (scripts.isEmpty) {
          expect(manifest.capabilities, contains(kAiPromptPackCapability),
              reason: 'only the declarative sample may ship without scripts');
          return;
        }
        expect(manifest.capabilities, contains(kScriptRunCapability));
        for (final action in scripts) {
          expect(action.entry.endsWith('.js'), isTrue);
        }
      });

      test('script files stay plain ES5 and call no browser API', () {
        for (final action
            in manifest.contributions.whereType<ScriptActionContribution>()) {
          final source = File(p.join(directory.path, action.entry))
              .readAsStringSync();
          // The runtime is a Worker without a DOM; these would fail at run time.
          for (final forbidden in [
            'document.',
            'window.',
            'localStorage',
            'XMLHttpRequest',
            'fetch(',
            'importScripts',
          ]) {
            expect(source.contains(forbidden), isFalse,
                reason: '${action.entry} must not use $forbidden');
          }
          // Arrow functions and const/let are not guaranteed on old WebViews.
          expect(source.contains('=>'), isFalse,
              reason: '${action.entry} should stay ES5');
        }
      });
    });
  }
}
