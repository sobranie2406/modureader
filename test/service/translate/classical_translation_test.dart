import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/service/ai/langchain_runner.dart';
import 'package:modu_reader/service/translate/classical_translation.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, Future<void>?) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = await requestStream
        ?.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return respond(
        options.copyWith(data: utf8.decode(bytes ?? [])), cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Object value, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });
  for (final direction in ClassicalTranslationDirection.values) {
    test('Baidu signs raw UTF-8 and uses documented ${direction.name} codes',
        () async {
      final client = Dio()
        ..httpClientAdapter = FakeAdapter((o, _) async {
          final form = Uri.splitQueryString(o.data as String);
          expect(o.uri.toString(),
              'https://fanyi-api.baidu.com/api/trans/vip/translate');
          expect(form['q'], '学而时习之 & +😀');
          expect(
              form['from'],
              direction == ClassicalTranslationDirection.toModern
                  ? 'wyw'
                  : 'zh');
          expect(
              form['to'],
              direction == ClassicalTranslationDirection.toModern
                  ? 'zh'
                  : 'wyw');
          expect(
              form['sign'],
              md5
                  .convert(utf8.encode('app${form['q']}${form['salt']}secret'))
                  .toString());
          return jsonBody({
            'trans_result': [
              {'dst': '译文'}
            ]
          });
        });
      final service = ClassicalTranslation(
          engine: ClassicalTranslationEngine.baidu,
          direction: direction,
          config: {'baidu_appid': 'app', 'baidu_key': 'secret'},
          aiService: '',
          client: client);
      expect(
          await service
              .translate('学而时习之 & +😀', CancelableLangchainRunner())
              .last,
          '译文');
    });
    test('Microsoft ${direction.name} sends official JSON and auth headers',
        () async {
      final client = Dio()
        ..httpClientAdapter = FakeAdapter((o, _) async {
          expect(o.uri.host, 'api.cognitive.microsofttranslator.com');
          expect(o.queryParameters, {
            'api-version': '3.0',
            'from': direction == ClassicalTranslationDirection.toModern
                ? 'lzh'
                : 'zh-Hans',
            'to': direction == ClassicalTranslationDirection.toModern
                ? 'zh-Hans'
                : 'lzh'
          });
          expect(o.headers['Ocp-Apim-Subscription-Key'], 'key');
          expect(o.headers['Ocp-Apim-Subscription-Region'], 'eastasia');
          expect(jsonDecode(o.data as String), [
            {'Text': 'test'}
          ]);
          return jsonBody([
            {
              'translations': [
                {'text': 'result'}
              ]
            }
          ]);
        });
      final service = ClassicalTranslation(
          engine: ClassicalTranslationEngine.microsoft,
          direction: direction,
          config: {'microsoft_key': 'key', 'microsoft_region': 'eastasia'},
          aiService: '',
          client: client);
      expect(await service.translate('test', CancelableLangchainRunner()).last,
          'result');
    });
  }
  test('long paragraphs retain every code point and global region is omitted',
      () async {
    final inputs = <String>[];
    final client = Dio()
      ..httpClientAdapter = FakeAdapter((o, _) async {
        expect(o.headers.containsKey('Ocp-Apim-Subscription-Region'), isFalse);
        final text =
            (jsonDecode(o.data as String) as List).first['Text'] as String;
        inputs.add(text);
        return jsonBody([
          {
            'translations': [
              {'text': text}
            ]
          }
        ]);
      });
    final service = ClassicalTranslation(
        engine: ClassicalTranslationEngine.microsoft,
        config: {'microsoft_key': 'key', 'microsoft_region': 'global'},
        aiService: '',
        client: client);
    final source = List.filled(1900, '😀').join();
    expect(await service.translate(source, CancelableLangchainRunner()).last,
        source);
    expect(inputs.map((s) => s.runes.length), [900, 900, 100]);
  });
  test('stop cancels HTTP and does not send later chunks', () async {
    var count = 0;
    final started = Completer<void>();
    final cancelled = Completer<void>();
    final client = Dio()
      ..httpClientAdapter = FakeAdapter((o, cancel) async {
        count++;
        started.complete();
        await cancel;
        cancelled.complete();
        return jsonBody([
          {
            'translations': [
              {'text': 'late'}
            ]
          }
        ]);
      });
    final service = ClassicalTranslation(
        engine: ClassicalTranslationEngine.microsoft,
        config: {'microsoft_key': 'key'},
        aiService: '',
        client: client);
    final runner = CancelableLangchainRunner();
    final result =
        service.translate(List.filled(1900, '字').join(), runner).toList();
    await started.future;
    await runner.cancel();
    await cancelled.future;
    expect(await result, isEmpty);
    expect(count, 1);
  });
  test('already stopped sessions never call a provider', () async {
    final runner = CancelableLangchainRunner();
    await runner.cancel();
    final service = ClassicalTranslation(
        engine: ClassicalTranslationEngine.microsoft,
        config: {},
        aiService: '');
    expect(await service.translate('text', runner).toList(), isEmpty);
  });
  test('provider failures never expose credentials or echoed book text',
      () async {
    final client = Dio()
      ..httpClientAdapter = FakeAdapter((o, _) async =>
          jsonBody({'error': 'key and private book'}, status: 401));
    final service = ClassicalTranslation(
        engine: ClassicalTranslationEngine.microsoft,
        config: {'microsoft_key': 'sensitive'},
        aiService: '',
        client: client);
    await expectLater(
        service.translate('private book', CancelableLangchainRunner()).last,
        throwsA(predicate((e) =>
            e.toString().contains('401') &&
            !e.toString().contains('sensitive') &&
            !e.toString().contains('private book'))));
  });
  test('direction participates in cache identity and AI prompt', () {
    final forward = ClassicalTranslation(
        engine: ClassicalTranslationEngine.microsoft,
        config: {},
        aiService: '');
    final reverse = ClassicalTranslation(
        engine: ClassicalTranslationEngine.microsoft,
        config: {},
        aiService: '',
        direction: ClassicalTranslationDirection.toClassical);
    expect(forward.identity, isNot(reverse.identity));
    expect(
        ClassicalTranslation.messages('source',
                direction: ClassicalTranslationDirection.toClassical)
            .first
            .toString(),
        contains('现代汉语逐段翻译'));
  });
  test('key rotation does not invalidate translated paragraphs', () {
    final provider = <String, dynamic>{
      'id': 'test',
      'model': 'model-a',
      'keyIndex': 0,
      'updatedAt': '2026-10-23T10:00:00Z',
    };
    Prefs().saveAiProviders([provider]);
    final service = ClassicalTranslation(
        engine: ClassicalTranslationEngine.ai, config: {}, aiService: 'test');
    final original = service.identity;
    Prefs().saveAiProviders([
      {...provider, 'keyIndex': 1, 'updatedAt': '2026-10-23T10:01:00Z'},
      {'id': 'unrelated', 'model': 'other-model'},
    ]);
    expect(service.identity, original);
    Prefs().saveAiProviders([
      {...provider, 'model': 'model-b'}
    ]);
    expect(service.identity, isNot(original));
  });
}
