import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/translate/translation_usage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final account = TranslationUsage.account('baidu', {'baidu_appid': 'test'});
  test('UTC periods, independent accounts, monotonic device merge and quota',
      () async {
    SharedPreferences.setMockInitialValues(
        {TranslationUsage.deviceKey: 'device-a'});
    final prefs = await SharedPreferences.getInstance();
    final usage = TranslationUsage(prefs);
    final now = DateTime.utc(2026, 10, 31, 23);
    await Future.wait([
      usage.record(account, 10, now: now),
      usage.record(account, 20, now: now)
    ]);
    await usage.merge('device-b', {'2026-10/$account': 40});
    await usage.merge('device-b', {'2026-10/$account': 40});
    await usage.merge('device-b', {'2026-10/$account': 15});
    expect(usage.used(account, now: now), 70);
    expect(usage.used(account, now: DateTime.utc(2026, 11)), 0);
    await usage.record(account, 2, now: DateTime.utc(2026, 11));
    expect(usage.used(account, now: now), 70);
    expect(usage.used(account, now: DateTime.utc(2026, 11)), 2);
    expect(
        usage.used(TranslationUsage.account('baidu', {'baidu_appid': 'other'}),
            now: now),
        0);
    expect(usage.quota(account, 'baidu'), 1000000);
    await usage.setQuota(account, 100);
    expect(usage.quota(account, 'baidu'), 100);
    await expectLater(usage.merge('device-c', {'2026-10/$account': -1}),
        throwsFormatException);
    await expectLater(
        usage.merge('device-c', {'bad': 50}), throwsFormatException);
    expect(usage.used(account, now: now), 70);
  });

  test('app backups cannot clone counter writer identity or counters',
      () async {
    SharedPreferences.setMockInitialValues({
      TranslationUsage.deviceKey: 'device-a',
      TranslationUsage.countersKey: '{}'
    });
    await Prefs().initPrefs();
    final backup = await Prefs().buildPrefsBackupMap();
    expect(backup, isNot(contains(TranslationUsage.deviceKey)));
    expect(backup, isNot(contains(TranslationUsage.countersKey)));
    await Prefs().applyPrefsBackupMap({
      TranslationUsage.deviceKey: {'type': 'string', 'value': 'device-b'}
    });
    expect(Prefs().prefs.getString(TranslationUsage.deviceKey), 'device-a');
  });
}
