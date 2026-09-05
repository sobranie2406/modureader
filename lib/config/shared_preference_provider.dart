import 'dart:convert';
import 'dart:core';

import 'package:anx_reader/enums/ai_prompts.dart';
import 'package:anx_reader/enums/bgimg_alignment.dart';
import 'package:anx_reader/enums/bgimg_type.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/enums/convert_chinese_mode.dart';
import 'package:anx_reader/enums/excerpt_share_template.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/enums/sort_field.dart';
import 'package:anx_reader/enums/sort_order.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/enums/text_alignment.dart';
import 'package:anx_reader/enums/ai_panel_position.dart';
import 'package:anx_reader/enums/ai_chat_display_mode.dart';
import 'package:anx_reader/enums/bgimg_fit.dart';
import 'package:anx_reader/enums/code_highlight_theme.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/bgimg.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/chapter_split_presets.dart';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/models/book_notes_state.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/models/reading_info.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/models/window_info.dart';
import 'package:anx_reader/service/ai/tools/ai_tool_registry.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/get_current_language_code.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String prefsBackupVersionKey = '__prefsBackupVersion';
const int prefsBackupSchemaVersion = 1;
const String _prefsBackupEntryTypeKey = 'type';
const String _prefsBackupEntryValueKey = 'value';

const Set<String> _prefsImportSkipKeys = {
  'iapPurchaseStatus',
  'iapLastCheckTime',
  // Enabling sensitive sync requires an explicit risk confirmation on each
  // device. Never restore this switch or its local-only password silently.
  'syncAiSettingsToWebdav',
  'syncAiSettingsEncryptionPassword',
};

const Set<String> _prefsExportSkipKeys = {
  // The encryption password must remain local and must not be copied into an
  // app backup or uploaded alongside the encrypted payload.
  'syncAiSettingsEncryptionPassword',
};

class Prefs extends ChangeNotifier {
  late SharedPreferences prefs;
  static final Prefs _instance = Prefs._internal();

  /// Notifies settings consumers after a validated external restore.
  void notifyExternalChange() => notifyListeners();

  factory Prefs() {
    return _instance;
  }

  Prefs._internal() {
    initPrefs();
  }

  static const String _chapterSplitSelectedRuleKey =
      'chapterSplitSelectedRuleId';
  static const String _chapterSplitCustomRulesKey = 'chapterSplitCustomRules';
  static const String _statisticsDashboardTilesKey = 'statisticsDashboardTiles';
  static const String _enabledAiToolsKey = 'enabledAiTools';
  static const String _userPromptsKey = 'userPrompts';
  static const String _readAnySkillStatesKey = 'readAnySkillStates';
  static const String _readAnySkillPromptsKey = 'readAnySkillPrompts';
  static const String _vectorModelConfigKey = 'vectorModelConfig';

  Future<void> initPrefs() async {
    prefs = await SharedPreferences.getInstance();
    saveBeginDate();
    notifyListeners();
  }

  Future<Map<String, dynamic>> buildPrefsBackupMap() async {
    Map<String, Object?>? encodePrefsBackupEntry(Object? value) {
      if (value is bool) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'bool',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is int) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'int',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is double) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'double',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is String) {
        return <String, Object?>{
          _prefsBackupEntryTypeKey: 'string',
          _prefsBackupEntryValueKey: value,
        };
      }
      if (value is List) {
        final bool allStrings =
            value.every((dynamic element) => element is String);
        if (allStrings) {
          return <String, Object?>{
            _prefsBackupEntryTypeKey: 'stringList',
            _prefsBackupEntryValueKey:
                List<String>.from(value, growable: false),
          };
        }
      }
      return null;
    }

    final Map<String, dynamic> backup = <String, dynamic>{
      prefsBackupVersionKey: prefsBackupSchemaVersion,
    };
    for (final String key in prefs.getKeys()) {
      if (_prefsExportSkipKeys.contains(key)) continue;
      final Object? value = prefs.get(key);
      final Map<String, Object?>? encoded = encodePrefsBackupEntry(value);
      if (encoded != null) {
        backup[key] = encoded;
      }
    }
    return backup;
  }

  Future<void> applyPrefsBackupMap(Map<String, dynamic> backup) async {
    for (final MapEntry<String, dynamic> entry in backup.entries) {
      final String key = entry.key;
      if (key == prefsBackupVersionKey || _prefsImportSkipKeys.contains(key)) {
        continue;
      }
      final dynamic entryValue = entry.value;
      if (entryValue is! Map) continue;
      final dynamic type = entryValue[_prefsBackupEntryTypeKey];
      final dynamic value = entryValue[_prefsBackupEntryValueKey];
      if (type is! String) continue;
      switch (type) {
        case 'bool':
          if (value is bool) await prefs.setBool(key, value);
          break;
        case 'int':
          if (value is int) await prefs.setInt(key, value);
          break;
        case 'double':
          if (value is num) await prefs.setDouble(key, value.toDouble());
          break;
        case 'string':
          if (value is String) await prefs.setString(key, value);
          break;
        case 'stringList':
          if (value is List) {
            final List<String> list =
                value.map((dynamic v) => v as String).toList();
            await prefs.setStringList(key, list);
          }
          break;
        default:
          continue;
      }
    }
    notifyListeners();
  }

  Color get themeColor {
    int colorValue = prefs.getInt('themeColor') ?? Colors.blue.value;
    return Color(colorValue);
  }

  Future<void> saveThemeToPrefs(int colorValue) async {
    await prefs.setInt('themeColor', colorValue);
    notifyListeners();
  }

  Locale? get locale {
    String? localeCode = prefs.getString('locale');
    if (localeCode == null || localeCode == 'System') return null;
    if (localeCode.contains('-')) {
      List<String> codes = localeCode.split('-');
      return Locale(codes[0], codes[1]);
    }
    return Locale(localeCode);
  }

  Future<void> saveLocaleToPrefs(String localeCode) async {
    await prefs.setString('locale', localeCode);
    notifyListeners();
  }

  ThemeMode get themeMode {
    String themeMode = prefs.getString('themeMode') ?? 'system';
    switch (themeMode) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> saveThemeModeToPrefs(String themeMode) async {
    await prefs.setString('themeMode', themeMode);
    notifyListeners();
  }

  Future<void> saveBookStyleToPrefs(BookStyle bookStyle) async {
    await prefs.setString('readStyle', bookStyle.toJson());
    notifyListeners();
  }

  BookStyle get bookStyle {
    String? bookStyleJson = prefs.getString('readStyle');
    if (bookStyleJson == null) return BookStyle();
    return BookStyle.fromJson(bookStyleJson);
  }

  void removeBookStyle() {
    prefs.remove('readStyle');
    notifyListeners();
  }

  void saveReadThemeToPrefs(ReadTheme readTheme) {
    prefs.setString('readTheme', readTheme.toJson());
    notifyListeners();
  }

  ReadTheme get readTheme {
    String? readThemeJson = prefs.getString('readTheme');
    if (readThemeJson == null) {
      return ReadTheme(
          backgroundColor: 'FFFBFBF3',
          textColor: 'FF343434',
          backgroundImagePath: '');
    }
    return ReadTheme.fromJson(readThemeJson);
  }

  void saveBeginDate() {
    String? beginDate = prefs.getString('beginDate');
    if (beginDate == null) {
      prefs.setString('beginDate', DateTime.now().toIso8601String());
    }
  }

  DateTime? get beginDate {
    String? beginDateStr = prefs.getString('beginDate');
    if (beginDateStr == null) return null;
    return DateTime.parse(beginDateStr);
  }

  // void saveWebdavInfo(Map webdavInfo) {
  //   prefs.setString('webdavInfo', jsonEncode(webdavInfo));
  //   notifyListeners();
  // }

  // Map get webdavInfo {
  //   String? webdavInfoJson = prefs.getString('webdavInfo');
  //   if (webdavInfoJson == null) {
  //     return {};
  //   }
  //   return jsonDecode(webdavInfoJson);
  // }

  // Sync protocol selection
  String? get syncProtocol {
    return prefs.getString('syncProtocol');
  }

  set syncProtocol(String? protocol) {
    if (protocol != null) {
      prefs.setString('syncProtocol', protocol);
    } else {
      prefs.remove('syncProtocol');
    }
    notifyListeners();
  }

  Map<String, dynamic> getSyncInfo(SyncProtocol protocol) {
    String? syncInfoJson = prefs.getString('${protocol.name}Info');
    if (syncInfoJson == null) return {};
    return Map<String, dynamic>.from(jsonDecode(syncInfoJson));
  }

  setSyncInfo(SyncProtocol protocol, Map<String, dynamic>? info) {
    if (info != null) {
      prefs.setString('${protocol.name}Info', jsonEncode(info));
    } else {
      prefs.remove('${protocol.name}Info');
    }
    notifyListeners();
  }

  void saveWebdavStatus(bool status) {
    prefs.setBool('webdavStatus', status);
    notifyListeners();
  }

  bool get webdavStatus {
    return prefs.getBool('webdavStatus') ?? false;
  }

  void saveClearLogWhenStart(bool status) {
    prefs.setBool('clearLogWhenStart', status);
    notifyListeners();
  }

  bool get reduceVibrationFeedback {
    return prefs.getBool('reduceVibrationFeedback') ?? false;
  }

  set reduceVibrationFeedback(bool value) {
    prefs.setBool('reduceVibrationFeedback', value);
    notifyListeners();
  }

  bool get developerOptionsEnabled {
    return prefs.getBool("developerOptionsEnabled") ?? false;
  }

  set developerOptionsEnabled(bool value) {
    prefs.setBool("developerOptionsEnabled", value);
    notifyListeners();
  }

  List<StatisticsDashboardTileType> get statisticsDashboardTiles {
    final stored = prefs.getStringList(_statisticsDashboardTilesKey);
    if (stored == null || stored.isEmpty) {
      return List<StatisticsDashboardTileType>.from(
        defaultStatisticsDashboardTiles,
      );
    }
    final mapped = stored
        .map(_statisticsDashboardTileFromName)
        .whereType<StatisticsDashboardTileType>()
        .toList();
    if (mapped.isEmpty) {
      return List<StatisticsDashboardTileType>.from(
        defaultStatisticsDashboardTiles,
      );
    }
    return mapped;
  }

  set statisticsDashboardTiles(List<StatisticsDashboardTileType> tiles) {
    prefs.setStringList(
      _statisticsDashboardTilesKey,
      tiles.map((e) => e.name).toList(),
    );
    notifyListeners();
  }

  StatisticsDashboardTileType? _statisticsDashboardTileFromName(String name) {
    try {
      return StatisticsDashboardTileType.values
          .firstWhere((element) => element.name == name);
    } catch (_) {
      return null;
    }
  }

  bool get clearLogWhenStart {
    return prefs.getBool('clearLogWhenStart') ?? true;
  }

  bool get useOriginalCoverRatio {
    return prefs.getBool('useOriginalCoverRatio') ?? false;
  }

  set useOriginalCoverRatio(bool value) {
    prefs.setBool('useOriginalCoverRatio', value);
    notifyListeners();
  }

  void saveHideStatusBar(bool status) {
    prefs.setBool('hideStatusBar', status);
    notifyListeners();
  }

  bool get hideStatusBar {
    return prefs.getBool('hideStatusBar') ?? true;
  }

  bool get readerFullscreen => prefs.getBool('readerFullscreen') ?? false;
  Future<void> saveReaderFullscreen(bool value) async {
    await prefs.setBool('readerFullscreen', value);
    notifyListeners();
  }

  set autoHideBottomBar(bool status) {
    prefs.setBool('autoHideBottomBar', status);
    notifyListeners();
  }

  bool get autoHideBottomBar {
    return prefs.getBool('autoHideBottomBar') ?? false;
  }

  set awakeTime(int minutes) {
    prefs.setInt('awakeTime', minutes);
    notifyListeners();
  }

  int get awakeTime {
    return prefs.getInt('awakeTime') ?? 5;
  }

  set lastShowUpdate(DateTime time) {
    prefs.setString('lastShowUpdate', time.toIso8601String());
    notifyListeners();
  }

  DateTime get lastShowUpdate {
    String? lastShowUpdateStr = prefs.getString('lastShowUpdate');
    if (lastShowUpdateStr == null) return DateTime(1970, 1, 1);
    return DateTime.parse(lastShowUpdateStr);
  }

  set pageTurningType(int type) {
    prefs.setInt('pageTurningType', type);
    notifyListeners();
  }

  int get pageTurningType {
    return prefs.getInt('pageTurningType') ?? 0;
  }

  set annotationType(String style) {
    prefs.setString('annotationType', style);
    notifyListeners();
  }

  String get annotationType {
    return prefs.getString('annotationType') ?? 'highlight';
  }

  set annotationColor(String color) {
    prefs.setString('annotationColor', color);
    notifyListeners();
  }

  String get annotationColor {
    return prefs.getString('annotationColor') ?? '66CCFF';
  }

  set ttsVolume(double volume) {
    prefs.setDouble('ttsVolume', volume);
    notifyListeners();
  }

  double get ttsVolume {
    return prefs.getDouble('ttsVolume') ?? 1.0;
  }

  set ttsPitch(double pitch) {
    prefs.setDouble('ttsPitch', pitch);
    notifyListeners();
  }

  double get ttsPitch {
    return prefs.getDouble('ttsPitch') ?? 1.0;
  }

  set ttsRate(double rate) {
    prefs.setDouble('ttsRate', rate);
    notifyListeners();
  }

  double get ttsRate {
    return prefs.getDouble('ttsRate') ?? 0.6;
  }

  void setTtsVoiceModel(String serviceId, String shortName) {
    prefs.setString('ttsVoiceModel_$serviceId', shortName);
    notifyListeners();
  }

  void removeTtsVoiceModel(String serviceId) {
    prefs.remove('ttsVoiceModel_$serviceId');
    notifyListeners();
  }

  String getTtsVoiceModel(String serviceId) {
    return prefs.getString('ttsVoiceModel_$serviceId') ?? '';
  }

  set ttsService(String serviceId) {
    prefs.setString('ttsService', serviceId);
    notifyListeners();
  }

  String get ttsService {
    String? service = prefs.getString('ttsService');
    if (service != null) {
      // Removed legacy providers may still be stored by an older installation.
      return const {'aliyun', 'azure'}.contains(service) ? 'system' : service;
    }

    // Migration/Fallback
    bool isSystem = prefs.getBool('isSystemTts') ??
        true; // Default to system if nothing set
    if (!isSystem) {
      // Check if there was an online service set
      String? online = prefs.getString('onlineTtsService');
      if (online != null) {
        return const {'aliyun', 'azure'}.contains(online) ? 'system' : online;
      }
    }
    return 'system';
  }

  Map<String, dynamic> getOnlineTtsConfig(String serviceId) {
    String? json = prefs.getString('onlineTtsConfig_$serviceId');
    if (json == null) return {};
    try {
      return jsonDecode(json) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  Future<void> saveOnlineTtsConfig(
      String serviceId, Map<String, dynamic> config) async {
    await prefs.setString('onlineTtsConfig_$serviceId', jsonEncode(config));
    notifyListeners();
  }

  set pageTurnStyle(PageTurn style) {
    prefs.setString('pageTurnStyle', style.name);
    notifyListeners();
  }

  PageTurn get pageTurnStyle {
    String? style = prefs.getString('pageTurnStyle');
    if (style == null) return PageTurn.slide;
    return PageTurn.values.firstWhere((element) => element.name == style);
  }

  set font(FontModel font) {
    prefs.setString('font', font.toJson());
    notifyListeners();
  }

  FontModel get font {
    String? fontJson = prefs.getString('font');
    BuildContext context = navigatorKey.currentContext!;
    if (fontJson == null) {
      return FontModel(
          label: L10n.of(context).followBook, name: 'book', path: 'book');
    }
    return FontModel.fromJson(fontJson);
  }

  set trueDarkMode(bool status) {
    prefs.setBool('trueDarkMode', status);
    notifyListeners();
  }

  bool get trueDarkMode {
    return prefs.getBool('trueDarkMode') ?? false;
  }

  set eInkMode(bool status) {
    prefs.setBool('eInkMode', status);
    notifyListeners();
  }

  bool get eInkMode {
    return prefs.getBool('eInkMode') ?? false;
  }

  set translateService(TranslateService service) {
    prefs.setString('translateService', service.name);
    notifyListeners();
  }

  TranslateService get translateService {
    return getTranslateService(
        prefs.getString('translateService') ?? 'microsoftFree');
  }

  set translateFrom(LangListEnum from) {
    prefs.setString('translateFrom', from.code);
    notifyListeners();
  }

  LangListEnum get translateFrom {
    return getLang(prefs.getString('translateFrom') ?? 'auto');
  }

  set translateTo(LangListEnum to) {
    prefs.setString('translateTo', to.code);
    notifyListeners();
  }

  LangListEnum get translateTo {
    return getLang(prefs.getString('translateTo') ?? getCurrentLanguageCode());
  }

  set autoTranslateSelection(bool status) {
    prefs.setBool('autoTranslateSelection', status);
    notifyListeners();
  }

  bool get autoTranslateSelection {
    return prefs.getBool('autoTranslateSelection') ?? false;
  }

  set autoMarkSelection(bool status) {
    prefs.setBool('autoMarkSelection', status);
    notifyListeners();
  }

  bool get autoMarkSelection {
    return prefs.getBool('autoMarkSelection') ?? false;
  }

  set fullTextTranslateService(TranslateService service) {
    prefs.setString('fullTextTranslateService', service.name);
    notifyListeners();
  }

  TranslateService get fullTextTranslateService {
    final serviceName =
        prefs.getString('fullTextTranslateService') ?? 'microsoftFree';
    if (serviceName == 'microsoft') {
      prefs.setString('fullTextTranslateService', 'microsoftApi');
      return TranslateService.microsoftApi;
    }
    return getTranslateService(serviceName);
  }

  set translationAiService(String identifier) {
    prefs.setString('translationAiService', identifier);
    notifyListeners();
  }

  /// AI endpoint/model used only for translation, matching ReadAny's separate
  /// translation-model selector. Falls back to the default AI endpoint.
  String get translationAiService {
    final configured = prefs.getString('translationAiService');
    final providers = getAiProviders();
    if (providers.isEmpty) return selectedAiService;

    bool isUsable(dynamic item) {
      if (item is! Map) return false;
      final provider = Map<String, dynamic>.from(item);
      if (provider['enabled'] == false ||
          (provider['model']?.toString().trim().isEmpty ?? true)) {
        return false;
      }
      final keys = provider['apiKeys'];
      return keys is List &&
          keys.any((item) =>
              item is Map &&
              item['enabled'] != false &&
              (item['key']?.toString().trim().isNotEmpty ?? false));
    }

    final usable = providers.where(isUsable).toList(growable: false);
    if (usable.isEmpty) return selectedAiService;
    if (configured != null &&
        configured.isNotEmpty &&
        usable.any((item) => item is Map && item['id'] == configured)) {
      return configured;
    }
    final selected = selectedAiService;
    if (usable.any((item) => item is Map && item['id'] == selected)) {
      return selected;
    }
    return (usable.first as Map)['id']?.toString() ?? selected;
  }

  set fullTextTranslateFrom(LangListEnum from) {
    prefs.setString('fullTextTranslateFrom', from.code);
    notifyListeners();
  }

  LangListEnum get fullTextTranslateFrom {
    return getLang(prefs.getString('fullTextTranslateFrom') ?? 'auto');
  }

  set fullTextTranslateTo(LangListEnum to) {
    prefs.setString('fullTextTranslateTo', to.code);
    notifyListeners();
  }

  LangListEnum get fullTextTranslateTo {
    return getLang(
        prefs.getString('fullTextTranslateTo') ?? getCurrentLanguageCode());
  }

  set aiRpm(int rpm) {
    prefs.setInt('aiRpm', rpm < 0 ? 0 : rpm);
    notifyListeners();
  }

  /// Maximum AI requests per minute across all AI features. 0 means unlimited.
  int get aiRpm {
    // Migrate from old fullTextTranslateRpm key if present
    final legacy = prefs.getInt('fullTextTranslateRpm');
    if (legacy != null) {
      prefs.setInt('aiRpm', legacy);
      prefs.remove('fullTextTranslateRpm');
      return legacy;
    }
    return prefs.getInt('aiRpm') ?? 0;
  }

  // set convertChineseMode(ConvertChineseMode mode) {
  //   prefs.setString('convertChineseMode', mode.name);
  //   notifyListeners();
  // }

  // ConvertChineseMode get convertChineseMode {
  //   return getConvertChineseMode(
  //       prefs.getString('convertChineseMode') ?? 'none');
  // }

  set readingRules(ReadingRules rules) {
    prefs.setString('readingRules', rules.toJson().toString());
    notifyListeners();
  }

  ReadingRules get readingRules {
    String? rulesJson = prefs.getString('readingRules');
    if (rulesJson == null) {
      return ReadingRules(
        convertChineseMode: ConvertChineseMode.none,
        bionicReading: false,
      );
    }
    return ReadingRules.fromJson(rulesJson);
  }

  List<ChapterSplitRule> get chapterSplitCustomRules {
    final raw = prefs.getString(_chapterSplitCustomRulesKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((entry) {
        if (entry is Map<String, dynamic>) {
          return ChapterSplitRule.fromMap(entry);
        }
        if (entry is Map) {
          return ChapterSplitRule.fromMap(Map<String, dynamic>.from(entry));
        }
        throw const FormatException('Invalid chapter split rule entry');
      }).toList();
    } catch (e) {
      AnxLog.warning('Prefs: Failed to decode custom chapter split rules. $e');

      return const [];
    }
  }

  set chapterSplitCustomRules(List<ChapterSplitRule> rules) {
    final encoded = jsonEncode(rules.map((rule) => rule.toMap()).toList());
    prefs.setString(_chapterSplitCustomRulesKey, encoded);
    notifyListeners();
  }

  List<ChapterSplitRule> get allChapterSplitRules {
    return [
      ...builtinChapterSplitRules,
      ...chapterSplitCustomRules,
    ];
  }

  String? get _storedChapterSplitRuleId {
    return prefs.getString(_chapterSplitSelectedRuleKey);
  }

  set _storedChapterSplitRuleId(String? id) {
    if (id == null) {
      prefs.remove(_chapterSplitSelectedRuleKey);
    } else {
      prefs.setString(_chapterSplitSelectedRuleKey, id);
    }
    notifyListeners();
  }

  ChapterSplitRule get activeChapterSplitRule {
    final selectedId = _storedChapterSplitRuleId;

    if (selectedId != null) {
      final builtin = findBuiltinChapterSplitRuleById(selectedId);
      if (builtin != null) {
        try {
          builtin.buildRegExp();
          return builtin;
        } catch (_) {}
      }

      final custom = chapterSplitCustomRules
          .where((rule) => rule.id == selectedId)
          .toList();
      if (custom.isNotEmpty) {
        final rule = custom.first;
        try {
          rule.buildRegExp();
          return rule;
        } catch (_) {}
      }
    }

    return getDefaultChapterSplitRule();
  }

  void selectChapterSplitRule(String id) {
    _storedChapterSplitRuleId = id;
  }

  String? get chapterSplitSelectedRuleId => _storedChapterSplitRuleId;

  void saveCustomChapterSplitRule(ChapterSplitRule rule) {
    if (rule.isBuiltin) {
      return;
    }

    final rules = List<ChapterSplitRule>.from(chapterSplitCustomRules);
    final index = rules.indexWhere((existing) => existing.id == rule.id);

    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }

    chapterSplitCustomRules = rules;
  }

  void deleteCustomChapterSplitRule(String id) {
    final rules = chapterSplitCustomRules
        .where((rule) => rule.id != id)
        .toList(growable: false);

    chapterSplitCustomRules = rules;

    if (_storedChapterSplitRuleId == id) {
      _storedChapterSplitRuleId = kDefaultChapterSplitRuleId;
    }
  }

  set windowInfo(WindowInfo info) {
    prefs.setString('windowInfo', jsonEncode(info.toJson()));
    notifyListeners();
  }

  WindowInfo get windowInfo {
    String? windowInfoJson = prefs.getString('windowInfo');
    if (windowInfoJson == null) {
      return const WindowInfo(x: 0, y: 0, width: 0, height: 0);
    }
    return WindowInfo.fromJson(jsonDecode(windowInfoJson));
  }

  /// Custom storage path for Windows/macOS
  String? get customStoragePath => prefs.getString('customStoragePath');

  set customStoragePath(String? value) {
    if (value == null) {
      prefs.remove('customStoragePath');
    } else {
      prefs.setString('customStoragePath', value);
    }
    notifyListeners();
  }

  void saveAiConfig(String identifier, Map<String, String> config) {
    prefs.setString('aiConfig_$identifier', jsonEncode(config));
    notifyListeners();
  }

  Map<String, String> getAiConfig(String identifier) {
    String? aiConfigJson = prefs.getString('aiConfig_$identifier');
    if (aiConfigJson == null) {
      return {};
    }
    Map<String, dynamic> decoded = jsonDecode(aiConfigJson);
    return decoded.map((key, value) => MapEntry(key, value.toString()));
  }

  set selectedAiService(String identifier) {
    prefs.setString('selectedAiService', identifier);
    notifyListeners();
  }

  String get selectedAiService {
    return prefs.getString('selectedAiService') ?? 'openai';
  }

  double get aiTemperature => prefs.getDouble('aiTemperature') ?? 0.7;

  set aiTemperature(double value) {
    prefs.setDouble('aiTemperature', value.clamp(0.0, 1.0));
    notifyListeners();
  }

  int get aiMaxTokens => prefs.getInt('aiMaxTokens') ?? 8192;

  set aiMaxTokens(int value) {
    prefs.setInt('aiMaxTokens', value.clamp(1024, 32768));
    notifyListeners();
  }

  int get aiContextTurns => prefs.getInt('aiContextTurns') ?? 8;

  set aiContextTurns(int value) {
    prefs.setInt('aiContextTurns', value.clamp(2, 30));
    notifyListeners();
  }

  bool get vectorModelEnabled => prefs.getBool('vectorModelEnabled') ?? true;

  set vectorModelEnabled(bool value) {
    prefs.setBool('vectorModelEnabled', value);
    notifyListeners();
  }

  bool get autoVectorizeOnImport =>
      prefs.getBool('autoVectorizeOnImport') ?? false;

  set autoVectorizeOnImport(bool value) {
    prefs.setBool('autoVectorizeOnImport', value);
    notifyListeners();
  }

  String get vectorModelMode => prefs.getString('vectorModelMode') ?? 'builtin';

  set vectorModelMode(String value) {
    prefs.setString(
      'vectorModelMode',
      value == 'remote' ? 'remote' : 'builtin',
    );
    notifyListeners();
  }

  String get vectorLocalModelId =>
      prefs.getString('vectorLocalModelId') ?? 'bge-small-zh-v1.5';

  set vectorLocalModelId(String value) {
    prefs.setString('vectorLocalModelId', value);
    notifyListeners();
  }

  Map<String, dynamic> get vectorModelConfig {
    final raw = prefs.getString(_vectorModelConfigKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveVectorModelConfig(Map<String, dynamic> config) async {
    await prefs.setString(_vectorModelConfigKey, jsonEncode(config));
    notifyListeners();
  }

  void deleteAiConfig(String identifier) {
    prefs.remove('aiConfig_$identifier');
    notifyListeners();
  }

  void saveAiProviders(List<dynamic> providers) {
    final jsonList = providers.map((p) {
      // Handle both AiProvider objects and already-serialized maps
      if (p is Map<String, dynamic>) {
        return p;
      } else {
        return p.toJson();
      }
    }).toList();
    prefs.setString('aiProviders', jsonEncode(jsonList));
    notifyListeners();
  }

  List<dynamic> getAiProviders() {
    String? jsonString = prefs.getString('aiProviders');
    if (jsonString == null) {
      return [];
    }
    try {
      final List<dynamic> decoded = jsonDecode(jsonString);
      // Import will be handled in ai_providers.dart to avoid circular dependency
      return decoded;
    } catch (e) {
      return [];
    }
  }

  void saveAiPrompt(AiPrompts identifier, String prompt) {
    prefs.setString('aiPrompt_${identifier.name}', prompt);
    notifyListeners();
  }

  String getAiPrompt(AiPrompts identifier) {
    String? aiPrompt = prefs.getString('aiPrompt_${identifier.name}');
    if (aiPrompt == null) {
      return identifier.getPrompt();
    }
    return aiPrompt;
  }

  void deleteAiPrompt(AiPrompts identifier) {
    prefs.remove('aiPrompt_${identifier.name}');
    notifyListeners();
  }

  List<String> get enabledAiToolIds {
    final stored = prefs.getStringList(_enabledAiToolsKey);
    if (stored == null) {
      return AiToolRegistry.defaultEnabledToolIds();
    }
    if (stored.isEmpty) {
      return const [];
    }
    final sanitized = AiToolRegistry.sanitizeIds(stored);
    if (sanitized.isEmpty && stored.isNotEmpty) {
      return AiToolRegistry.defaultEnabledToolIds();
    }
    return sanitized;
  }

  set enabledAiToolIds(List<String> ids) {
    prefs.setStringList(
      _enabledAiToolsKey,
      AiToolRegistry.sanitizeIds(ids),
    );
    notifyListeners();
  }

  bool isAiToolEnabled(String id) {
    return enabledAiToolIds.contains(id);
  }

  void resetEnabledAiTools() {
    prefs.remove(_enabledAiToolsKey);
    notifyListeners();
  }

  bool shouldShowHint(HintKey key) {
    return prefs.getBool('hint_${key.code}') ?? true;
  }

  void setShowHint(HintKey key, bool value) {
    prefs.setBool('hint_${key.code}', value);
    notifyListeners();
  }

  void resetHints() {
    for (final hint in HintKey.values) {
      prefs.remove('hint_${hint.code}');
    }
    notifyListeners();
  }

  set autoSummaryPreviousContent(bool status) {
    prefs.setBool('autoSummaryPreviousContent', status);
    notifyListeners();
  }

  bool get autoSummaryPreviousContent {
    return prefs.getBool('autoSummaryPreviousContent') ?? false;
  }

  set autoAdjustReadingTheme(bool status) {
    prefs.setBool('autoAdjustReadingTheme', status);
    notifyListeners();
  }

  bool get autoAdjustReadingTheme {
    return prefs.getBool('autoAdjustReadingTheme') ?? false;
  }

  // User prompts - simple read/write methods
  List<UserPrompt> get userPrompts {
    final jsonString = prefs.getString(_userPromptsKey);
    if (jsonString == null || jsonString.isEmpty) return [];

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList
          .map((json) => UserPrompt.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AnxLog.severe('Error loading user prompts: $e');
      return [];
    }
  }

  set userPrompts(List<UserPrompt> prompts) {
    final jsonList = prompts.map((p) => p.toJson()).toList();
    prefs.setString(_userPromptsKey, jsonEncode(jsonList));
    notifyListeners();
  }

  Map<String, bool> get readAnySkillStates {
    final jsonString = prefs.getString(_readAnySkillStatesKey);
    if (jsonString == null || jsonString.isEmpty) return const {};
    try {
      final values = jsonDecode(jsonString) as Map<String, dynamic>;
      return values.map((key, value) => MapEntry(key, value == true));
    } catch (error) {
      AnxLog.warning('Error loading ReadAny skill states: $error');
      return const {};
    }
  }

  bool isReadAnySkillEnabled(String skillId) {
    return readAnySkillStates[skillId] ?? true;
  }

  void setReadAnySkillEnabled(String skillId, bool enabled) {
    final states = Map<String, bool>.from(readAnySkillStates);
    states[skillId] = enabled;
    prefs.setString(_readAnySkillStatesKey, jsonEncode(states));
    notifyListeners();
  }

  Map<String, String> get readAnySkillPrompts {
    final jsonString = prefs.getString(_readAnySkillPromptsKey);
    if (jsonString == null || jsonString.isEmpty) return const {};
    try {
      final values = jsonDecode(jsonString) as Map<String, dynamic>;
      return values.map((key, value) => MapEntry(key, value.toString()));
    } catch (error) {
      AnxLog.warning('Error loading AI reading skill prompts: $error');
      return const {};
    }
  }

  String getReadAnySkillPrompt(String skillId, String defaultPrompt) {
    final saved = readAnySkillPrompts[skillId]?.trim();
    return saved == null || saved.isEmpty ? defaultPrompt : saved;
  }

  void setReadAnySkillPrompt(String skillId, String prompt) {
    final prompts = Map<String, String>.from(readAnySkillPrompts);
    prompts[skillId] = prompt;
    prefs.setString(_readAnySkillPromptsKey, jsonEncode(prompts));
    notifyListeners();
  }

  void resetReadAnySkillPrompt(String skillId) {
    final prompts = Map<String, String>.from(readAnySkillPrompts)
      ..remove(skillId);
    prefs.setString(_readAnySkillPromptsKey, jsonEncode(prompts));
    notifyListeners();
  }

  set maxAiCacheCount(int count) {
    prefs.setInt('maxAiCacheCount', count);
    notifyListeners();
  }

  int get maxAiCacheCount {
    return prefs.getInt('maxAiCacheCount') ?? 300;
  }

  set aiChatFontSize(double size) {
    prefs.setDouble('aiChatFontSize', size);
    notifyListeners();
  }

  double get aiChatFontSize {
    return prefs.getDouble('aiChatFontSize') ?? 14.0;
  }

  set volumeKeyTurnPage(bool status) {
    prefs.setBool('volumeKeyTurnPage', status);
    notifyListeners();
  }

  bool get volumeKeyTurnPage {
    return prefs.getBool('volumeKeyTurnPage') ?? false;
  }

  set keyboardShortcutTurnPage(bool status) {
    prefs.setBool('keyboardShortcutTurnPage', status);
    notifyListeners();
  }

  bool get keyboardShortcutTurnPage {
    return prefs.getBool('keyboardShortcutTurnPage') ?? false;
  }

  set swapPageTurnArea(bool status) {
    prefs.setBool('swapPageTurnArea', status);
  }

  bool get swapPageTurnArea {
    return prefs.getBool('swapPageTurnArea') ?? false;
  }

  set showMenuOnHover(bool status) {
    prefs.setBool('showMenuOnHover', status);
    notifyListeners();
  }

  bool get showMenuOnHover {
    return prefs.getBool('showMenuOnHover') ?? true;
  }

  set showActionLabels(bool status) {
    prefs.setBool('showActionLabels', status);
    notifyListeners();
  }

  bool get showActionLabels {
    return prefs.getBool('showActionLabels') ?? true;
  }

  set pageTurnMode(String mode) {
    prefs.setString('pageTurnMode', mode);
    notifyListeners();
  }

  String get pageTurnMode {
    return prefs.getString('pageTurnMode') ?? 'simple';
  }

  set customPageTurnConfig(List<int> config) {
    prefs.setString('customPageTurnConfig', config.join(','));
    notifyListeners();
  }

  List<int> get customPageTurnConfig {
    String? configStr = prefs.getString('customPageTurnConfig');
    if (configStr == null) {
      // Default: left column = prev (1), middle column = menu (3), right column = next (2)
      // Index mapping: 0=none, 1=next, 2=prev, 3=menu
      // Grid layout: 0,1,2,3,4,5,6,7,8 (row by row)
      return [2, 3, 1, 2, 3, 1, 2, 3, 1]; // prev, menu, next for all rows
    }
    return configStr.split(',').map((e) => int.parse(e)).toList();
  }

  set bookCoverWidth(double width) {
    prefs.setDouble('bookCoverWidth', width);
    notifyListeners();
  }

  double get bookCoverWidth {
    return prefs.getDouble('bookCoverWidth') ?? 120;
  }

  set bookshelfFolderStyle(BookshelfFolderStyle style) {
    prefs.setString('bookshelfFolderStyle', style.code);
    notifyListeners();
  }

  BookshelfFolderStyle get bookshelfFolderStyle {
    return BookshelfFolderStyle.fromCode(
      prefs.getString('bookshelfFolderStyle') ??
          BookshelfFolderStyle.stacked.code,
    );
  }

  set showBookTitleOnDefaultCover(bool status) {
    prefs.setBool('showBookTitleOnDefaultCover', status);
    notifyListeners();
  }

  bool get showBookTitleOnDefaultCover {
    return prefs.getBool('showBookTitleOnDefaultCover') ?? true;
  }

  set showAuthorOnDefaultCover(bool status) {
    prefs.setBool('showAuthorOnDefaultCover', status);
    notifyListeners();
  }

  bool get showAuthorOnDefaultCover {
    return prefs.getBool('showAuthorOnDefaultCover') ?? true;
  }

  set openBookAnimation(bool status) {
    prefs.setBool('openBookAnimation', status);
    notifyListeners();
  }

  bool get openBookAnimation {
    return prefs.getBool('openBookAnimation') ?? true;
  }

  set onlySyncWhenWifi(bool status) {
    prefs.setBool('onlySyncWhenWifi', status);
    notifyListeners();
  }

  bool get onlySyncWhenWifi {
    return prefs.getBool('onlySyncWhenWifi') ?? false;
  }

  set useBookStyles(bool status) {
    prefs.setBool('useBookStyles', status);
    notifyListeners();
  }

  bool get useBookStyles {
    return prefs.getBool('useBookStyles') ?? false;
  }

  set bottomNavigatorShowNote(bool status) {
    prefs.setBool('bottomNavigatorShowNote', status);
    notifyListeners();
  }

  bool get bottomNavigatorShowNote {
    return prefs.getBool('bottomNavigatorShowNote') ?? true;
  }

  set bottomNavigatorShowStatistics(bool status) {
    prefs.setBool('bottomNavigatorShowStatistics', status);
    notifyListeners();
  }

  bool get bottomNavigatorShowStatistics {
    return prefs.getBool('bottomNavigatorShowStatistics') ?? true;
  }

  bool get bottomNavigatorShowAI {
    return prefs.getBool('bottomNavigatorShowAI') ?? true;
  }

  set bottomNavigatorShowAI(bool status) {
    prefs.setBool('bottomNavigatorShowAI', status);
    notifyListeners();
  }

  set syncCompletedToast(bool status) {
    prefs.setBool('syncCompletedToast', status);
    notifyListeners();
  }

  bool get syncCompletedToast {
    return prefs.getBool('syncCompletedToast') ?? true;
  }

  set autoSync(bool status) {
    prefs.setBool('autoSync', status);
    notifyListeners();
  }

  bool get autoSync {
    return prefs.getBool('autoSync') ?? true;
  }

  bool get syncAiSettingsToWebdav {
    return prefs.getBool('syncAiSettingsToWebdav') ?? false;
  }

  set syncAiSettingsToWebdav(bool value) {
    prefs.setBool('syncAiSettingsToWebdav', value);
    notifyListeners();
  }

  String? get syncAiSettingsEncryptionPassword {
    final value = prefs.getString('syncAiSettingsEncryptionPassword');
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveSyncAiSettingsEncryptionPassword(String password) async {
    await prefs.setString('syncAiSettingsEncryptionPassword', password);
    notifyListeners();
  }

  Future<void> clearSyncAiSettingsEncryptionPassword() async {
    await prefs.remove('syncAiSettingsEncryptionPassword');
    notifyListeners();
  }

  set readingInfo(ReadingInfoModel info) {
    prefs.setString('readingInfo', jsonEncode(info.toJson()));
    notifyListeners();
  }

  ReadingInfoModel get readingInfo {
    String? readingInfoJson = prefs.getString('readingInfo');
    if (readingInfoJson == null) {
      return ReadingInfoModel();
    }
    final Map<String, dynamic> json =
        Map<String, dynamic>.from(jsonDecode(readingInfoJson));
    if (json.containsKey('header') || json.containsKey('footer')) {
      return ReadingInfoModel.fromJson(json);
    }

    return ReadingInfoModel(
      header: ReadingInfoSectionModel(
        left: _decodeReadingInfoEnum(
          json['headerLeft'],
          ReadingInfoEnum.chapterTitle,
        ),
        center: _decodeReadingInfoEnum(
          json['headerCenter'],
          ReadingInfoEnum.none,
        ),
        right: _decodeReadingInfoEnum(
          json['headerRight'],
          ReadingInfoEnum.none,
        ),
        verticalMargin: prefs.getDouble('pageHeaderMargin') ??
            MediaQuery.of(navigatorKey.currentContext!).padding.bottom,
        leftMargin: prefs.getDouble('pageHeaderLeftMargin') ?? 20,
        rightMargin: prefs.getDouble('pageHeaderRightMargin') ?? 20,
        fontSize: prefs.getDouble('pageHeaderFontSize') ?? 10,
      ),
      footer: ReadingInfoSectionModel(
        left: _decodeReadingInfoEnum(
          json['footerLeft'],
          ReadingInfoEnum.batteryAndTime,
        ),
        center: _decodeReadingInfoEnum(
          json['footerCenter'],
          ReadingInfoEnum.chapterProgress,
        ),
        right: _decodeReadingInfoEnum(
          json['footerRight'],
          ReadingInfoEnum.bookProgress,
        ),
        verticalMargin: prefs.getDouble('pageFooterMargin') ??
            MediaQuery.of(navigatorKey.currentContext!).padding.bottom,
        leftMargin: prefs.getDouble('pageFooterLeftMargin') ?? 20,
        rightMargin: prefs.getDouble('pageFooterRightMargin') ?? 20,
        fontSize: prefs.getDouble('pageFooterFontSize') ?? 10,
      ),
    );
  }

  set isSystemTts(bool status) {
    prefs.setBool('isSystemTts', status);
    notifyListeners();
  }

  bool get showTextUnderIconButton {
    return prefs.getBool('showTextUnderIconButton') ?? true;
  }

  set showTextUnderIconButton(bool show) {
    prefs.setBool('showTextUnderIconButton', show);
    notifyListeners();
  }

  DateTime? get lastUploadBookDate {
    String? lastUploadBookDateStr = prefs.getString('lastUploadBookDate');
    if (lastUploadBookDateStr == null) return null;
    return DateTime.parse(lastUploadBookDateStr);
  }

  set lastUploadBookDate(DateTime? date) {
    if (date == null) {
      prefs.remove('lastUploadBookDate');
    } else {
      prefs.setString('lastUploadBookDate', date.toIso8601String());
    }
    notifyListeners();
  }

  int get lastServerPort {
    return prefs.getInt('lastServerPort') ?? 0;
  }

  set lastServerPort(int port) {
    prefs.setInt('lastServerPort', port);
    notifyListeners();
  }

  SortFieldEnum get sortField {
    return SortFieldEnum.values.firstWhere(
      (element) => element.name == prefs.getString('sortField'),
      orElse: () => SortFieldEnum.lastReadTime,
    );
  }

  set sortField(SortFieldEnum field) {
    prefs.setString('sortField', field.name);
    notifyListeners();
  }

  SortOrderEnum get sortOrder {
    return SortOrderEnum.values.firstWhere(
      (element) => element.name == prefs.getString('sortOrder'),
      orElse: () => SortOrderEnum.descending,
    );
  }

  set sortOrder(SortOrderEnum order) {
    prefs.setString('sortOrder', order.name);
    notifyListeners();
  }

  bool get notesExportMergeChapters {
    return prefs.getBool('notesExportMergeChapters') ?? true;
  }

  set notesExportMergeChapters(bool value) {
    prefs.setBool('notesExportMergeChapters', value);
    notifyListeners();
  }

  NotesSortField get notesViewSortFieldPref {
    final stored = prefs.getString('notesViewSortField');
    return NotesSortField.values.firstWhere(
      (field) => field.name == stored,
      orElse: () => NotesSortField.cfi,
    );
  }

  set notesViewSortFieldPref(NotesSortField field) {
    prefs.setString('notesViewSortField', field.name);
    notifyListeners();
  }

  SortDirection get notesViewSortDirectionPref {
    final stored = prefs.getString('notesViewSortDirection');
    return SortDirection.values.firstWhere(
      (dir) => dir.name == stored,
      orElse: () => SortDirection.asc,
    );
  }

  set notesViewSortDirectionPref(SortDirection direction) {
    prefs.setString('notesViewSortDirection', direction.name);
    notifyListeners();
  }

  NotesSortField get notesExportSortFieldPref {
    final stored = prefs.getString('notesExportSortField');
    return NotesSortField.values.firstWhere(
      (field) => field.name == stored,
      orElse: () => NotesSortField.cfi,
    );
  }

  set notesExportSortFieldPref(NotesSortField field) {
    prefs.setString('notesExportSortField', field.name);
    notifyListeners();
  }

  SortDirection get notesExportSortDirectionPref {
    final stored = prefs.getString('notesExportSortDirection');
    return SortDirection.values.firstWhere(
      (dir) => dir.name == stored,
      orElse: () => SortDirection.asc,
    );
  }

  set notesExportSortDirectionPref(SortDirection direction) {
    prefs.setString('notesExportSortDirection', direction.name);
    notifyListeners();
  }

  ExcerptShareTemplateEnum get excerptShareTemplate {
    return ExcerptShareTemplateEnum.values.firstWhere(
      (element) => element.name == prefs.getString('excerptShareTemplate'),
      orElse: () => ExcerptShareTemplateEnum.defaultTemplate,
    );
  }

  set excerptShareTemplate(ExcerptShareTemplateEnum template) {
    prefs.setString('excerptShareTemplate', template.name);
    notifyListeners();
  }

  FontModel get excerptShareFont {
    String? fontJson = prefs.getString('excerptShareFont');
    if (fontJson == null) {
      return FontModel(
          label: L10n.of(navigatorKey.currentContext!).systemFont,
          name: 'customFont0',
          path: 'SourceHanSerifSC-Regular.otf');
    }
    return FontModel.fromJson(fontJson);
  }

  set excerptShareFont(FontModel font) {
    prefs.setString('excerptShareFont', font.toJson());
    notifyListeners();
  }

  int get excerptShareColorIndex {
    return prefs.getInt('excerptShareColorIndex') ?? 0;
  }

  set excerptShareColorIndex(int index) {
    prefs.setInt('excerptShareColorIndex', index);
    notifyListeners();
  }

  int get excerptShareBgimgIndex {
    return prefs.getInt('excerptShareBgimgIndex') ?? 1;
  }

  set excerptShareBgimgIndex(int index) {
    prefs.setInt('excerptShareBgimgIndex', index);
    notifyListeners();
  }

  void saveTranslateServiceConfig(
      TranslateService service, Map<String, dynamic> config) {
    prefs.setString(
        'translateServiceConfig_${service.name}', jsonEncode(config));
    notifyListeners();
  }

  Map<String, dynamic>? getTranslateServiceConfig(TranslateService service) {
    String? configJson =
        prefs.getString('translateServiceConfig_${service.name}');
    if (configJson == null) {
      return null;
    }
    return jsonDecode(configJson) as Map<String, dynamic>;
  }

  set iapPurchaseStatus(bool isPurchased) {
    prefs.setBool('iapPurchaseStatus', isPurchased);
    // notifyListeners();
  }

  bool get iapPurchaseStatus {
    return prefs.getBool('iapPurchaseStatus') ?? false;
  }

  set iapLastCheckTime(DateTime checkTime) {
    prefs.setString('iapLastCheckTime', checkTime.toIso8601String());
    // notifyListeners();
  }

  DateTime get iapLastCheckTime {
    String? lastCheckTimeStr = prefs.getString('iapLastCheckTime');
    if (lastCheckTimeStr == null) {
      return DateTime(1970, 1, 1);
    }
    return DateTime.parse(lastCheckTimeStr);
  }

  WritingModeEnum get writingMode {
    return WritingModeEnum.fromCode(prefs.getString('writingMode') ?? 'auto');
  }

  set writingMode(WritingModeEnum mode) {
    prefs.setString('writingMode', mode.code);
    notifyListeners();
  }

  TranslationModeEnum get translationMode {
    return TranslationModeEnum.fromCode(
        prefs.getString('translationMode') ?? 'off');
  }

  set translationMode(TranslationModeEnum mode) {
    prefs.setString('translationMode', mode.code);
    notifyListeners();
  }

  BgimgModel get bgimg {
    String? bgimgJson = prefs.getString('bgimg');
    if (bgimgJson == null) {
      return BgimgModel(
          type: BgimgType.none, path: 'none', alignment: BgimgAlignment.center);
    }
    return BgimgModel.fromJson(jsonDecode(bgimgJson));
  }

  set bgimg(BgimgModel bgimg) {
    prefs.setString('bgimg', jsonEncode(bgimg.toJson()));
    notifyListeners();
  }

  bool get enableJsForEpub {
    return prefs.getBool('enableJsForEpub') ?? false;
  }

  set enableJsForEpub(bool enable) {
    prefs.setBool('enableJsForEpub', enable);
    notifyListeners();
  }

  bool get httpProxyEnabled {
    return prefs.getBool('httpProxyEnabled') ?? false;
  }

  set httpProxyEnabled(bool enabled) {
    prefs.setBool('httpProxyEnabled', enabled);
    notifyListeners();
  }

  String get httpProxyHost {
    return prefs.getString('httpProxyHost') ?? '';
  }

  set httpProxyHost(String host) {
    prefs.setString('httpProxyHost', host);
    notifyListeners();
  }

  int get httpProxyPort {
    return prefs.getInt('httpProxyPort') ?? 7890;
  }

  set httpProxyPort(int port) {
    prefs.setInt('httpProxyPort', port);
    notifyListeners();
  }

  String get httpProxyTestUrl {
    return prefs.getString('httpProxyTestUrl') ?? 'https://google.com';
  }

  set httpProxyTestUrl(String url) {
    prefs.setString('httpProxyTestUrl', url);
    notifyListeners();
  }

  String? get lastAppVersion {
    return prefs.getString('lastAppVersion');
  }

  set lastAppVersion(String? version) {
    if (version != null) {
      prefs.setString('lastAppVersion', version);
    } else {
      prefs.remove('lastAppVersion');
    }
    notifyListeners();
  }

  set customCSSEnabled(bool enabled) {
    prefs.setBool('customCSSEnabled', enabled);
    notifyListeners();
  }

  bool get customCSSEnabled {
    return prefs.getBool('customCSSEnabled') ?? false;
  }

  set customCSS(String css) {
    prefs.setString('customCSS', css);
    notifyListeners();
  }

  String get customCSS {
    return prefs.getString('customCSS') ?? '';
  }

  Map<String, TranslationModeEnum> get bookTranslationModes {
    String? modesJson = prefs.getString('bookTranslationModes');
    if (modesJson == null) return {};

    Map<String, dynamic> decoded = jsonDecode(modesJson);
    return decoded.map((key, value) =>
        MapEntry(key, TranslationModeEnum.fromCode(value as String)));
  }

  set bookTranslationModes(Map<String, TranslationModeEnum> modes) {
    Map<String, String> encoded =
        modes.map((key, value) => MapEntry(key, value.code));
    prefs.setString('bookTranslationModes', jsonEncode(encoded));
    notifyListeners();
  }

  TranslationModeEnum getBookTranslationMode(int bookId) {
    return bookTranslationModes[bookId.toString()] ?? TranslationModeEnum.off;
  }

  void setBookTranslationMode(int bookId, TranslationModeEnum mode) {
    Map<String, TranslationModeEnum> modes = bookTranslationModes;
    String bookIdStr = bookId.toString();

    if (mode == TranslationModeEnum.off) {
      modes.remove(bookIdStr); // 默认状态不保存，节省空间
    } else {
      modes[bookIdStr] = mode;
    }
    bookTranslationModes = modes;
  }

  bool get allowMixWithOtherAudio {
    return prefs.getBool('allowMixWithOtherAudio') ?? false;
  }

  set allowMixWithOtherAudio(bool allow) {
    prefs.setBool('allowMixWithOtherAudio', allow);
    notifyListeners();
  }

  TextAlignmentEnum get textAlignment {
    return TextAlignmentEnum.fromCode(
        prefs.getString('textAlignment') ?? 'auto');
  }

  set textAlignment(TextAlignmentEnum alignment) {
    prefs.setString('textAlignment', alignment.code);
    notifyListeners();
  }

  BgimgFitEnum get bgimgFit {
    return BgimgFitEnum.fromCode(prefs.getString('bgimgFit') ?? 'cover');
  }

  set bgimgFit(BgimgFitEnum fit) {
    prefs.setString('bgimgFit', fit.code);
    notifyListeners();
  }

  AiPanelPositionEnum get aiPanelPosition {
    return AiPanelPositionEnum.fromCode(
        prefs.getString('aiPanelPosition') ?? 'right');
  }

  set aiPanelPosition(AiPanelPositionEnum position) {
    prefs.setString('aiPanelPosition', position.code);
    notifyListeners();
  }

  CodeHighlightThemeEnum get codeHighlightTheme {
    return CodeHighlightThemeEnum.fromCode(
        prefs.getString('codeHighlightTheme') ?? 'default');
  }

  set codeHighlightTheme(CodeHighlightThemeEnum theme) {
    prefs.setString('codeHighlightTheme', theme.code);
    notifyListeners();
  }

  // AI chat display mode configuration
  AiChatDisplayMode get aiChatDisplayMode {
    return AiChatDisplayMode.fromCode(
        prefs.getString('aiChatDisplayMode') ?? 'adaptive');
  }

  set aiChatDisplayMode(AiChatDisplayMode mode) {
    prefs.setString('aiChatDisplayMode', mode.code);
    notifyListeners();
  }

  // AI panel width (for split mode)
  double get aiPanelWidth {
    return prefs.getDouble('aiPanelWidth') ?? 300;
  }

  set aiPanelWidth(double width) {
    prefs.setDouble('aiPanelWidth', width);
    notifyListeners();
  }

  // AI panel height (for split mode)
  double get aiPanelHeight {
    return prefs.getDouble('aiPanelHeight') ?? 300;
  }

  set aiPanelHeight(double height) {
    prefs.setDouble('aiPanelHeight', height);
    notifyListeners();
  }
}

ReadingInfoEnum _decodeReadingInfoEnum(
  Object? value,
  ReadingInfoEnum fallback,
) {
  if (value is! String) return fallback;
  for (final item in ReadingInfoEnum.values) {
    if (item.name == value) {
      return item;
    }
  }
  return fallback;
}
