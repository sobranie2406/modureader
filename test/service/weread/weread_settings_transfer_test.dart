import 'dart:convert';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/service/sync/ai_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  test('connection defaults off; key only in explicitly opted-in global export',
      () async {
    expect(Prefs().wereadEnabled, false);
    await Prefs().saveWereadSettings(enabled: true, apiKey: 'wrk-example');
    final safe = await GlobalSettingsTransfer.export(Prefs());
    final sensitive =
        await GlobalSettingsTransfer.export(Prefs(), includeSecrets: true);
    expect(safe, isNot(contains('wrk-example')));
    expect(sensitive, contains('wrk-example'));
    expect(sensitive, isNot(contains('wereadEnabled')));
    final appearance = await GlobalSettingsTransfer.export(Prefs(),
        includeSecrets: true, scope: 'appearance');
    expect(appearance, contains('wrk-example'));
    expect((jsonDecode(sensitive)['preferences'] as Map)['wereadApiKey'],
        {'type': 'string', 'value': 'wrk-example'});
  });
  test(
      'encrypted settings channel includes key, excludes switch and public caches',
      () async {
    await Prefs().saveWereadSettings(enabled: true, apiKey: 'wrk-example');
    final data = collectAiSettingsForSync(Prefs().prefs);
    expect(data['wereadApiKey'], 'wrk-example');
    expect(data, isNot(contains('wereadEnabled')));
    expect(Prefs().syncAiSettingsToWebdav, false);
    await applyAiSettingsFromSync(Prefs().prefs, {});
    expect(
        Prefs().wereadApiKey, 'wrk-example'); // Old client does not erase it.
    await applyAiSettingsFromSync(Prefs().prefs, {'wereadApiKey': ''});
    expect(Prefs().wereadApiKey, '');
    expect(Prefs().wereadEnabled, true);
    await applyAiSettingsFromSync(
        Prefs().prefs, {'wereadApiKey': 'wrk-remote'});
    expect(Prefs().wereadApiKey, 'wrk-remote');
  });
  test('API Key encryption round trip never places plaintext in cloud payload',
      () async {
    final cipher = AiSettingsSyncCipher();
    final encrypted = await cipher
        .encrypt({'wereadApiKey': 'wrk-test-secret'}, 'separate-test-password');
    expect(encrypted, isNot(contains('wrk-test-secret')));
    expect(await cipher.decrypt(encrypted, 'separate-test-password'),
        {'wereadApiKey': 'wrk-test-secret'});
    await expectLater(cipher.decrypt(encrypted, 'wrong-password'),
        throwsA(isA<AiSyncDecryptionException>()));
  });
  test('credential-free restore preserves key; opted-in restore updates it',
      () async {
    await Prefs().saveWereadSettings(apiKey: 'wrk-local');
    final values = <String, dynamic>{
      '__prefsBackupVersion': 1,
      'wereadApiKey': {'type': 'string', 'value': 'wrk-remote'},
    };
    await GlobalSettingsTransfer.apply(
        Prefs(), GlobalSettingsTransfer.forImport(values));
    expect(Prefs().wereadApiKey, 'wrk-local');
    await GlobalSettingsTransfer.apply(Prefs(),
        GlobalSettingsTransfer.forImport(values, includeSecrets: true));
    expect(Prefs().wereadApiKey, 'wrk-remote');
  });
}
