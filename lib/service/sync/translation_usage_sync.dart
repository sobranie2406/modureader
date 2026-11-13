import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/sync/ai_settings_sync.dart';
import 'package:modu_reader/service/translate/translation_usage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:modu_reader/dao/database.dart';

/// Separate encrypted record per device: concurrent devices cannot replace
/// each other's increments through the settings snapshot's last-writer rule.
class TranslationUsageSyncService extends AiSettingsSyncService {
  TranslationUsageSyncService(
      {super.databaseProvider, super.preferences, super.cipher})
      : _prefs = preferences ?? Prefs().prefs,
        _database = databaseProvider ?? (() => DBHelper().database),
        _cipher = cipher ?? AiSettingsSyncCipher();
  final SharedPreferences _prefs;
  final SyncDatabaseProvider _database;
  final AiSettingsSyncCipher _cipher;
  static const prefix = 'translation-usage-v1-';
  @override
  String get recordId => '$prefix${TranslationUsage(_prefs).device}';
  @override
  bool get hasLocalSettings => _prefs.containsKey(TranslationUsage.countersKey);
  @override
  Map<String, Object?> collectPreferences() =>
      TranslationUsage(_prefs).localCounters();

  @override
  Future<bool> restoreFromDownloadedDatabase(
      {required bool enabled, required String? password}) async {
    if (!enabled) return false;
    if (password == null || password.isEmpty) {
      throw const AiSyncPasswordMissingException();
    }
    final db = await _database();
    final exists = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        [aiSettingsSyncTable]);
    if (exists.isEmpty) return false;
    final rows = await db.query(aiSettingsSyncTable,
        where: 'id LIKE ?', whereArgs: ['$prefix%']);
    final usage = TranslationUsage(_prefs);
    for (final row in rows) {
      final values =
          await _cipher.decrypt(row['encrypted_payload'] as String, password);
      await usage.merge((row['id'] as String).substring(prefix.length), values);
    }
    if (rows.isNotEmpty) Prefs().notifyExternalChange();
    return rows.isNotEmpty;
  }
}
