import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/config/config_item.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

const _deeplApiBaseUrl = 'https://api-free.deepl.com/v2';

String normalizeDeepLBaseUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return _deeplApiBaseUrl;
  return trimmed.replaceFirst(RegExp(r'/+$'), '').replaceFirst(
        RegExp(r'/translate$', caseSensitive: false),
        '',
      );
}

class DeepLTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.deepl;

  /// DeepL uses uppercase language codes (e.g., ZH, EN, JA).
  @override
  String mapLanguageCode(LangListEnum lang) {
    const Map<String, String> codeMap = {
      'zh-CN': 'ZH',
      'zh-TW': 'ZH',
      'en': 'EN',
      'ja': 'JA',
      'de': 'DE',
      'fr': 'FR',
      'es': 'ES',
      'it': 'IT',
      'nl': 'NL',
      'pl': 'PL',
      'pt': 'PT',
      'ru': 'RU',
    };
    return codeMap[lang.code] ?? lang.code.toUpperCase();
  }

  @override
  String getLabel(BuildContext context) => 'DeepL';

  @override
  Widget translate(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) {
    return convertStreamToWidget(
      translateStream(text, from, to, contextText: contextText),
    );
  }

  @override
  Stream<String> translateStream(
    String text,
    LangListEnum from,
    LangListEnum to, {
    String? contextText,
    bool isFullText = false,
  }) async* {
    try {
      final config = getConfig();

      yield "...";
      yield await _translateWithReadAnyConfig(text, from, to, config);
    } catch (e) {
      AnxLog.severe(
          "Deepl ${L10n.of(navigatorKey.currentContext!).translateError}: $e");
      yield* Stream.error(Exception(e));
    }
  }

  @override
  List<ConfigItem> getConfigItems(BuildContext context) {
    return [
      ConfigItem(
        key: 'tip',
        label: L10n.of(context).translateTip,
        type: ConfigItemType.tip,
        defaultValue: L10n.of(context).translateDeepLHelpText,
      ),
      ConfigItem(
        key: 'api_url',
        label: Localizations.localeOf(context).languageCode == 'zh'
            ? 'DeepL 请求地址'
            : 'DeepL request URL',
        type: ConfigItemType.text,
        defaultValue: _deeplApiBaseUrl,
      ),
      ConfigItem(
        key: 'api_key',
        label: 'DeepL API Key',
        description: L10n.of(navigatorKey.currentContext!).deeplKeyTip,
        type: ConfigItemType.password,
        defaultValue: '',
      ),
    ];
  }

  @override
  Map<String, dynamic> getConfig() {
    final config = Prefs().getTranslateServiceConfig(service);
    return config ?? {'api_key': '', 'api_url': _deeplApiBaseUrl};
  }

  @override
  void saveConfig(Map<String, dynamic> config) {
    Prefs().saveTranslateServiceConfig(service, config);
  }

  Future<String> _translateWithReadAnyConfig(
    String text,
    LangListEnum from,
    LangListEnum to,
    Map<String, dynamic> config,
  ) async {
    final apiKey = config['api_key']?.toString().trim() ?? '';
    final rawUrl = config['api_url']?.toString().trim() ?? '';
    final normalized = normalizeDeepLBaseUrl(rawUrl);
    final baseUri = Uri.tryParse(normalized);
    if (baseUri == null || !baseUri.hasScheme || baseUri.host.isEmpty) {
      throw Exception('Invalid DeepL request URL');
    }

    final isOfficial = baseUri.host == 'api.deepl.com' ||
        baseUri.host == 'api-free.deepl.com' ||
        baseUri.host.endsWith('.deepl.com') ||
        baseUri.pathSegments.lastOrNull == 'v2';

    if (isOfficial) {
      if (apiKey.isEmpty) throw Exception('Invalid DeepL API key');
      return _translateOfficial(text, from, to, apiKey, normalized);
    }

    final exactUrl = rawUrl.replaceFirst(RegExp(r'/+$'), '');
    final hasExactTranslateUrl = exactUrl.toLowerCase().endsWith('/translate');
    final pathSegments = [...baseUri.pathSegments]
      ..removeWhere((segment) => segment.isEmpty);
    var resolvedApiKey = apiKey;
    if (pathSegments.isNotEmpty &&
        (resolvedApiKey.isEmpty || pathSegments.last == resolvedApiKey)) {
      resolvedApiKey =
          resolvedApiKey.isEmpty ? pathSegments.last : resolvedApiKey;
      pathSegments.removeLast();
    }
    final requestBase = baseUri.replace(
      pathSegments: pathSegments,
      queryParameters: const {},
      fragment: '',
    );
    final endpoint = hasExactTranslateUrl
        ? exactUrl
        : '${requestBase.toString().replaceFirst(RegExp(r'/+$'), '')}/translate';
    if (resolvedApiKey.isEmpty && !hasExactTranslateUrl) {
      throw Exception('DeepLX API key is required');
    }
    return _translateDeepLX(
      text,
      from,
      to,
      resolvedApiKey,
      endpoint,
    );
  }

  Future<String> _translateOfficial(
    String text,
    LangListEnum from,
    LangListEnum to,
    String apiKey,
    String baseUrl,
  ) async {
    final params = <String, dynamic>{
      'text': text,
      'target_lang': mapLanguageCode(to),
      if (from != LangListEnum.auto) 'source_lang': mapLanguageCode(from),
    };
    final response = await Dio().post(
      '$baseUrl/translate',
      data: params,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {'Authorization': 'DeepL-Auth-Key $apiKey'},
        validateStatus: (status) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('DeepL API error (${response.statusCode})');
    }
    final translations =
        response.data is Map ? (response.data as Map)['translations'] : null;
    if (translations is List &&
        translations.isNotEmpty &&
        translations.first is Map &&
        (translations.first as Map)['text'] is String) {
      return (translations.first as Map)['text'] as String;
    }
    throw Exception('DeepL returned unexpected data');
  }

  Future<String> _translateDeepLX(
    String text,
    LangListEnum from,
    LangListEnum to,
    String apiKey,
    String endpoint,
  ) async {
    var uri = Uri.parse(endpoint);
    if (apiKey.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {...uri.queryParameters, 'token': apiKey},
      );
    }

    final response = await Dio().post(
      uri.toString(),
      data: {
        'text': text,
        'source_lang':
            from == LangListEnum.auto ? 'auto' : _mapDeepLXLanguage(from),
        'target_lang': _mapDeepLXLanguage(to),
      },
      options: Options(
        headers: {
          if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        validateStatus: (status) => true,
      ),
    );
    if (response.statusCode != 200) {
      throw Exception('DeepLX API error (${response.statusCode})');
    }

    final data = response.data;
    if (data is Map) {
      final candidate = data['data'] ?? data['translation'];
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate;
      }
    }
    throw Exception('DeepLX returned unexpected data');
  }

  String _mapDeepLXLanguage(LangListEnum lang) {
    final normalized = lang.code.toUpperCase().replaceAll('-', '_');
    if (normalized == 'ZH_CN' || normalized == 'ZH_TW') return 'ZH';
    return normalized;
  }
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
