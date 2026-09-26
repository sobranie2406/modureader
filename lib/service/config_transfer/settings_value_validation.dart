import 'dart:convert';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/models/chapter_split_rule.dart';
import 'package:anx_reader/models/reading_info.dart';
import 'package:anx_reader/models/reading_rules.dart';
import 'package:anx_reader/models/user_prompt.dart';
import 'package:anx_reader/service/config_transfer/custom_css_transfer.dart';
import 'package:anx_reader/service/config_transfer/tts_config_transfer.dart';

/// Parse with the same models that consume these preferences, before writing
/// anything. Free-form prompts/CSS are not inferred to be JSON from their text.
void validateSettingsValue(String key, dynamic value) {
  dynamic decoded() => jsonDecode(value as String);
  Map<String, dynamic> object() {
    final data = decoded();
    if (data is! Map<String, dynamic>)
      throw const FormatException('Expected object');
    return data;
  }

  List<dynamic> array() {
    final data = decoded();
    if (data is! List) throw const FormatException('Expected array');
    return data;
  }

  const choices = {
    'syncProtocol': ['webdav'],
    'pageTurnStyle': ['noAnimation', 'slide', 'scroll'],
    'pageTurnMode': ['simple', 'custom'],
    'themeMode': ['system', 'light', 'dark'],
    'vectorModelMode': ['builtin', 'remote'],
    'vectorModelDownloadSource': ['huggingFace', 'gitee'],
  };
  if (choices.containsKey(key) && !choices[key]!.contains(value)) {
    throw const FormatException('Unknown setting choice');
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
  if ((key == 'readAnySkillPrompts' || key.startsWith('aiConfig_')) &&
      object().values.any((v) => v is! String)) {
    throw const FormatException('Invalid text configuration');
  }
  if (key.startsWith('onlineTtsConfig_')) {
    final data = TtsConfigTransfer.defaults();
    final id = key.substring('onlineTtsConfig_'.length);
    if (TtsConfigTransfer.services.contains(id)) {
      data['providers'][id]['config'] = object();
      TtsConfigTransfer.validate(data);
    } else {
      object(); // Preserve old provider configuration without selecting it.
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
  if (key == 'vectorModelConfig' || key.startsWith('translateServiceConfig_'))
    object();
  if (key == 'remoteLibraryViewOptions') {
    final data = object();
    if (!['name', 'createdAt', 'modifiedAt', 'size'].contains(data['sort']) ||
        data['ascending'] is! bool ||
        !['all', 'books', 'epub', 'pdf', 'txt', 'mobi', 'azw3', 'fb2']
            .contains(data['filter'])) {
      throw const FormatException('Invalid library view');
    }
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
        data['blur'] > 100 ||
        data['opacity'] is! num ||
        data['opacity'] < 0 ||
        data['opacity'] > 1) {
      throw const FormatException('Invalid portable background');
    }
  }
}
