import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

const _readAnyFreeTranslateUrl =
    'https://translate.googleapis.com/translate_a/single';
const _maxChunkLength = 4500;

/// ReadAny-compatible, key-free translation provider.
///
/// The persisted service ID remains `microsoftFree` for compatibility with
/// existing settings, but the actual transport is Google's public translation
/// endpoint. The user-facing label names the transport truthfully.
class MicrosoftFreeTranslateProvider extends TranslateServiceProvider {
  @override
  TranslateService get service => TranslateService.microsoftFree;

  @override
  String getLabel(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh'
          ? 'Google 翻译（免费）'
          : 'Google Translate (Free)';

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
    if (text.trim().isEmpty) {
      yield '';
      return;
    }

    yield '...';

    try {
      final chunks = _splitText(text);
      final translated = <String>[];
      for (final chunk in chunks) {
        translated.add(await _translateChunk(chunk, from, to));
      }
      yield translated.join();
    } catch (error) {
      AnxLog.severe('Free translation failed: $error');
      yield* Stream.error(Exception(error));
    }
  }

  Future<String> _translateChunk(
    String text,
    LangListEnum from,
    LangListEnum to,
  ) async {
    final response = await Dio().get(
      _readAnyFreeTranslateUrl,
      queryParameters: {
        'client': 'gtx',
        'sl': from == LangListEnum.auto ? 'auto' : from.code.toLowerCase(),
        'tl': to.code.toLowerCase(),
        'dt': 't',
        'q': text,
      },
      options: Options(
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode != 200 || response.data is! List) {
      throw Exception('Free translation HTTP ${response.statusCode}');
    }

    final data = response.data as List<dynamic>;
    if (data.isEmpty || data.first is! List) {
      throw Exception('Free translation returned unexpected data');
    }

    final buffer = StringBuffer();
    for (final segment in data.first as List<dynamic>) {
      if (segment is List && segment.isNotEmpty && segment.first is String) {
        buffer.write(segment.first as String);
      }
    }

    final result = buffer.toString();
    if (result.trim().isEmpty) {
      throw Exception('Free translation returned an empty result');
    }
    return result;
  }

  List<String> _splitText(String text) {
    if (text.length <= _maxChunkLength) return [text];

    final chunks = <String>[];
    var offset = 0;
    while (offset < text.length) {
      var end = (offset + _maxChunkLength).clamp(0, text.length);
      if (end < text.length) {
        final candidate = text.substring(offset, end);
        final boundary = candidate.lastIndexOf(RegExp(r'[\n。！？.!?]'));
        if (boundary > _maxChunkLength ~/ 2) {
          end = offset + boundary + 1;
        }
      }
      chunks.add(text.substring(offset, end));
      offset = end;
    }
    return chunks;
  }
}
