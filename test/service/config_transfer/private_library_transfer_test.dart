import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:modu_reader/service/config_transfer/settings_modules.dart';
import 'package:modu_reader/service/local_data/backup_safety.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'privateLibrary_v1';
  setUp(() async {
    SharedPreferences.setMockInitialValues({key: 'device-local-credential'});
    await Prefs().initPrefs();
  });
  test('private credentials and marks never enter settings or full backups',
      () async {
    expect((await Prefs().buildPrefsBackupMap()).containsKey(key), false);
    for (final secrets in [false, true]) {
      final exported = await GlobalSettingsTransfer.decode(
          await GlobalSettingsTransfer.export(Prefs(),
              includeSecrets: secrets));
      expect(exported.containsKey(key), false);
    }
    expect(settingsModuleForKey(key), null);
    expect(isCredentialPreference(key), true);
    expect(withoutBackupCredentials({key: 'secret', 'ordinary': true}),
        {'ordinary': true});
  });
  test('restoring a backup cannot replace this device protection', () async {
    await Prefs().applyPrefsBackupMap({
      key: {'type': 'string', 'value': 'foreign-device'}
    });
    expect(Prefs().prefs.getString(key), 'device-local-credential');
    expect(
        () => GlobalSettingsTransfer.validate({
              prefsBackupVersionKey: 1,
              key: {'type': 'string', 'value': 'foreign-device'}
            }),
        throwsFormatException);
  });
}
