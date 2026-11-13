import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/service/translate/translation_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class OfficialApiTranslateProvider extends TranslateServiceProvider {
  OfficialApiTranslateProvider(this.service, {this.client});
  @override
  final TranslateService service;
  final Dio? client;
  bool get isBaidu => service == TranslateService.baiduApi;

  @override
  String getLabel(BuildContext context) => isBaidu
      ? ModuStrings.text(context, '百度翻译 API', 'Baidu Translate API')
      : 'Microsoft Translator';

  @override
  String mapLanguageCode(LangListEnum lang) {
    if (lang == LangListEnum.auto) return 'auto';
    if (!isBaidu) {
      return switch (lang) {
        LangListEnum.simplifiedChinese => 'zh-Hans',
        LangListEnum.traditionalChinese => 'zh-Hant',
        _ => lang.code,
      };
    }
    const codes = {
      'zh-CN': 'zh',
      'zh-TW': 'cht',
      'en': 'en',
      'ja': 'jp',
      'ko': 'kor',
      'fr': 'fra',
      'es': 'spa',
      'th': 'th',
      'ar': 'ara',
      'ru': 'ru',
      'pt': 'pt',
      'de': 'de',
      'it': 'it',
      'el': 'el',
      'nl': 'nl',
      'pl': 'pl',
      'bg': 'bul',
      'fi': 'fin',
      'cs': 'cs',
      'da': 'dan',
      'sv': 'swe',
      'hu': 'hu',
      'ro': 'rom',
      'sl': 'slo',
      'vi': 'vie',
      'id': 'id',
      'ms': 'may',
      'hi': 'hi',
      'tr': 'tr',
      'uk': 'ukr',
      'ta': 'tam',
      'te': 'tel',
      'nb': 'nob',
      'sk': 'sk',
      'hr': 'hrv',
      'ca': 'cat',
      'mt': 'mlt',
    };
    final code = codes[lang.code];
    if (code == null) {
      throw StateError('Baidu does not support ${lang.nativeName}');
    }
    return code;
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().classicalTranslationConfig;
    final legacy =
        Prefs().getTranslateServiceConfig(TranslateService.microsoftApi);
    return isBaidu
        ? {
            'baidu_appid': config['baidu_appid'] ?? '',
            'baidu_key': config['baidu_key'] ?? '',
          }
        : {
            'microsoft_key':
                config['microsoft_key'] ?? legacy?['api_key'] ?? '',
            'microsoft_region':
                config['microsoft_region'] ?? legacy?['region'] ?? '',
          };
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().classicalTranslationConfig = {
      ...Prefs().classicalTranslationConfig,
      for (final entry in config.entries) entry.key: entry.value.toString(),
    };
  }

  @override
  Widget translate(String text, LangListEnum from, LangListEnum to,
          {String? contextText}) =>
      convertStreamToWidget(translateStream(text, from, to));

  @override
  Stream<String> translateStream(
      String text, LangListEnum from, LangListEnum to,
      {String? contextText,
      bool isFullText = false,
      Future<void>? whenCancelled}) async* {
    if (to == LangListEnum.auto) {
      throw StateError('Select a target language');
    }
    yield* TranslationApiClient(
      isBaidu ? TranslationApiEngine.baidu : TranslationApiEngine.microsoft,
      getConfig().map((key, value) => MapEntry(key, value.toString())),
      client: client,
    ).translate(text,
        from: mapLanguageCode(from),
        to: mapLanguageCode(to),
        whenCancelled: whenCancelled);
  }
}
