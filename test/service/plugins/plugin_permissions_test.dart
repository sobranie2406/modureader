import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/models/plugin_manifest.dart';
import 'package:modu_reader/models/plugin_permissions.dart';
import 'package:modu_reader/service/plugins/plugin_permissions.dart';

import 'plugin_test_utils.dart';

void main() {
  group('permission catalogue', () {
    test('every new capability has a catalogue entry', () {
      // A token without a spec would be silently treated as runtime-tier and
      // render as its raw name, so the two lists must stay in step.
      for (final capability in kKnownCapabilities) {
        expect(pluginPermissionSpec(capability), isNotNull,
            reason: 'no catalogue entry for $capability');
      }
    });

    test('catalogue tokens are all known capabilities', () {
      for (final spec in kPluginPermissions) {
        expect(kKnownCapabilities, contains(spec.token));
      }
    });

    test('catalogue tokens match the capability pattern', () {
      final pattern = RegExp(r'^[a-z][a-z0-9-]*:[a-z][a-z0-9-]*$');
      for (final spec in kPluginPermissions) {
        expect(pattern.hasMatch(spec.token), isTrue,
            reason: '${spec.token} is not a capability token');
      }
    });

    test('unknown tokens are runtime-tier, so a newer package fails closed',
        () {
      expect(isRuntimePermission('future:thing'), isTrue);
      expect(pluginPermissionSpec('future:thing'), isNull);
    });

    test('install-tier capabilities are never runtime-grantable', () {
      for (final capability in ['script:run', 'ai:prompt-pack']) {
        expect(isRuntimePermission(capability), isFalse);
      }
    });
  });

  group('grant store', () {
    PluginManifest manifest(List<String> capabilities) =>
        PluginManifest.parse(manifestJson(
            id: 'com.example.perms', capabilities: capabilities));

    test('requestedRuntime keeps only runtime-tier declarations', () {
      final parsed = manifest(
          ['ai:prompt-pack', 'ai:invoke', 'clipboard:write', 'script:run']);
      expect(PluginPermissions.requestedRuntime(parsed),
          {'ai:invoke', 'clipboard:write'});
      expect(PluginPermissions.installTier(parsed),
          {'ai:prompt-pack', 'script:run'});
    });

    test('a capability is denied until it is granted', () {
      final parsed = manifest(['ai:invoke']);
      expect(PluginPermissions.allows(const {}, parsed.id, 'ai:invoke'),
          isFalse);
      expect(
          PluginPermissions.allows({
            parsed.id: {'ai:invoke'}
          }, parsed.id, 'ai:invoke'),
          isTrue);
    });

    test('install-tier capabilities are allowed without a grant', () {
      expect(PluginPermissions.allows(const {}, 'any', 'script:run'), isTrue);
    });

    test('encode/decode round-trips and sorts deterministically', () {
      final encoded = PluginPermissions.encode({
        'b.plugin': {'clipboard:write', 'ai:invoke'},
        'a.plugin': {'note:read'},
        'empty.plugin': <String>{},
      });
      expect(encoded, contains('"a.plugin"'));
      expect(encoded, isNot(contains('empty.plugin')));
      final decoded = PluginPermissions.decode(jsonDecode(encoded));
      expect(decoded['b.plugin'], {'clipboard:write', 'ai:invoke'});
      expect(decoded['a.plugin'], {'note:read'});
      expect(decoded.containsKey('empty.plugin'), isFalse);
    });

    test('decode rejects an install-tier capability in the store', () {
      expect(
          () => PluginPermissions.decode({
                'com.example.plugin': ['script:run']
              }),
          throwsFormatException);
    });

    test('decode rejects an unknown capability', () {
      expect(
          () => PluginPermissions.decode({
                'com.example.plugin': ['made:up']
              }),
          throwsFormatException);
    });

    test('decode rejects an invalid plugin id', () {
      expect(() => PluginPermissions.decode({'NOT VALID': ['ai:invoke']}),
          throwsFormatException);
    });

    test('prune drops a capability the new version no longer declares', () {
      final grants = {
        'com.example.perms': {'ai:invoke', 'clipboard:read'},
      };
      final pruned =
          PluginPermissions.prune(grants, manifest(['clipboard:read']));
      expect(pruned['com.example.perms'], {'clipboard:read'});
    });

    test('prune removes the plugin entirely when nothing survives', () {
      final grants = {
        'com.example.perms': {'ai:invoke'},
      };
      final pruned = PluginPermissions.prune(grants, manifest(['note:read']));
      expect(pruned.containsKey('com.example.perms'), isFalse);
    });

    test('legacy grants cover only capabilities that shipped before grants',
        () {
      final parsed =
          manifest(['library:read', 'note:write', 'ai:invoke', 'clipboard:read']);
      expect(PluginPermissions.legacyGrants(parsed),
          {'library:read', 'note:write'});
      // A capability that never shipped before manual grants is not seeded.
      expect(PluginPermissions.legacyGrants(parsed), isNot(contains('ai:invoke')));
    });
  });
}
