import 'dart:convert';
import 'package:anx_reader/models/text_color.dart';
import 'package:anx_reader/models/translation_text_style.dart';
import 'package:anx_reader/models/tts_buffer_settings.dart';
import 'package:anx_reader/service/sync/s3_config.dart';
import 'package:anx_reader/service/ai/reading_skill_layout.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/models/plugin_manifest.dart';
import 'package:anx_reader/models/plugin_state.dart';
import 'package:anx_reader/models/reading_info.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/service/config_transfer/custom_css_transfer.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:anx_reader/service/plugins/plugin_config.dart';
import 'package:anx_reader/service/plugins/plugin_host.dart';

/// Parse with the same models that consume these preferences, before writing
/// anything. Free-form prompts/CSS are not inferred to be JSON from their text.
void validateSettingsValue(String key, dynamic value,
    {PluginManifest? Function(String pluginId)? pluginManifest}) {
  dynamic decoded() => jsonDecode(value as String);
  Map<String, dynamic> object() {
    final data = decoded();
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Expected object');
    }
    return data;
  }

  List<dynamic> array() {
    final data = decoded();
    if (data is! List) throw const FormatException('Expected array');
    return data;
  }

  const choices = {
    'classicalTranslationEngine': ['ai', 'baidu', 'microsoft'],
    'classicalTranslationDirection': ['toModern', 'toClassical'],
    'appLayoutMode': ['auto', 'wide', 'narrow'],
    'syncProtocol': ['webdav', 's3'],
    'pageTurnStyle': ['noAnimation', 'slide', 'scroll'],
    'pageTurnMode': ['simple', 'custom'],
    // Older versions saved the system theme as "auto".
    'themeMode': ['system', 'light', 'dark', 'auto'],
    'vectorModelMode': ['builtin', 'remote'],
    'vectorModelDownloadSource': ['huggingFace', 'gitee'],
    'ocrModelDownloadSource': ['upstream', 'gitee'],
    'ocrModelId': [
      'ppocr-v6-small-1',
      'ppocr-v6-medium-1',
      'ppocr-v4-mobile-1',
      'ppocr-v5-mobile-1',
      'ppocr-v3-mobile-1',
      'ppocr-v3-english-mobile-1'
    ],
  };
  if (choices.containsKey(key) && !choices[key]!.contains(value)) {
    throw const FormatException('Unknown setting choice');
  }
  if (key == 'readerToolbar') {
    final config = object();
    for (final field in ['order', 'hidden']) {
      final items = config[field];
      if (items != null &&
          (items is! List || items.any((item) => item is! String))) {
        throw const FormatException('Invalid reader toolbar actions');
      }
    }
  }
  if (key == 'classicalTranslationTextStyle' ||
      key == 'languageTranslationTextStyle') {
    final config = object();
    final size = config['size'];
    if ((config.containsKey('color') && !validTextColor(config['color'])) ||
        !TranslationTextStyle.validFont(config['font']) ||
        size is! num ||
        !size.isFinite ||
        (size != 0 && (size < 8 || size > 48)) ||
        config['bold'] is! bool ||
        config['italic'] is! bool) {
      throw const FormatException('Invalid translation text style');
    }
  }
  if (key == 'eInkRefreshPages' &&
      (value is! int || value < 0 || value > 100)) {
    throw const FormatException('Invalid E-Ink refresh interval');
  }
  if (key == 'ocrPrecachePages' && (value is! int || value < 1 || value > 5)) {
    throw const FormatException('Invalid OCR prefetch window');
  }
  if (key == 'dailyCheckInMinutes' &&
      (value is! int || value < 0 || value > 120)) {
    throw const FormatException('Invalid daily check-in goal');
  }
  if (key == 'scrollPagePercent' && (value < 80 || value > 100)) {
    throw const FormatException('Invalid scroll page percentage');
  }
  if ((key == 'selectionSearchZoomPercent' ||
          key == 'webTranslationZoomPercent') &&
      (value < 50 || value > 200)) {
    throw const FormatException('Invalid search zoom percentage');
  }
  if (key == 'customPageTurnConfig') {
    final cells = (value as String).split(',').map(int.tryParse).toList();
    if (cells.length != 9 || cells.any((n) => n == null || n < 0 || n > 3)) {
      throw const FormatException('Invalid page turn grid');
    }
  }
  if (key == 'excerptShareBgimgIndex' && (value < 0 || value > 7)) {
    throw const FormatException('Invalid excerpt background');
  }
  if (key == 'httpProxyPort' && (value < 1 || value > 65535)) {
    throw const FormatException('Invalid proxy port');
  }
  if (key == 'readingRules') ReadingRules.fromJson(value);
  if (key == 'ttsBufferSettings') TtsBufferSettings.fromMap(object());
  if (key == 'readingInfo') {
    final data = object();
    if (data.containsKey('header') || data.containsKey('footer')) {
      ReadingInfoModel.fromJson(data);
    } else if (data.values.any((v) => v is! String)) {
      throw const FormatException('Invalid legacy reading info');
    }
  }
  if (key == 'aiProviders') {
    final ids = <String>{};
    for (final entry in array()) {
      final provider =
          AiProvider.fromJson(Map<String, dynamic>.from(entry as Map));
      if (provider.id.isEmpty || !ids.add(provider.id)) {
        throw const FormatException('Duplicate provider');
      }
    }
  }
  if (key == 'userPrompts') {
    for (final entry in array()) {
      UserPrompt.fromJson(Map<String, dynamic>.from(entry as Map));
    }
  }
  if (key == 'chapterSplitCustomRules') {
    for (final entry in array()) {
      ChapterSplitRule.fromMap(Map<String, dynamic>.from(entry as Map))
          .buildRegExp();
    }
  }
  if (key == 'customCssProfiles') {
    final profiles = array();
    if (profiles.isNotEmpty) {
      CustomCssTransfer.decode(
          jsonEncode({
            'kind': CustomCssTransfer.kind,
            'version': 1,
            'profiles': profiles,
          }),
          fileName: 'settings.json');
    }
  }
  if (key == 'customCssDefaultIndices') {
    if (array().any((n) => n is! int || n < 0 || n >= 32)) {
      throw const FormatException('Invalid CSS selection');
    }
  }
  if (key == 'customCssDefaultIndex' && (value < 0 || value >= 32)) {
    throw const FormatException('Invalid CSS index');
  }
  if (key == 'readAnySkillStates' && object().values.any((v) => v is! bool)) {
    throw const FormatException('Invalid skill state');
  }
  if (key == 'readAnySkillOrder') {
    final order = List<String>.from(value as List);
    if (order.length > 512 ||
        order.toSet().length != order.length ||
        order.any((id) => !isReadingSkillOrderId(id))) {
      throw const FormatException('Invalid reading skill order');
    }
  }
  if ((key == 'readAnySkillPrompts' || key.startsWith('aiConfig_')) &&
      object().values.any((v) => v is! String)) {
    throw const FormatException('Invalid text configuration');
  }
  if (key.startsWith('onlineTtsConfig_')) {
    final data = TtsConfigTransfer.defaults();
    final id = key.substring('onlineTtsConfig_'.length);
    // A provider this build knows is validated strictly; an unknown one keeps
    // its object shape so reinstalling or upgrading cannot silently drop it.
    if (TtsConfigTransfer.isKnownProvider(id)) {
      data['providers'][id]['config'] = object();
      TtsConfigTransfer.validate(data);
    } else {
      object();
    }
  }
  if (key == 'webdavInfo') {
    final data = object();
    for (final field in ['url', 'username', 'password']) {
      if (data.containsKey(field) && data[field] is! String) {
        throw const FormatException('Invalid WebDAV setting');
      }
    }
  }
  if (key == 's3Info') S3Config(object());
  if (key == 'vectorModelConfig' || key.startsWith('translateServiceConfig_')) {
    object();
  }
  if (key == 'remoteLibraryViewOptions') {
    final data = object();
    if (!['name', 'createdAt', 'modifiedAt', 'size'].contains(data['sort']) ||
        data['ascending'] is! bool ||
        ![
          'all',
          'books',
          'epub',
          'pdf',
          'txt',
          'mobi',
          'azw3',
          'fb2',
          'md',
          'umd'
        ].contains(data['filter'])) {
      throw const FormatException('Invalid library view');
    }
  }
  if (key == 'pluginState') {
    PluginState.parseStrict(decoded());
  }
  if (key.startsWith(PluginConfig.prefix)) {
    final id = key.substring(PluginConfig.prefix.length);
    final manifest = (pluginManifest ?? PluginHost.instance.manifestFor)(id);
    PluginConfig.validate(id, value, manifest: manifest);
  }
  if (key == 'bgimg') {
    final data = object();
    if (data.keys.any((k) =>
            !['alignment', 'selectedMode', 'blur', 'opacity'].contains(k)) ||
        !['center', 'top', 'bottom', 'left', 'right']
            .contains(data['alignment']) ||
        ![null, 'day', 'night'].contains(data['selectedMode']) ||
        data['blur'] is! num ||
        data['blur'] < 0 ||
        data['blur'] > 20 ||
        data['opacity'] is! num ||
        data['opacity'] < 0 ||
        data['opacity'] > 1) {
      throw const FormatException('Invalid portable background');
    }
  }
}
