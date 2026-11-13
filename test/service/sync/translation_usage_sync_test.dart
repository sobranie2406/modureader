import 'package:modu_reader/service/sync/ai_settings_sync.dart';
import 'package:modu_reader/service/sync/translation_usage_sync.dart';
import 'package:modu_reader/service/translate/translation_usage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'two offline device writers survive repeated encrypted sync without double counting',
      () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    final account =
        TranslationUsage.account('microsoft', {'microsoft_key': 'test-key'});
    SharedPreferences.setMockInitialValues(
        {TranslationUsage.deviceKey: 'device-a'});
    final a = await SharedPreferences.getInstance();
    SharedPreferences.setMockInitialValues(
        {TranslationUsage.deviceKey: 'device-b'});
    final b = await SharedPreferences.getInstance();
    final ua = TranslationUsage(a), ub = TranslationUsage(b);
    final sa = TranslationUsageSyncService(
        preferences: a, databaseProvider: () async => db);
    final sb = TranslationUsageSyncService(
        preferences: b, databaseProvider: () async => db);
    await ua.record(account, 30);
    await ub.record(account, 20);
    expect(
        await sa.prepareLocalDatabase(enabled: false, password: null), false);
    await sa.prepareLocalDatabase(enabled: true, password: 'test-password');
    await sb.prepareLocalDatabase(enabled: true, password: 'test-password');
    final rows = await db.query(aiSettingsSyncTable);
    expect(rows.length, 2);
    expect(rows.toString(), isNot(contains('test-key')));
    for (var i = 0; i < 2; i++) {
      await sa.restoreFromDownloadedDatabase(
          enabled: true, password: 'test-password');
      await sb.restoreFromDownloadedDatabase(
          enabled: true, password: 'test-password');
      expect(ua.used(account), 50);
      expect(ub.used(account), 50);
    }
    await ua.record(account, 7);
    await ub.record(account, 9);
    await sa.prepareLocalDatabase(enabled: true, password: 'test-password');
    await sb.prepareLocalDatabase(enabled: true, password: 'test-password');
    await sa.restoreFromDownloadedDatabase(
        enabled: true, password: 'test-password');
    await sb.restoreFromDownloadedDatabase(
        enabled: true, password: 'test-password');
    expect(ua.used(account), 66);
    expect(ub.used(account), 66);
    expect(
        await sa.prepareLocalDatabase(enabled: true, password: 'test-password'),
        false);
  },
      // Six PBKDF2-hardened encrypt/decrypt rounds take ~30s on CI, which is
      // the package default; keep the assertion but give it realistic headroom.
      timeout: const Timeout(Duration(minutes: 2)));
}
