import 'dart:convert';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/service/config_transfer/settings_config_transfer.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:anx_reader/service/config_transfer/library_config_transfer.dart';

/// Portable preferences only. Never restore databases, per-book IDs, migration
/// flags, storage paths, permissions, window geometry or device-local assets.
class GlobalSettingsTransfer {
  static const maxBytes = 4 * 1024 * 1024;
  static const kind = 'modu-global-settings';
  static const scopes = ['all', 'ai', 'tts', 'webdav', 'remote-library-webdav'];
  static final Map<String, String> _types = {
    for (final key
        in '''quickMarkShowMenu clearLogWhenStart useOriginalCoverRatio hideStatusBar readerFullscreen
autoHideBottomBar trueDarkMode eInkMode autoTranslateSelection autoMarkSelection vectorModelEnabled
autoVectorizeOnImport autoSummaryPreviousContent autoAdjustReadingTheme readingNightMode volumeKeyTurnPage
keyboardShortcutTurnPage swapPageTurnArea showMenuOnHover showActionLabels showBookTitleOnDefaultCover
showAuthorOnDefaultCover openBookAnimation onlySyncWhenWifi useBookStyles bottomNavigatorShowNote
bottomNavigatorShowStatistics bottomNavigatorShowAI syncCompletedToast autoSync readingTimedSync
isSystemTts showTextUnderIconButton notesExportMergeChapters verticalRedFrame enableJsForEpub
httpProxyEnabled customCSSEnabled allowMixWithOtherAudio tapOnlyPageTurn'''
            .split(RegExp(r'\s+')))
      key: 'bool',
    for (final key
        in '''themeColor awakeTime pageTurningType aiRpm aiMaxTokens aiContextTurns maxAiCacheCount
readingSyncMinutes excerptShareColorIndex httpProxyPort customCssDefaultIndex'''
            .split(RegExp(r'\s+')))
      key: 'int',
    for (final key
        in '''ttsVolume ttsPitch ttsRate aiTemperature aiChatFontSize bookCoverWidth
pageHeaderMargin pageHeaderLeftMargin pageHeaderRightMargin pageHeaderFontSize pageFooterMargin
pageFooterLeftMargin pageFooterRightMargin pageFooterFontSize aiPanelWidth aiPanelHeight'''
            .split(RegExp(r'\s+')))
      key: 'double',
    for (final key
        in '''locale themeMode readStyle readTheme annotationType annotationColor ttsService
pageTurnStyle translateService translateFrom translateTo fullTextTranslateService fullTextTranslateFrom
fullTextTranslateTo translationAiService readingRules chapterSplitCustomRules chapterSplitSelectedRuleId
selectedAiService vectorModelMode vectorLocalModelId vectorModelDownloadSource vectorModelConfig aiProviders
userPrompts readAnySkillStates readAnySkillPrompts pageTurnMode customPageTurnConfig bookshelfFolderStyle
readingInfo onlineTtsService sortField sortOrder notesViewSortField notesViewSortDirection notesExportSortField
notesExportSortDirection excerptShareTemplate writingMode translationMode httpProxyHost httpProxyTestUrl
customCSS customCssProfiles customCssDefaultIndices textAlignment bgimgFit aiPanelPosition codeHighlightTheme aiChatDisplayMode
webdavInfo remoteLibraryConnection'''
            .split(RegExp(r'\s+')))
      key: 'string',
    'statisticsDashboardTiles': 'stringList',
    'enabledAiTools': 'stringList',
  };

  static String? _type(String key) {
    if (_types.containsKey(key)) return _types[key];
    if ([
      'aiConfig_',
      'onlineTtsConfig_',
      'translateServiceConfig_',
      'ttsVoiceModel_',
      'aiPrompt_'
    ].any(key.startsWith)) {
      return 'string';
    }
    return null;
  }

  static Future<String> export(Prefs prefs,
      {bool includeSecrets = false, String scope = 'all'}) async {
    if (!scopes.contains(scope)) {
      throw const FormatException('Unknown settings scope');
    }
    var values = await prefs.buildPrefsBackupMap();
    values.removeWhere(
        (key, _) => key != prefsBackupVersionKey && _type(key) == null);
    values.removeWhere(
        (key, _) => key != prefsBackupVersionKey && !_inScope(key, scope));
    // Local file selections are intentionally not part of this format.
    for (final key in ['readStyle', 'readTheme']) {
      if (values[key] == null) continue;
      final data =
          jsonDecode(values[key]['value'] as String) as Map<String, dynamic>;
      data.remove(key == 'readStyle' ? 'fontFamily' : 'backgroundImagePath');
      data.remove('id');
      values[key] = {'type': 'string', 'value': jsonEncode(data)};
    }
    if (!includeSecrets) {
      values = withoutBackupCredentials(values);
      // Do not select an absent provider on another device.
      values.remove('selectedAiService');
      values.remove('translationAiService');
    }
    validate(values);
    final envelope = {
      'kind': kind,
      'version': 1,
      'scope': scope,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'preferences': values,
    };
    final text = jsonEncode(envelope);
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('设置文件过大 / Settings file too large');
    }
    return text;
  }

  static bool _inScope(String key, String scope) => switch (scope) {
        'all' => true,
        'ai' => key.startsWith('ai') ||
            key.startsWith('readAnySkill') ||
            [
              'selectedAiService',
              'translationAiService',
              'userPrompts',
              'enabledAiTools',
              'maxAiCacheCount'
            ].contains(key),
        'tts' => key.startsWith('tts') ||
            key.startsWith('onlineTts') ||
            ['isSystemTts', 'allowMixWithOtherAudio'].contains(key),
        'webdav' => [
            'webdavInfo',
            'autoSync',
            'onlySyncWhenWifi',
            'syncCompletedToast',
            'readingTimedSync',
            'readingSyncMinutes'
          ].contains(key),
        'remote-library-webdav' => key == 'remoteLibraryConnection',
        _ => false,
      };

  /// Old per-page links are still accepted at the single migration entry.
  /// ReadAny has no kind, so the user explicitly selects AI or WebDAV scope.
  static Map<String, dynamic>? legacy(String text, {String scope = 'all'}) {
    if (!text.trim().startsWith('modu:') &&
        !text.trim().startsWith('readany:')) {
      return null;
    }
    final decoded = ConfigTransferCodec.decode(text);
    if (decoded.kind == kind) return null;
    final type = decoded.kind ?? scope;
    final data = decoded.data;
    final raw = <String, dynamic>{};
    switch (type) {
      case 'ai':
        final ai = AiConfigTransfer.parse(data);
        raw.addAll({
          'aiProviders':
              jsonEncode(ai.providers.map((p) => p.toJson()).toList()),
          'selectedAiService': ai.selectedProviderId,
          'aiTemperature': ai.temperature,
          'aiMaxTokens': ai.maxTokens,
          'aiContextTurns': ai.contextTurns,
          if (ai.rpm != null) 'aiRpm': ai.rpm,
          if (ai.translationProviderId != null)
            'translationAiService': ai.translationProviderId
        });
        break;
      case 'tts':
        final tts = TtsConfigTransfer.validate(data);
        raw.addAll({
          'ttsService': tts['service'],
          'ttsVolume': tts['volume'],
          'ttsPitch': tts['pitch'],
          'ttsRate': tts['rate'],
          'allowMixWithOtherAudio': tts['allowMixWithOtherAudio']
        });
        for (final id in TtsConfigTransfer.services) {
          raw['onlineTtsConfig_$id'] =
              jsonEncode(tts['providers'][id]['config']);
          raw['ttsVoiceModel_$id'] = tts['providers'][id]['voice'];
        }
        break;
      case 'webdav':
        final dav = WebdavConfigTransfer.parse(data);
        raw.addAll({
          'webdavInfo': jsonEncode(dav.syncInfo),
          if (dav.wifiOnly != null) 'onlySyncWhenWifi': dav.wifiOnly,
          if (dav.notifyOnComplete != null)
            'syncCompletedToast': dav.notifyOnComplete
        });
        break;
      case 'remote-library-webdav':
        final library = LibraryConfigTransfer.parse(data);
        raw['remoteLibraryConnection'] = jsonEncode({
          'url': library.url,
          'username': library.username,
          'password': library.password,
          'allowHttp': library.allowHttp
        });
        break;
      default:
        throw const FormatException(
            '未知配置类型；ReadAny 请先选择 AI 或 WebDAV / Select AI or WebDAV for ReadAny');
    }
    return {
      prefsBackupVersionKey: 1,
      for (final e in raw.entries)
        e.key: {'type': _type(e.key), 'value': e.value}
    };
  }

  static Map<String, dynamic> envelope(String text) {
    if (text.trim().startsWith('modu:')) {
      final decoded = ConfigTransferCodec.decode(text);
      if (decoded.kind != kind) {
        throw const FormatException('不是全局设置链接 / Not a global settings link');
      }
      text = jsonEncode(decoded.data);
    }
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('设置文件过大 / Settings file too large');
    }
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic> ||
        value['kind'] != kind ||
        value['version'] != 1 ||
        !value.containsKey('preferences') ||
        value.containsKey('encryptedPreferences')) {
      throw const FormatException('不是支持的全局设置备份 / Unsupported settings backup');
    }
    return value;
  }

  static String link(String file) {
    final token = ConfigTransferCodec.encode(kind: kind, data: envelope(file));
    // Verify the generated link fits the existing transfer decoder's limits.
    ConfigTransferCodec.decode(token);
    return token;
  }

  static Future<Map<String, dynamic>> decode(String text) async {
    final file = envelope(text);
    final raw = file['preferences'];
    if (raw is! Map) throw const FormatException('设置格式无效 / Invalid settings');
    final values = Map<String, dynamic>.from(raw);
    validate(values);
    return values;
  }

  static void validate(Map<String, dynamic> values) {
    validatePreferencesBackup(values);
    for (final entry in values.entries) {
      if (entry.key == prefsBackupVersionKey) continue;
      if (_type(entry.key) != entry.value['type'] || _type(entry.key) == null) {
        throw const FormatException(
            '包含不支持或不安全的设置 / Unsupported or unsafe setting');
      }
      // Validate structured payloads before ANY setting is applied.
      final value = entry.value['value'];
      if (entry.key == 'readStyle') {
        final data = Map<String, dynamic>.from(jsonDecode(value) as Map);
        BookStyle.fromJson(jsonEncode({...data, 'fontFamily': 'Arial'}));
      }
      if (entry.key == 'readTheme') {
        final data = Map<String, dynamic>.from(jsonDecode(value) as Map);
        final theme = ReadTheme.fromJson(
            jsonEncode({...data, 'id': null, 'backgroundImagePath': ''}));
        if (![theme.backgroundColor, theme.textColor]
            .every((color) => RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(color))) {
          throw const FormatException('Invalid theme color');
        }
      }
      if (entry.key == 'remoteLibraryConnection') {
        LibraryConnectionStore.decode(value);
      }
      final range = switch (entry.key) {
        'ttsVolume' => (0.0, 1.0),
        'ttsRate' => (0.0, 2.0),
        'ttsPitch' => (0.5, 2.0),
        _ => null,
      };
      if (range != null && (value < range.$1 || value > range.$2)) {
        throw const FormatException('Invalid speech setting');
      }
      if (value is String &&
          (value.trimLeft().startsWith('{') ||
              value.trimLeft().startsWith('['))) {
        // CSS and prompts are free text, not JSON.
        if (!['customCSS'].contains(entry.key) &&
            !entry.key.startsWith('aiPrompt_')) {
          jsonDecode(value);
        }
      }
    }
  }

  /// Restore only fields present in the file; omitted secrets/local preferences
  /// stay untouched. Roll back on a write error. Does not initiate network work.
  static Future<void> apply(Prefs prefs, Map<String, dynamic> values) async {
    validate(values);
    final pending = <String, Object>{};
    for (final entry in values.entries) {
      if (entry.key == prefsBackupVersionKey) continue;
      if (_type(entry.key) == null || _type(entry.key) != entry.value['type']) {
        throw const FormatException('无效设置 / Invalid setting');
      }
      Object value = entry.value['value'];
      if (entry.key == 'readStyle' || entry.key == 'readTheme') {
        final data =
            Map<String, dynamic>.from(jsonDecode(value as String) as Map);
        if (entry.key == 'readStyle') {
          data['fontFamily'] = prefs.bookStyle.fontFamily;
        } else {
          data['backgroundImagePath'] = prefs.readTheme.backgroundImagePath;
          data['id'] = prefs.readTheme.id;
        }
        value = jsonEncode(data);
      }
      pending[entry.key] =
          entry.value['type'] == 'double' ? (value as num).toDouble() : value;
    }
    // Credentials may move but sync must be re-enabled on this device manually.
    if (values.containsKey('webdavInfo') ||
        values.containsKey('autoSync') ||
        values.containsKey('readingTimedSync')) {
      pending.addAll({
        'webdavStatus': false,
        'autoSync': false,
        'readingTimedSync': false
      });
    }
    final before = {for (final key in pending.keys) key: prefs.prefs.get(key)};
    try {
      for (final entry in pending.entries) {
        if (!await _write(prefs.prefs, entry.key, entry.value)) {
          throw StateError('Settings write failed');
        }
      }
    } catch (_) {
      for (final entry in before.entries) {
        await _write(prefs.prefs, entry.key, entry.value);
      }
      rethrow;
    }
    prefs.notifyExternalChange();
  }

  static Future<bool> _write(
      SharedPreferences prefs, String key, Object? value) {
    if (value == null) return prefs.remove(key);
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    if (value is String) return prefs.setString(key, value);
    return prefs.setStringList(key, (value as List).cast<String>());
  }
}
