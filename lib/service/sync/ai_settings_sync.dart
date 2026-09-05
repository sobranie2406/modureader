import 'dart:collection';
import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

const String aiSettingsSyncTable = 'tb_sync_secrets';
const String _aiSettingsRecordId = 'ai-service-settings-v1';
const int _aiSettingsPayloadVersion = 1;

const Set<String> _aiSettingsPreferenceKeys = {
  // AI chat providers and model parameters.
  'aiProviders',
  'selectedAiService',
  'aiTemperature',
  'aiMaxTokens',
  'aiContextTurns',
  'aiRpm',
  'translationAiService',
  // Vector model settings. vectorModelConfig may contain a remote API key.
  'vectorModelEnabled',
  'autoVectorizeOnImport',
  'vectorModelMode',
  'vectorLocalModelId',
  'vectorModelConfig',
  // Translation provider settings.
  'translateService',
  'translateFrom',
  'translateTo',
  'fullTextTranslateService',
  'fullTextTranslateFrom',
  'fullTextTranslateTo',
  'autoTranslateSelection',
  // Online speech provider settings.
  'ttsService',
  'ttsVolume',
  'ttsPitch',
  'ttsRate',
  // Legacy values remain supported so an upgraded installation does not lose
  // credentials that have not yet been migrated to the current provider UI.
  'isSystemTts',
  'onlineTtsService',
};

const List<String> _aiSettingsPreferencePrefixes = [
  'aiConfig_',
  'onlineTtsConfig_',
  'ttsVoiceModel_',
  'translateServiceConfig_',
];

bool isAiSettingsSyncPreference(String key) {
  return _aiSettingsPreferenceKeys.contains(key) ||
      _aiSettingsPreferencePrefixes.any(key.startsWith);
}

/// Returns only AI-related provider settings and credentials. General app
/// preferences and WebDAV credentials are deliberately excluded.
Map<String, Object?> collectAiSettingsForSync(SharedPreferences preferences) {
  final result = SplayTreeMap<String, Object?>();
  final keys = preferences.getKeys().where(isAiSettingsSyncPreference).toList()
    ..sort();
  for (final key in keys) {
    final value = preferences.get(key);
    if (_isSupportedPreferenceValue(value)) {
      result[key] =
          key == 'aiProviders' ? _removeVolatileProviderFields(value) : value;
    }
  }
  return Map<String, Object?>.unmodifiable(result);
}

/// Replaces the local AI service settings with an authenticated remote
/// snapshot. Unknown keys and unsupported value types are rejected before any
/// local value is changed.
Future<void> applyAiSettingsFromSync(
  SharedPreferences preferences,
  Map<String, Object?> values,
) async {
  for (final entry in values.entries) {
    if (!isAiSettingsSyncPreference(entry.key) ||
        !_isSupportedPreferenceValue(entry.value)) {
      throw const FormatException('同步数据库中的 AI 设置格式无效');
    }
  }

  final localKeys =
      preferences.getKeys().where(isAiSettingsSyncPreference).toList();
  for (final key in localKeys) {
    await preferences.remove(key);
  }
  for (final entry in values.entries) {
    await _setPreference(preferences, entry.key, entry.value);
  }
}

bool _isSupportedPreferenceValue(Object? value) {
  return value is bool ||
      value is int ||
      value is double ||
      value is String ||
      (value is List && value.every((item) => item is String));
}

Object? _removeVolatileProviderFields(Object? value) {
  if (value is! String || value.isEmpty) return value;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return value;
    final providers = decoded.map((item) {
      if (item is! Map) return item;
      final provider = Map<String, dynamic>.from(item);
      // Round-robin bookkeeping changes after ordinary API calls and should
      // not force a WebDAV database upload by itself.
      provider.remove('keyIndex');
      provider.remove('updatedAt');
      return provider;
    }).toList(growable: false);
    return jsonEncode(providers);
  } catch (_) {
    return value;
  }
}

Future<void> _setPreference(
  SharedPreferences preferences,
  String key,
  Object? value,
) async {
  if (value is bool) {
    await preferences.setBool(key, value);
  } else if (value is int) {
    await preferences.setInt(key, value);
  } else if (value is double) {
    await preferences.setDouble(key, value);
  } else if (value is String) {
    await preferences.setString(key, value);
  } else if (value is List) {
    await preferences.setStringList(key, value.cast<String>());
  }
}

class AiSettingsSyncCipher {
  static const int pbkdf2Iterations = 210000;
  static const List<int> _associatedData = [
    109,
    111,
    100,
    117,
    45,
    97,
    105,
    45,
    115,
    121,
    110,
    99,
    45,
    118,
    49,
  ]; // "modu-ai-sync-v1"

  final Cipher _cipher = AesGcm.with256bits();
  final KdfAlgorithm _kdf = Pbkdf2.hmacSha256(
    iterations: pbkdf2Iterations,
    bits: 256,
  );

  Future<String> encrypt(
    Map<String, Object?> preferences,
    String password,
  ) async {
    if (password.isEmpty) throw const AiSyncPasswordMissingException();
    final salt = await SecretKeyData.random(length: 16).extractBytes();
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final clearText = utf8.encode(_encodePayload(preferences));
    final secretBox = await _cipher.encrypt(
      clearText,
      secretKey: secretKey,
      aad: _associatedData,
    );
    return jsonEncode({
      'version': _aiSettingsPayloadVersion,
      'algorithm': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': pbkdf2Iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    });
  }

  Future<Map<String, Object?>> decrypt(
    String encryptedPayload,
    String password,
  ) async {
    if (password.isEmpty) throw const AiSyncPasswordMissingException();
    try {
      final envelope =
          Map<String, dynamic>.from(jsonDecode(encryptedPayload) as Map);
      if (envelope['version'] != _aiSettingsPayloadVersion ||
          envelope['algorithm'] != 'AES-256-GCM' ||
          envelope['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          envelope['iterations'] != pbkdf2Iterations) {
        throw const FormatException('不支持的 AI 设置加密格式');
      }
      final salt = base64Decode(envelope['salt'] as String);
      final secretKey = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final secretBox = SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      );
      final clearText = await _cipher.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: _associatedData,
      );
      final payload = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(clearText)) as Map,
      );
      if (payload['version'] != _aiSettingsPayloadVersion ||
          payload['preferences'] is! Map) {
        throw const FormatException('AI 设置同步数据格式无效');
      }
      return Map<String, Object?>.from(payload['preferences'] as Map);
    } on AiSyncPasswordMissingException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const AiSyncDecryptionException();
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('AI 设置同步数据格式无效');
    }
  }

  String canonicalPayload(Map<String, Object?> preferences) {
    return _encodePayload(preferences);
  }

  String _encodePayload(Map<String, Object?> preferences) {
    final sorted = SplayTreeMap<String, Object?>.from(preferences);
    return jsonEncode({
      'version': _aiSettingsPayloadVersion,
      'preferences': sorted,
    });
  }
}

typedef SyncDatabaseProvider = Future<Database> Function();

class AiSettingsSyncService {
  AiSettingsSyncService({
    SyncDatabaseProvider? databaseProvider,
    SharedPreferences? preferences,
    AiSettingsSyncCipher? cipher,
  })  : _databaseProvider = databaseProvider ?? _defaultDatabaseProvider,
        _providedPreferences = preferences,
        _cipher = cipher ?? AiSettingsSyncCipher();

  final SyncDatabaseProvider _databaseProvider;
  final SharedPreferences? _providedPreferences;
  final AiSettingsSyncCipher _cipher;

  SharedPreferences get _preferences => _providedPreferences ?? Prefs().prefs;

  static Future<Database> _defaultDatabaseProvider() => DBHelper().database;

  Future<bool> prepareLocalDatabase({
    required bool enabled,
    required String? password,
    bool force = false,
  }) async {
    if (!enabled) {
      // Disabled devices must leave an existing encrypted record untouched.
      // Removing it would make the next ordinary database upload erase the
      // opt-in secret created by another device.
      return false;
    }
    final database = await _databaseProvider();
    if (password == null || password.isEmpty) {
      throw const AiSyncPasswordMissingException();
    }
    await _ensureTable(database);

    final preferences = collectAiSettingsForSync(_preferences);
    final existing = await database.query(
      aiSettingsSyncTable,
      columns: ['encrypted_payload'],
      where: 'id = ?',
      whereArgs: [_aiSettingsRecordId],
      limit: 1,
    );
    if (!force && existing.isNotEmpty) {
      try {
        final oldPreferences = await _cipher.decrypt(
          existing.single['encrypted_payload']! as String,
          password,
        );
        if (_cipher.canonicalPayload(oldPreferences) ==
            _cipher.canonicalPayload(preferences)) {
          return false;
        }
      } on AiSyncPasswordMissingException {
        rethrow;
      } on AiSyncDecryptionException {
        rethrow;
      } on FormatException {
        rethrow;
      }
    }

    final encryptedPayload = await _cipher.encrypt(preferences, password);
    await database.insert(
      aiSettingsSyncTable,
      {
        'id': _aiSettingsRecordId,
        'encrypted_payload': encryptedPayload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return true;
  }

  Future<bool> restoreFromDownloadedDatabase({
    required bool enabled,
    required String? password,
  }) async {
    if (!enabled) {
      // Keep the opaque encrypted record so this device cannot accidentally
      // delete another device's opt-in API-key backup.
      return false;
    }
    final database = await _databaseProvider();
    if (password == null || password.isEmpty) {
      throw const AiSyncPasswordMissingException();
    }
    await _ensureTable(database);

    final rows = await database.query(
      aiSettingsSyncTable,
      columns: ['encrypted_payload'],
      where: 'id = ?',
      whereArgs: [_aiSettingsRecordId],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final preferences = await _cipher.decrypt(
      rows.single['encrypted_payload']! as String,
      password,
    );
    await applyAiSettingsFromSync(_preferences, preferences);
    if (_providedPreferences == null) Prefs().notifyExternalChange();
    return true;
  }

  Future<void> _ensureTable(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $aiSettingsSyncTable (
        id TEXT PRIMARY KEY NOT NULL,
        encrypted_payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }
}

class AiSyncPasswordMissingException implements Exception {
  const AiSyncPasswordMissingException();

  @override
  String toString() => '未设置 AI 设置同步加密密码';
}

class AiSyncDecryptionException implements Exception {
  const AiSyncDecryptionException();

  @override
  String toString() => '无法解密 AI 设置，请检查同步加密密码';
}
