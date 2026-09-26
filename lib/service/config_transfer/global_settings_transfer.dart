import 'dart:convert';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/custom_css_profile.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/models/selection_search.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/local_data/backup_safety.dart';
import 'package:anx_reader/service/config_transfer/config_transfer_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:anx_reader/service/config_transfer/settings_config_transfer.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:anx_reader/service/config_transfer/library_config_transfer.dart';
import 'package:anx_reader/service/config_transfer/settings_modules.dart';
import 'package:anx_reader/service/config_transfer/settings_value_validation.dart';
import 'package:anx_reader/enums/ai_prompts.dart';

/// Portable preferences only. Never restore databases, per-book IDs, migration
/// flags, storage paths, permissions, window geometry or device-local assets.
class GlobalSettingsTransfer {
  static const maxBytes = 4 * 1024 * 1024;
  static const kind = 'modu-global-settings';
  static final scopes =
      List<String>.unmodifiable(['all', ...settingsModuleKeys.keys]);
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
readingSyncMinutes excerptShareColorIndex excerptShareBgimgIndex httpProxyPort customCssDefaultIndex'''
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
webdavInfo syncProtocol remoteLibraryConnection remoteLibraryViewOptions selectionSearchSettings bgimg'''
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
    // Migrate in the snapshot only; do not mutate source preferences.
    if (prefs.prefs.getInt('fullTextTranslateRpm') case final int rpm) {
      values['aiRpm'] = {'type': 'int', 'value': rpm};
    }
    // Version 2 records explicit defaults as resets, instead of accidentally
    // retaining the receiving device's old values. Never reset absent secrets.
    for (final key in _types.keys) {
      if (!isCredentialPreference(key)) {
        values.putIfAbsent(key, () => {'type': 'reset', 'value': null});
      }
    }
    // These objects mix portable style with local file references. Materialize
    // their defaults so applying them can preserve the receiving local assets.
    values['readStyle'] = {'type': 'string', 'value': prefs.bookStyle.toJson()};
    values['readTheme'] = {'type': 'string', 'value': prefs.readTheme.toJson()};
    final background = prefs.bgimg.toJson()
      ..removeWhere((k, _) =>
          !['alignment', 'selectedMode', 'blur', 'opacity'].contains(k));
    values['bgimg'] = {'type': 'string', 'value': jsonEncode(background)};
    for (final prompt in AiPrompts.values) {
      values.putIfAbsent(
          'aiPrompt_${prompt.name}', () => {'type': 'reset', 'value': null});
    }
    for (final service in TtsConfigTransfer.services) {
      values.putIfAbsent(
          'ttsVoiceModel_$service', () => {'type': 'reset', 'value': null});
    }
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
    if (values['aiProviders']?['value'] case final String raw) {
      final providers = jsonDecode(raw) as List;
      for (final provider in providers) {
        (provider as Map)['keyIndex'] = 0;
      }
      values['aiProviders'] = {
        'type': 'string',
        'value': jsonEncode(providers)
      };
    }
    if (values['customCssProfiles']?['value'] case final String raw) {
      final profiles = jsonDecode(raw) as List;
      for (final profile in profiles) {
        if (profile['visual'] case final String visual) {
          final data = jsonDecode(visual) as Map;
          data.remove('fontFile'); // Files are not part of settings transfer.
          profile['visual'] = jsonEncode(data);
        }
      }
      values['customCssProfiles'] = {
        'type': 'string',
        'value': jsonEncode(profiles)
      };
    }
    validate(values);
    final envelope = {
      'kind': kind,
      'version': 2,
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

  static bool _inScope(String key, String scope) =>
      scope == 'all' || settingsModuleForKey(key) == scope;

  /// Filter actual keys, not the untrusted envelope's descriptive scope.
  static Map<String, dynamic> selectScope(
      Map<String, dynamic> values, String scope) {
    if (!scopes.contains(scope))
      throw const FormatException('Unknown settings scope');
    validate(values);
    return {
      for (final e in values.entries)
        if (e.key == prefsBackupVersionKey || _inScope(e.key, scope))
          e.key: e.value
    };
  }

  /// Describe the settings that will actually be applied, not an untrusted
  /// envelope label or the importing device's selected export scope. This also
  /// works for legacy links whose payload does not contain scope metadata.
  static List<String> includedScopes(Map<String, dynamic> values) {
    final included = <String>{};
    for (final key in values.keys) {
      if (key == prefsBackupVersionKey) continue;
      final module = settingsModuleForKey(key);
      if (module != null) included.add(module);
    }
    return [
      for (final scope in scopes.skip(1))
        if (included.contains(scope)) scope,
    ];
  }

  static bool disablesSync(Map<String, dynamic> values) =>
      values.containsKey('webdavInfo') ||
      values.containsKey('syncProtocol') ||
      values.containsKey('autoSync') ||
      values.containsKey('readingTimedSync');

  /// The credential switch applies in both directions. Never erase existing
  /// endpoint settings just because a sender included secrets in their file.
  static Map<String, dynamic> forImport(Map<String, dynamic> values,
      {bool includeSecrets = false}) {
    validate(values);
    if (includeSecrets) return Map<String, dynamic>.from(values);
    return withoutBackupCredentials(values)
      ..remove('selectedAiService')
      ..remove('translationAiService');
  }

  /// Old per-page links are still accepted at the single migration entry.
  /// ReadAny has no kind, so the user explicitly selects AI or WebDAV scope.
  static Map<String, dynamic>? legacy(String text, {String scope = 'all'}) {
    if (!text.trim().startsWith('modu:') &&
        !text.trim().startsWith('readany:')) {
      return null;
    }
    final decoded = ConfigTransferCodec.decode(text);
    if (decoded.kind == kind) return null;
    final data = decoded.data;
    final type = decoded.kind ??
        (scope != 'all'
            ? scope
            : data['endpoints'] is List || data['moduProviders'] is List
                ? 'ai'
                : data['backendType'] == 'webdav' ||
                        data['type'] == 'webdav' ||
                        (data['config'] is Map &&
                            data['config']['type'] == 'webdav')
                    ? 'webdav'
                    : 'unknown');
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
            '无法识别旧版配置类型 / Unrecognized legacy configuration');
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
        ![1, 2].contains(value['version']) ||
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
    if (file['version'] == 1 && values.values.any(_isReset)) {
      throw const FormatException('Defaults require settings format 2');
    }
    validate(values);
    return values;
  }

  static void validate(Map<String, dynamic> values) {
    validatePreferencesBackup({
      for (final e in values.entries)
        if (!_isReset(e.value)) e.key: e.value
    });
    for (final entry in values.entries) {
      if (entry.key == prefsBackupVersionKey) continue;
      if (_isReset(entry.value)) {
        if (_type(entry.key) == null ||
            isCredentialPreference(entry.key) ||
            ['readStyle', 'readTheme', 'bgimg'].contains(entry.key) ||
            entry.value['value'] != null) {
          throw const FormatException('Unsafe default reset');
        }
        continue;
      }
      if (_type(entry.key) != entry.value['type'] || _type(entry.key) == null) {
        throw const FormatException(
            '包含不支持或不安全的设置 / Unsupported or unsafe setting');
      }
      // Validate structured payloads before ANY setting is applied.
      final value = entry.value['value'];
      validateSettingsValue(entry.key, value);
      if (entry.key == 'customCssProfiles') {
        final profiles = jsonDecode(value as String);
        if (profiles is! List || profiles.length > customCssProfileCount) {
          throw const FormatException('Invalid CSS profiles');
        }
        for (final profile in profiles) {
          if (profile is! Map ||
              profile['css'] is! String ||
              (profile.containsKey('visual') && profile['visual'] is! String)) {
            throw const FormatException('Invalid CSS profile');
          }
          CustomCssProfile.fromJson(profile);
        }
      }
      if (entry.key == 'selectionSearchSettings') {
        SelectionSearchConfig.decode(value as String);
      }
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
    }
  }

  static bool _isReset(dynamic entry) =>
      entry is Map && entry['type'] == 'reset';

  /// Restore only fields present in the file; omitted secrets/local preferences
  /// stay untouched. Roll back on a write error. Does not initiate network work.
  static Future<void> apply(Prefs prefs, Map<String, dynamic> values) async {
    validate(values);
    final pending = <String, Object?>{};
    for (final entry in values.entries) {
      if (entry.key == prefsBackupVersionKey) continue;
      if (_isReset(entry.value)) {
        pending[entry.key] = null;
        continue;
      }
      if (_type(entry.key) == null || _type(entry.key) != entry.value['type']) {
        throw const FormatException('无效设置 / Invalid setting');
      }
      Object value = entry.value['value'];
      if (entry.key == 'bgimg') {
        value = jsonEncode({
          ...prefs.bgimg.toJson(),
          ...jsonDecode(value as String) as Map<String, dynamic>
        });
      }
      if (entry.key == 'readStyle' || entry.key == 'readTheme') {
        var data =
            Map<String, dynamic>.from(jsonDecode(value as String) as Map);
        if (entry.key == 'readStyle') {
          data =
              BookStyle.fromJson(jsonEncode({...data, 'fontFamily': 'Arial'}))
                  .toMap();
          data['fontFamily'] = prefs.bookStyle.fontFamily;
        } else {
          data = {
            'backgroundColor': data['backgroundColor'],
            'textColor': data['textColor'],
            'backgroundImagePath': prefs.readTheme.backgroundImagePath,
            'id': prefs.readTheme.id,
          };
        }
        value = jsonEncode(data);
      }
      if (entry.key == 'customCssProfiles') {
        final profiles = jsonDecode(value as String) as List;
        for (final profile in profiles) {
          if (profile['visual'] case final String visual) {
            profile['visual'] =
                jsonEncode((jsonDecode(visual) as Map)..remove('fontFile'));
          }
        }
        value = jsonEncode(profiles);
      }
      pending[entry.key] =
          entry.value['type'] == 'double' ? (value as num).toDouble() : value;
    }
    // Credentials may move but sync must be re-enabled on this device manually.
    if (disablesSync(values)) {
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
