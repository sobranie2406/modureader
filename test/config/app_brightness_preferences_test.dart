import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/app_brightness.dart';
import 'package:anx_reader/service/sync/ai_settings_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('brightness never travels through backup restore or settings sync',
      () async {
    SharedPreferences.setMockInitialValues({
      AppBrightness.levelKey: 0.7,
      AppBrightness.followSystemKey: false,
    });
    final prefs = Prefs();
    await prefs.initPrefs();
    final backup = await prefs.buildPrefsBackupMap();
    final synced = collectAiSettingsForSync(prefs.prefs);
    for (final key in [AppBrightness.levelKey, AppBrightness.followSystemKey]) {
      expect(backup.containsKey(key), isFalse);
      expect(synced.containsKey(key), isFalse);
    }
    await prefs.applyPrefsBackupMap({
      AppBrightness.levelKey: {'type': 'double', 'value': 0.2},
      AppBrightness.followSystemKey: {'type': 'bool', 'value': true},
    });
    expect(prefs.prefs.getDouble(AppBrightness.levelKey), 0.7);
    expect(prefs.prefs.getBool(AppBrightness.followSystemKey), isFalse);
  });
}
