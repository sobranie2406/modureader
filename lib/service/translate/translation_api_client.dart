import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/translate/translation_usage.dart';
import 'package:modu_reader/utils/log/common.dart';

enum TranslationApiEngine { baidu, microsoft }

/// Shared official API transport for language and classical translation.
class TranslationApiClient {
  TranslationApiClient(this.engine, this.config, {Dio? client})
      : _client = client;
  final TranslationApiEngine engine;
  final Map<String, String> config;
  final Dio? _client;
  static Future<void> _baiduQueue = Future.value();
  static DateTime? _lastBaiduRequest;

  Stream<String> translate(String text,
      {required String from,
      required String to,
      Future<void>? whenCancelled}) async* {
    final key = config[engine == TranslationApiEngine.baidu
                ? 'baidu_key'
                : 'microsoft_key']
            ?.trim() ??
        '';
    final appId = config['baidu_appid']?.trim() ?? '';
    if (key.isEmpty ||
        (engine == TranslationApiEngine.baidu && appId.isEmpty)) {
      throw StateError('请在翻译设置中配置密钥 / Configure translation credentials first');
    }
    final client = _client ??
        Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 60),
            sendTimeout: const Duration(seconds: 30)));
    final token = CancelToken();
    whenCancelled?.then((_) => token.cancel());
    final translated = <String>[];
    try {
      // Baidu standard accounts accept short requests. Do not drop long
      // paragraphs; split by code points without breaking surrogate pairs.
      final runes = text.runes.toList();
      for (var start = 0; start < runes.length; start += 900) {
        if (token.isCancelled) return;
        final part = String.fromCharCodes(
            runes.sublist(start, min(start + 900, runes.length)));
        Response<dynamic> response;
        if (engine == TranslationApiEngine.baidu) {
          final previous = _baiduQueue;
          final released = Completer<void>();
          _baiduQueue = released.future;
          try {
            await Future.any([previous, token.whenCancel]);
            if (token.isCancelled) return;
            final elapsed = _lastBaiduRequest == null
                ? 1100
                : DateTime.now().difference(_lastBaiduRequest!).inMilliseconds;
            if (elapsed < 1100) {
              await Future.any([
                Future<void>.delayed(Duration(milliseconds: 1100 - elapsed)),
                token.whenCancel
              ]);
            }
            if (token.isCancelled) return;
            _lastBaiduRequest = DateTime.now();
            final salt =
                '${DateTime.now().microsecondsSinceEpoch}${Random.secure().nextInt(1 << 30)}';
            response = await client.post(
                'https://fanyi-api.baidu.com/api/trans/vip/translate',
                cancelToken: token,
                data: {
                  'q': part,
                  'from': from,
                  'to': to,
                  'appid': appId,
                  'salt': salt,
                  'sign': md5
                      .convert(utf8.encode('$appId$part$salt$key'))
                      .toString()
                },
                options:
                    Options(contentType: Headers.formUrlEncodedContentType));
          } finally {
            // Keep queued requests ordered even when this waiter is cancelled.
            unawaited(previous.whenComplete(() {
              if (!released.isCompleted) released.complete();
            }));
          }
          final data = response.data;
          final rows = data is Map ? data['trans_result'] : null;
          if (rows is! List ||
              rows.isEmpty ||
              rows.any((row) => row is! Map || row['dst'] is! String)) {
            final code = data is Map ? data['error_code']?.toString() : null;
            throw StateError(
                'Baidu translation failed${code != null && RegExp(r"^\d+$").hasMatch(code) ? " ($code)" : ""}');
          }
          translated.add(rows.map((row) => row['dst'] as String).join('\n'));
        } else {
          final region = config['microsoft_region']?.trim() ?? '';
          response = await client.post(
              'https://api.cognitive.microsofttranslator.com/translate',
              queryParameters: {
                'api-version': '3.0',
                if (from != 'auto') 'from': from,
                'to': to
              },
              data: [
                {'Text': part}
              ],
              cancelToken: token,
              options: Options(headers: {
                'Ocp-Apim-Subscription-Key': key,
                if (region.isNotEmpty && region != 'global')
                  'Ocp-Apim-Subscription-Region': region
              }));
          final data = response.data;
          final rows = data is List && data.isNotEmpty && data.first is Map
              ? data.first['translations']
              : null;
          if (rows is! List ||
              rows.isEmpty ||
              rows.first is! Map ||
              rows.first['text'] is! String) {
            throw StateError('Microsoft Translator returned no translation');
          }
          translated.add(rows.first['text'] as String);
        }
        // Count each successful remote chunk, including a request completed
        // just before cancellation. Cached paragraphs never reach this path.
        try {
          await TranslationUsage(Prefs().prefs).record(
              TranslationUsage.account(engine.name, config), part.runes.length);
        } catch (_) {
          // A usage-storage failure must not discard a valid translation.
          AnxLog.warning('Translation usage could not be recorded');
        }
      }
      if (!token.isCancelled) yield translated.join();
    } on DioException catch (error) {
      if (token.isCancelled) return;
      // Never expose request bodies, signatures, keys or provider error echoes.
      throw StateError(
          '${engine.name} translation failed (HTTP ${error.response?.statusCode ?? "network"})');
    } finally {
      if (_client == null) client.close(force: true);
    }
  }
}
