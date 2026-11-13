import 'dart:async';
import 'dart:convert';
import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/enums/lang_list.dart';
import 'package:modu_reader/service/translate/index.dart';
import 'package:modu_reader/service/translate/official_api.dart';
import 'package:modu_reader/service/translate/translation_usage.dart';
import 'package:modu_reader/service/translate/translation_api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'classical_translation_test.dart' show FakeAdapter, jsonBody;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    Prefs().classicalTranslationConfig = {
      'baidu_appid': 'app',
      'baidu_key': 'secret',
      'microsoft_key': 'key',
      'microsoft_region': 'eastasia',
    };
  });
  test('usage counts successful Unicode chunks but not provider errors',
      () async {
    final config = Prefs().classicalTranslationConfig;
    final account = TranslationUsage.account('microsoft', config);
    var fail = false;
    final client = Dio()
      ..httpClientAdapter = FakeAdapter((o, _) async => fail
          ? jsonBody({'error': 'no quota'}, status: 429)
          : jsonBody([
              {
                'translations': [
                  {'text': 'translated'}
                ]
              }
            ]));
    final api = TranslationApiClient(TranslationApiEngine.microsoft, config,
        client: client);
    await api.translate('学😀${'x' * 900}', from: 'zh-Hans', to: 'en').last;
    expect(TranslationUsage(Prefs().prefs).used(account), 902);
    fail = true;
    await expectLater(api.translate('error', from: 'en', to: 'zh-Hans').last,
        throwsStateError);
    expect(TranslationUsage(Prefs().prefs).used(account), 902);
  });
  test('both official APIs are selectable and use shared saved credentials',
      () {
    expect(
        TranslateService.readAnyValues,
        containsAll(
            [TranslateService.baiduApi, TranslateService.microsoftApi]));
    expect(
        TranslateService.baiduApi.provider.getConfig()['baidu_key'], 'secret');
    expect(TranslateService.microsoftApi.provider.getConfig()['microsoft_key'],
        'key');
    expect(
        TranslateService.baiduApi.provider
            .mapLanguageCode(LangListEnum.japanese),
        'jp');
    expect(
        TranslateService.microsoftApi.provider
            .mapLanguageCode(LangListEnum.traditionalChinese),
        'zh-Hant');
    expect(
        () => TranslateService.baiduApi.provider
            .mapLanguageCode(LangListEnum.crimeanTatarLatin),
        throwsStateError);
  });
  test(
      'Baidu ordinary translation sends selected target, not classical direction',
      () async {
    final dio = Dio()
      ..httpClientAdapter = FakeAdapter((o, _) async {
        final form = Uri.splitQueryString(o.data as String);
        expect(form['from'], 'auto');
        expect(form['to'], 'en');
        expect(form['appid'], 'app');
        return jsonBody({
          'trans_result': [
            {'dst': 'Learning is a pleasure.'}
          ]
        });
      });
    final p =
        OfficialApiTranslateProvider(TranslateService.baiduApi, client: dio);
    expect(
        await p
            .translateStream(
                '学而时习之，不亦乐乎', LangListEnum.auto, LangListEnum.english)
            .last,
        'Learning is a pleasure.');
  });
  test('Microsoft auto detection omits from and global region header',
      () async {
    Prefs().classicalTranslationConfig = {
      'microsoft_key': 'key',
      'microsoft_region': 'global'
    };
    final dio = Dio()
      ..httpClientAdapter = FakeAdapter((o, _) async {
        expect(o.queryParameters, {'api-version': '3.0', 'to': 'zh-Hans'});
        expect(o.headers['Ocp-Apim-Subscription-Key'], 'key');
        expect(o.headers, isNot(contains('Ocp-Apim-Subscription-Region')));
        expect(jsonDecode(o.data as String), [
          {'Text': 'Hello'}
        ]);
        return jsonBody([
          {
            'translations': [
              {'text': '你好'}
            ]
          }
        ]);
      });
    expect(
        await OfficialApiTranslateProvider(TranslateService.microsoftApi,
                client: dio)
            .translateStream(
                'Hello', LangListEnum.auto, LangListEnum.simplifiedChinese)
            .last,
        '你好');
  });
  test('legacy Microsoft credentials remain usable', () {
    Prefs().classicalTranslationConfig = {};
    Prefs().saveTranslateServiceConfig(TranslateService.microsoftApi,
        {'api_key': 'old', 'region': 'eastasia'});
    expect(TranslateService.microsoftApi.provider.getConfig()['microsoft_key'],
        'old');
  });
  test('stop cancels official API transport without yielding late results',
      () async {
    final started = Completer<void>(),
        cancelled = Completer<void>(),
        stop = Completer<void>();
    final dio = Dio()
      ..httpClientAdapter = FakeAdapter((o, cancel) async {
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
    final result =
        OfficialApiTranslateProvider(TranslateService.microsoftApi, client: dio)
            .translateStream('test', LangListEnum.auto, LangListEnum.english,
                whenCancelled: stop.future)
            .toList();
    await started.future;
    stop.complete();
    await cancelled.future;
    expect(await result, isEmpty);
  });
}
