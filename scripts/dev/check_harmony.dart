// Read-only readiness audit. Run from modu_app with `dart run
// scripts/dev/check_harmony.dart`. Does not fetch packages, sign, or build.
import 'dart:convert';
import 'dart:io';
import 'package:pubspec_parse/pubspec_parse.dart';

/// Missing a platform declaration is not proof that a native plugin is usable.
String ohosPluginStatus(Map<String, dynamic>? flutter) {
  final plugin = flutter?['plugin'];
  if (plugin is! Map) return 'no-plugin-declaration';
  final platforms = plugin['platforms'];
  if (platforms is! Map || !platforms.containsKey('ohos')) {
    return 'missing-ohos';
  }
  final entry = platforms['ohos'];
  if (entry is! Map) return 'invalid-ohos-declaration';
  if (entry['default_package'] is String) return 'federated-ohos';
  if (entry['pluginClass'] is String ||
      entry['dartPluginClass'] is String ||
      entry['ffiPlugin'] == true) {
    return 'declares-ohos';
  }
  return 'invalid-ohos-declaration';
}

Future<void> main(List<String> arguments) async {
  final dependenciesOnly =
      arguments.length == 1 && arguments.single == '--dependencies-only';
  if (arguments.isNotEmpty && !dependenciesOnly) {
    stderr.writeln('Run from the project root [--dependencies-only]. Set '
        'MODU_OHOS_FLUTTER and MODU_HARMONY_SDK to explicit local SDK paths.');
    exitCode = 64;
    return;
  }
  final configFile = File('.dart_tool/package_config.json').absolute;
  if (!File('pubspec.yaml').existsSync() || !configFile.existsSync()) {
    stderr.writeln(
        'Missing pubspec.yaml/package_config.json. Resolve dependencies '
        'in an isolated HarmonyOS workspace first. Nothing was changed.');
    exitCode = 1;
    return;
  }
  final app = Pubspec.parse(File('pubspec.yaml').readAsStringSync());
  final packages =
      (jsonDecode(configFile.readAsStringSync())['packages'] as List);
  final roots = <String, Uri>{
    for (final package in packages)
      package['name'] as String:
          configFile.uri.resolve(package['rootUri'] as String),
  };
  final dependencies = <String, Pubspec>{};
  final unresolved = <String>{};
  // Follow runtime dependencies, excluding dev-only lint/build plugins and
  // avoiding unrelated packages left over in the local package cache.
  void visit(String name) {
    if (dependencies.containsKey(name) || unresolved.contains(name)) return;
    final root = roots[name];
    if (root == null) {
      unresolved.add(name);
      return;
    }
    // package_config rootUri often omits the trailing slash.
    final manifest = File('${Directory.fromUri(root).path}/pubspec.yaml');
    if (!manifest.existsSync()) {
      unresolved.add(name);
      return;
    }
    final spec = Pubspec.parse(manifest.readAsStringSync());
    dependencies[name] = spec;
    for (final child in spec.dependencies.keys) {
      visit(child);
    }
  }

  for (final name in app.dependencies.keys) {
    visit(name);
  }
  final unsupported = <String>[];
  final declared = <String>[];
  final ffi = <String>[];
  final sdkConstraints = <String>[];
  for (final name in dependencies.keys.toList()..sort()) {
    final spec = dependencies[name]!;
    final status = ohosPluginStatus(spec.flutter);
    if (status == 'missing-ohos' || status == 'invalid-ohos-declaration') {
      unsupported.add(name);
    } else if (status != 'no-plugin-declaration') {
      declared.add('$name ($status)');
    }
    if (spec.dependencies.keys.any({'ffi', 'hooks', 'code_assets'}.contains)) {
      ffi.add(name);
    }
    if (app.dependencies.containsKey(name)) {
      sdkConstraints.add('$name: ${spec.environment['sdk'] ?? 'unspecified'}');
    }
  }
  final sdk = Platform.environment['MODU_OHOS_FLUTTER'];
  final nativeSdk = Platform.environment['MODU_HARMONY_SDK'];
  final checks = <String, bool>{
    'Explicit Flutter OH SDK path exists':
        sdk != null && File('$sdk/bin/flutter').existsSync(),
    if (!dependenciesOnly)
      'Explicit HarmonyOS SDK path exists':
          nativeSdk != null && Directory(nativeSdk).existsSync(),
    'App build profile exists': File('ohos/build-profile.json5').existsSync(),
    'Entry build profile exists':
        File('ohos/entry/build-profile.json5').existsSync(),
  };
  const requiredPlugins = {
    'shared_preferences',
    'path_provider',
    'sqflite',
    'flutter_inappwebview',
    'file_picker',
    'package_info_plus',
    'audio_service',
    'audio_session',
    'audioplayers',
    'url_launcher',
    'connectivity_plus',
  };
  final missingRequired = requiredPlugins.where((name) {
    final spec = dependencies[name];
    if (spec == null ||
        !{'declares-ohos', 'federated-ohos'}
            .contains(ohosPluginStatus(spec.flutter))) {
      return true;
    }
    final implementation = (spec.flutter?['plugin'] as Map?)?['platforms']
        ?['ohos']?['default_package'];
    if (implementation is! String) return false;
    final implementationSpec = dependencies[implementation];
    return implementationSpec == null ||
        ohosPluginStatus(implementationSpec.flutter) != 'declares-ohos';
  }).toList()
    ..sort();
  for (final check in checks.entries) {
    stdout.writeln('${check.value ? 'FOUND' : 'BLOCKED'}: ${check.key}');
  }
  stdout.writeln('\nResolved runtime packages: ${dependencies.length}');
  stdout.writeln(
      'Plugins without OHOS declarations (review platform guards / replacements):');
  for (final name in unsupported) {
    stdout.writeln('  $name');
  }
  stdout.writeln('Declared OHOS plugins (declaration only, not verified):');
  for (final name in declared) {
    stdout.writeln('  $name');
  }
  stdout.writeln(
      'Native/FFI dependencies needing ABI and asset-hook validation:');
  for (final name in ffi) {
    stdout.writeln('  $name');
  }
  stdout.writeln(
      'Direct dependency Dart constraints (compare with selected OH SDK):');
  for (final line in sdkConstraints) {
    stdout.writeln('  $line');
  }
  if (unresolved.isNotEmpty) {
    stdout.writeln('Unresolved: ${unresolved.join(', ')}');
  }
  if (missingRequired.isNotEmpty) {
    stdout.writeln(
        'Required adapters to integrate: ${missingRequired.join(', ')}');
  }
  stdout.writeln('\nThis audit never certifies a release. Platform channels, '
      'federated registration, native libraries, SDK/API compatibility, signing '
      'and real-device tests still require verification. No files were changed.');
  if (checks.values.any((ok) => !ok) ||
      missingRequired.isNotEmpty ||
      unresolved.isNotEmpty) {
    exitCode = 1;
  }
}
