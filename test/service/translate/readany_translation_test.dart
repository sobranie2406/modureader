import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/service/translate/deepl.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('ReadAny translation catalog exposes the same three engines', () {
    expect(
      TranslateService.readAnyValues,
      containsAllInOrder([
        TranslateService.microsoftFree,
        TranslateService.ai,
        TranslateService.deepl,
      ]),
    );
  });

  test('new installs default to the key-free ReadAny translation engine', () {
    expect(Prefs().translateService, TranslateService.microsoftFree);
    expect(Prefs().fullTextTranslateService, TranslateService.microsoftFree);
  });

  test('selection and reader translation can share one engine and target', () {
    Prefs().translateService = TranslateService.ai;
    Prefs().fullTextTranslateService = TranslateService.ai;

    expect(Prefs().translateService, TranslateService.ai);
    expect(Prefs().fullTextTranslateService, TranslateService.ai);
  });

  test('DeepL URL normalization accepts base and full translate URLs', () {
    expect(
      normalizeDeepLBaseUrl('https://api-free.deepl.com/v2/translate/'),
      'https://api-free.deepl.com/v2',
    );
    expect(
      normalizeDeepLBaseUrl('https://deeplx.example.test/token/translate'),
      'https://deeplx.example.test/token',
    );
  });

  test(
    'key-free Google transport translates a fixed phrase',
    () async {
      HttpOverrides.global = null;
      final translated =
          await TranslateService.microsoftFree.provider.translateTextOnly(
        '你好世界',
        LangListEnum.auto,
        LangListEnum.english,
      );

      expect(translated.toLowerCase(), contains('hello'));
    },
    skip: Platform.environment['FREE_TRANSLATE_LIVE_TEST'] == '1'
        ? false
        : 'Set FREE_TRANSLATE_LIVE_TEST=1 to run the live network test.',
  );
}
