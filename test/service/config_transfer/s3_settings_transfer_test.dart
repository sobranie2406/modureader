import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:anx_reader/service/config_transfer/settings_value_validation.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/service/sync/s3_client.dart';
import 'package:anx_reader/service/sync/webdav_client.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';

const info = {
  'endpoint': 'https://s3.example.test',
  'bucket': 'my-books',
  'accessKeyId': 'private-id',
  'secretAccessKey': 'private-key',
  'sessionToken': 'private-token',
  'remoteRoot': 'MyBooks'
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      's3Info': jsonEncode(info),
      'syncProtocol': 's3',
      'webdavStatus': true
    });
    await Prefs().initPrefs();
    SyncClientFactory.resetCurrentClient();
  });
  test('all credential exports omit S3 by default; explicit opt-in round trips',
      () async {
    expect(isCredentialPreference('s3Info'), true);
    expect(
        withoutBackupCredentials(await Prefs().buildPrefsBackupMap())
            .containsKey('s3Info'),
        false);
    final plain = await GlobalSettingsTransfer.export(Prefs());
    expect(plain, isNot(contains('private-key')));
    expect(plain, isNot(contains('private-token')));
    expect(plain, isNot(contains('s3Info')));
    expect(plain, isNot(contains('syncProtocol')));
    final all = await GlobalSettingsTransfer.export(Prefs(),
        includeSecrets: true, scope: 'webdav');
    final values = await GlobalSettingsTransfer.decode(all);
    expect(jsonDecode(values['s3Info']['value']), info);
    expect(GlobalSettingsTransfer.disablesSync(values), true);
    expect(
        GlobalSettingsTransfer.forImport(values).containsKey('s3Info'), false);
    expect(GlobalSettingsTransfer.forImport(values).containsKey('syncProtocol'),
        false);
    await GlobalSettingsTransfer.apply(Prefs(),
        GlobalSettingsTransfer.forImport(values, includeSecrets: true));
    expect(Prefs().getSyncInfo(SyncProtocol.s3), info);
    expect(Prefs().webdavStatus, false);
    expect(
        collectAiSettingsForSync(Prefs().prefs).containsKey('s3Info'), false);
  });
  test('protocol switching never reuses stale WebDAV credentials', () async {
    SyncClientFactory.initializeCurrentClient();
    expect(SyncClientFactory.currentClient, isA<S3SyncClient>());
    SyncClientFactory.switchProtocol(SyncProtocol.webdav);
    expect(SyncClientFactory.currentClient, isNull);
    SyncClientFactory.switchProtocol(SyncProtocol.s3);
    expect(SyncClientFactory.currentClient, isA<S3SyncClient>());
    Prefs().setSyncInfo(SyncProtocol.s3, {'endpoint': 'bad'});
    SyncClientFactory.initializeCurrentClient();
    expect(SyncClientFactory.currentClient, isNull);
  });
  test('bad imported S3 config is rejected before it can overwrite preferences',
      () {
    expect(
        () => validateSettingsValue(
            's3Info', jsonEncode({...info, 'signature': 'unknown'})),
        throwsFormatException);
    expect(() => validateSettingsValue('syncProtocol', 's3'), returnsNormally);
    expect(() => validateSettingsValue('syncProtocol', 'unknown'),
        throwsFormatException);
  });
  for (final explicitProtocol in [false, true]) {
    test('existing WebDAV survives initialization (explicit=$explicitProtocol)',
        () async {
      const dav = {
        'url': 'https://dav.example.test/dav/',
        'username': 'existing-user',
        'password': 'existing-password'
      };
      final original = <String, Object>{
        'webdavInfo': jsonEncode(dav),
        'webdavStatus': true,
        'autoSync': true,
        'onlySyncWhenWifi': true,
        'syncAiSettingsToWebdav': true,
        'syncAiSettingsEncryptionPassword': 'example-upgrade-password',
        // An unused, damaged S3 setting must never break an active WebDAV account.
        's3Info': '{invalid json',
        if (explicitProtocol) 'syncProtocol': 'webdav',
      };
      SharedPreferences.setMockInitialValues(original);
      await Prefs().initPrefs();
      final before = {
        for (final key in Prefs().prefs.getKeys()) key: Prefs().prefs.get(key)
      };
      SyncClientFactory.initializeCurrentClient();
      final client = SyncClientFactory.currentClient!;
      expect(client, isA<WebdavClient>());
      expect(client.config, containsPair('url', dav['url']));
      expect(client.config, containsPair('username', dav['username']));
      expect(client.config, containsPair('password', dav['password']));
      // Pending batches / scan caches / maintenance retain their legacy identity.
      expect(client.syncIdentity,
          [client.protocolName, dav['url'], dav['username']]);
      expect(Prefs().webdavStatus, true);
      expect({
        for (final key in Prefs().prefs.getKeys()) key: Prefs().prefs.get(key)
      }, before);
    });
  }
  test(
      'configuring S3 and switching back preserves the WebDAV account verbatim',
      () {
    const dav = {
      'url': 'https://dav.example.test/dav',
      'username': 'old-user',
      'password': 'old-password'
    };
    Prefs().setSyncInfo(SyncProtocol.webdav, dav);
    Prefs().saveWebdavStatus(false);
    SyncClientFactory.switchProtocol(SyncProtocol.webdav);
    final identity = SyncClientFactory.currentClient!.syncIdentity;
    final saved = Prefs().prefs.getString('webdavInfo');
    Prefs().setSyncInfo(SyncProtocol.s3, {...info, 'bucket': 'another-bucket'});
    SyncClientFactory.switchProtocol(SyncProtocol.s3);
    expect(SyncClientFactory.currentClient, isA<S3SyncClient>());
    expect(Prefs().prefs.getString('webdavInfo'), saved);
    SyncClientFactory.switchProtocol(SyncProtocol.webdav);
    expect(SyncClientFactory.currentClient, isA<WebdavClient>());
    expect(SyncClientFactory.currentClient!.syncIdentity, identity);
    expect(Prefs().getSyncInfo(SyncProtocol.webdav), dav);
  });
}
