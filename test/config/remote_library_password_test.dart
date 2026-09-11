import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('library settings round-trip encrypted backups, never plaintext exports',
      () async {
    SharedPreferences.setMockInitialValues(
        {'sync-config-sentinel': 'unchanged'});
    await Prefs().initPrefs();
    await LibraryConnectionStore.save(const LibraryConnection(
        url: 'https://library.example.test/books/',
        username: 'reader',
        password: 'local-test-secret'));
    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup.containsKey(LibraryConnectionStore.key), isTrue);
    final publicBackup = withoutBackupCredentials(backup);
    expect(publicBackup.containsKey(LibraryConnectionStore.key), isFalse);
    expect(jsonEncode(publicBackup), isNot(contains('local-test-secret')));
    final cipher = AiSettingsSyncCipher();
    final encrypted = await cipher.encrypt(backup, 'test-backup-passphrase');
    expect(encrypted, isNot(contains('local-test-secret')));
    final restored = await cipher.decrypt(encrypted, 'test-backup-passphrase');
    expect(restored[LibraryConnectionStore.key],
        backup[LibraryConnectionStore.key]);
    final prefs = await SharedPreferences.getInstance();
    expect(
        collectAiSettingsForSync(prefs).containsKey(LibraryConnectionStore.key),
        isFalse);
    await Prefs().applyPrefsBackupMap({
      LibraryConnectionStore.key: {
        'type': 'string',
        'value': jsonEncode({
          'url': 'https://other.example.test/',
          'password': 'remote-test-secret'
        })
      }
    });
    expect(
        (await LibraryConnectionStore.load())!.password, 'remote-test-secret');
    await Prefs().applyPrefsBackupMap(Map<String, dynamic>.from(restored));
    expect(
        (await LibraryConnectionStore.load())!.password, 'local-test-secret');
    expect(prefs.getString('sync-config-sentinel'), 'unchanged');
    await LibraryConnectionStore.clear();
    expect(await LibraryConnectionStore.load(), isNull);
  });
}
