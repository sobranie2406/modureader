import 'dart:io';

import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/utils/log/common.dart';
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
  MicrosoftFreeTranslateProvider({Dio Function()? dioFactory})
      : _dioFactory = dioFactory ?? _defaultDio;

  /// A fresh client per call so a cancelled lookup cannot leave a connection
  /// pool behind, but with a **connect** deadline: without one a blocked host
  /// falls through to the OS timeout (21 s here), then [_translateChunk]'s
  /// caller retried it twice more.
  final Dio Function() _dioFactory;

  static Dio _defaultDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
      ));

  @override
  TranslateService get service => TranslateService.microsoftFree;

  @override
  String getLabel(BuildContext context) =>
      ModuStrings.text(context, 'Google 翻译（免费）', 'Google Translate (Free)');

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
    Future<void>? whenCancelled,
  }) async* {
    final cancelToken = CancelToken();
    whenCancelled?.then((_) => cancelToken.cancel());
    if (text.trim().isEmpty) {
      yield '';
      return;
    }

    yield '...';

    try {
      final chunks = _splitText(text);
      final translated = <String>[];
      for (final chunk in chunks) {
        translated.add(await _translateChunk(chunk, from, to, cancelToken));
      }
      yield translated.join();
    } catch (error) {
      if (cancelToken.isCancelled) return;
      // A blocked or unreachable endpoint is a normal condition (offline, no
      // route, a network that filters Google), not a crash: one warning line,
      // no stack trace, and a failure the caller knows not to retry.
      final unavailable = error is TranslateUnavailableException;
      AnxLog.warning(
          'Free translation ${unavailable ? 'unavailable' : 'failed'}: '
          '${_describe(error)}');
      yield* Stream.error(unavailable ? error : Exception(_describe(error)));
    }
  }

  Future<String> _translateChunk(
    String text,
    LangListEnum from,
    LangListEnum to,
    CancelToken cancelToken,
  ) async {
    final Response<dynamic> response;
    try {
      response = await _dioFactory().get<dynamic>(
        _readAnyFreeTranslateUrl,
        cancelToken: cancelToken,
        queryParameters: {
          'client': 'gtx',
          'sl': from == LangListEnum.auto ? 'auto' : from.code.toLowerCase(),
          'tl': to.code.toLowerCase(),
          'dt': 't',
          'q': text,
        },
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
    } on DioException catch (error) {
      // Nothing about a dropped connection or a rate limit changes within the
      // retry window, so classify it once instead of trying three times.
      if (error.type == DioExceptionType.badResponse) rethrow;
      throw TranslateUnavailableException(_describe(error));
    }

    if (response.statusCode != 200 || response.data is! List) {
      throw TranslateUnavailableException(
          'HTTP ${response.statusCode} from the free endpoint');
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

  /// One log-friendly line instead of Dio's multi-line exception dump.
  static String _describe(Object error) {
    if (error is TranslateUnavailableException) return _describe(error.cause);
    if (error is DioException) {
      final inner = error.error;
      if (inner is SocketException) {
        return 'cannot reach ${Uri.parse(_readAnyFreeTranslateUrl).host} '
            '(socket: ${inner.osError?.message ?? inner.message})';
      }
      return '${error.type.name}: ${error.message ?? error}';
    }
    return '$error';
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
