import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/sync/ai_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shown release version stays local, including older backups', () async {
    SharedPreferences.setMockInitialValues({'lastAppVersion': '1.3.8+10175'});
    final prefs = Prefs();
    await prefs.initPrefs();
    expect(
        await prefs.buildPrefsBackupMap(), isNot(contains('lastAppVersion')));
    expect(collectAiSettingsForSync(prefs.prefs),
        isNot(contains('lastAppVersion')));
    await prefs.applyPrefsBackupMap({
      'lastAppVersion': {'type': 'string', 'value': '1.3.7+10170'},
    });
    expect(prefs.lastAppVersion, '1.3.8+10175');
  });
}
