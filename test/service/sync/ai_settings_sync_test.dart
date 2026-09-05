import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('API key sync is opt-in and its password stays out of app backups',
      () async {
    SharedPreferences.setMockInitialValues({
      'syncAiSettingsEncryptionPassword': 'local-only-password',
      'themeMode': 'dark',
    });
    await Prefs().initPrefs();

    expect(Prefs().syncAiSettingsToWebdav, isFalse);
    expect(
      await Prefs().buildPrefsBackupMap(),
      isNot(contains('syncAiSettingsEncryptionPassword')),
    );
    await Prefs().applyPrefsBackupMap({
      'syncAiSettingsToWebdav': {'type': 'bool', 'value': true},
    });
    expect(Prefs().syncAiSettingsToWebdav, isFalse);
  });

  group('AI settings sync preference filter', () {
    test('includes AI service credentials but excludes unrelated secrets',
        () async {
      SharedPreferences.setMockInitialValues({
        'aiProviders': jsonEncode([
          {
            'id': 'provider-1',
            'apiKeys': [
              {'id': 'key-1', 'key': 'chat-secret'}
            ],
            'keyIndex': 4,
            'updatedAt': '2026-09-03T10:00:00.000Z',
          }
        ]),
        'vectorModelConfig': jsonEncode({'apiKey': 'vector-secret'}),
        'onlineTtsConfig_openai': jsonEncode({'key': 'tts-secret'}),
        'translateServiceConfig_deepl':
            jsonEncode({'api_key': 'translation-secret'}),
        'webdavInfo': jsonEncode({'password': 'dav-secret'}),
        'themeMode': 'dark',
        'syncAiSettingsEncryptionPassword': 'local-only-password',
      });
      final preferences = await SharedPreferences.getInstance();

      final snapshot = collectAiSettingsForSync(preferences);

      expect(snapshot, contains('aiProviders'));
      expect(snapshot, contains('vectorModelConfig'));
      expect(snapshot, contains('onlineTtsConfig_openai'));
      expect(snapshot, contains('translateServiceConfig_deepl'));
      expect(snapshot, isNot(contains('webdavInfo')));
      expect(snapshot, isNot(contains('themeMode')));
      expect(
        snapshot,
        isNot(contains('syncAiSettingsEncryptionPassword')),
      );

      final providers = jsonDecode(snapshot['aiProviders']! as String) as List;
      expect(providers.single, isNot(contains('keyIndex')));
      expect(providers.single, isNot(contains('updatedAt')));
      expect(
        ((providers.single as Map)['apiKeys'] as List).single['key'],
        'chat-secret',
      );
    });
  });

  group('AiSettingsSyncCipher', () {
    test('encrypts and authenticates the complete payload', () async {
      final cipher = AiSettingsSyncCipher();
      final clearText = <String, Object?>{
        'aiProviders': '[{"apiKeys":[{"key":"sk-secret"}]}]',
        'aiTemperature': 0.6,
      };

      final encrypted = await cipher.encrypt(
        clearText,
        'a-strong-sync-password',
      );

      expect(encrypted, isNot(contains('sk-secret')));
      expect(jsonDecode(encrypted)['algorithm'], 'AES-256-GCM');
      expect(
        await cipher.decrypt(encrypted, 'a-strong-sync-password'),
        clearText,
      );
      expect(
        () => cipher.decrypt(encrypted, 'the-wrong-password'),
        throwsA(isA<AiSyncDecryptionException>()),
      );
    });
  });

  group('AiSettingsSyncService', () {
    late Database database;

    setUp(() async {
      sqfliteFfiInit();
      database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    });

    tearDown(() async {
      await database.close();
    });

    test('does not create a sync table while the separate switch is off',
        () async {
      SharedPreferences.setMockInitialValues({'aiProviders': 'sensitive'});
      final preferences = await SharedPreferences.getInstance();
      final service = AiSettingsSyncService(
        databaseProvider: () async => database,
        preferences: preferences,
      );

      expect(
        await service.prepareLocalDatabase(enabled: false, password: null),
        isFalse,
      );
      final tables = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [aiSettingsSyncTable],
      );
      expect(tables, isEmpty);
    });

    test('switching sync off preserves an existing encrypted record', () async {
      SharedPreferences.setMockInitialValues({'aiProviders': 'sensitive'});
      final preferences = await SharedPreferences.getInstance();
      final service = AiSettingsSyncService(
        databaseProvider: () async => database,
        preferences: preferences,
      );
      await service.prepareLocalDatabase(
        enabled: true,
        password: 'correct-password-123',
      );
      final before = await database.query(aiSettingsSyncTable);

      expect(
        await service.prepareLocalDatabase(enabled: false, password: null),
        isFalse,
      );
      expect(await database.query(aiSettingsSyncTable), before);
      expect(
        await service.restoreFromDownloadedDatabase(
          enabled: false,
          password: null,
        ),
        isFalse,
      );
      expect(await database.query(aiSettingsSyncTable), before);
    });

    test('stores only ciphertext and restores the selected AI settings',
        () async {
      SharedPreferences.setMockInitialValues({
        'aiProviders': '[{"id":"remote","apiKeys":[{"key":"sk-db"}]}]',
        'selectedAiService': 'remote',
        'themeMode': 'dark',
      });
      final preferences = await SharedPreferences.getInstance();
      final service = AiSettingsSyncService(
        databaseProvider: () async => database,
        preferences: preferences,
      );

      expect(
        await service.prepareLocalDatabase(
          enabled: true,
          password: 'a-strong-sync-password',
        ),
        isTrue,
      );
      final rows = await database.query(aiSettingsSyncTable);
      final encryptedPayload = rows.single['encrypted_payload']! as String;
      expect(encryptedPayload, isNot(contains('sk-db')));

      await preferences.setString(
        'aiProviders',
        '[{"id":"local","apiKeys":[{"key":"local-key"}]}]',
      );
      await preferences.setString('selectedAiService', 'local');
      await preferences.setString('aiConfig_stale', 'stale');

      expect(
        await service.restoreFromDownloadedDatabase(
          enabled: true,
          password: 'a-strong-sync-password',
        ),
        isTrue,
      );
      expect(preferences.getString('aiProviders'), contains('sk-db'));
      expect(preferences.getString('selectedAiService'), 'remote');
      expect(preferences.containsKey('aiConfig_stale'), isFalse);
      expect(preferences.getString('themeMode'), 'dark');
    });

    test('wrong password does not overwrite local AI settings', () async {
      SharedPreferences.setMockInitialValues({
        'aiProviders': '[{"id":"remote"}]',
      });
      final preferences = await SharedPreferences.getInstance();
      final service = AiSettingsSyncService(
        databaseProvider: () async => database,
        preferences: preferences,
      );
      await service.prepareLocalDatabase(
        enabled: true,
        password: 'correct-password-123',
      );
      await preferences.setString('aiProviders', '[{"id":"local"}]');

      await expectLater(
        service.restoreFromDownloadedDatabase(
          enabled: true,
          password: 'wrong-password-1234',
        ),
        throwsA(isA<AiSyncDecryptionException>()),
      );
      expect(preferences.getString('aiProviders'), contains('local'));
    });

    test('wrong password cannot replace the encrypted database payload',
        () async {
      SharedPreferences.setMockInitialValues({
        'aiProviders': '[{"id":"remote"}]',
      });
      final preferences = await SharedPreferences.getInstance();
      final service = AiSettingsSyncService(
        databaseProvider: () async => database,
        preferences: preferences,
      );
      await service.prepareLocalDatabase(
        enabled: true,
        password: 'correct-password-123',
      );
      final before = (await database.query(aiSettingsSyncTable))
          .single['encrypted_payload'];
      await preferences.setString('aiProviders', '[{"id":"local"}]');

      await expectLater(
        service.prepareLocalDatabase(
          enabled: true,
          password: 'wrong-password-1234',
        ),
        throwsA(isA<AiSyncDecryptionException>()),
      );
      final after = (await database.query(aiSettingsSyncTable))
          .single['encrypted_payload'];
      expect(after, before);
    });
  });
}
