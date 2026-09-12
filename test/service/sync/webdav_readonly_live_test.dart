import 'dart:convert';
import 'dart:io';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:anx_reader/service/sync/sync_paths.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit opt-in only. Credentials are inherited privately in the process
// environment, never supplied in command-line arguments or printed.
void main() {
  test('authorized configured WebDAV read-only metadata probe', () async {
    final raw = Platform.environment['MODU_WEBDAV_READONLY_CONFIG']!;
    final config = jsonDecode(raw) as Map;
    final client = WebdavClient(
        url: config['url'] as String,
        username: config['username'] as String,
        password: config['password'] as String);
    String? previous;
    for (var round = 1; round <= 3; round++) {
      try {
        await client.ping();
        final metadata =
            await client.readProps(SyncPaths.database('database8.db'));
        if (metadata == null) fail('Configured database not present');
        final strong = WebdavClient.isStrongETag(metadata.eTag);
        print(
            'MODU_WEBDAV_READONLY round=$round authenticated=true strong_etag=$strong stable=${round == 1 || previous == metadata.eTag}');
        expect(strong, isTrue, reason: 'Strong validator was not returned');
        previous = metadata.eTag;
      } catch (error) {
        fail(
            'Read-only probe failed: ${error.runtimeType} (private details omitted)');
      }
    }
  }, skip: !Platform.environment.containsKey('MODU_WEBDAV_READONLY_CONFIG'));
}
