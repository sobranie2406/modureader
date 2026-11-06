import 'package:anx_reader/service/registry/host_registry.dart';
import 'package:anx_reader/service/translate/index.dart';
import 'package:anx_reader/service/translate/microsoft_free.dart';
import 'package:anx_reader/service/translate/translate_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => TranslateRegistry.useForTesting(null));

  test('every built-in translation id is registered exactly once', () {
    final ids = TranslateRegistry.current.registry.all.map((e) => e.id).toList();
    expect(ids, [
      'microsoftFree',
      'bingWeb',
      'googleWeb',
      'microsoftApi',
      'googleApi',
      'deepl',
      'ai',
      'baiduApi',
      'baiduWeb',
      'youdaoWeb',
    ]);
    expect(ids.toSet(), hasLength(TranslateService.values.length));
  });

  test('the retired microsoft token still resolves to microsoftApi', () {
    expect(getTranslateService('microsoft'), TranslateService.microsoftApi);
    expect(TranslateRegistry.current.resolveService('microsoft'),
        TranslateService.microsoftApi);
    expect(TranslateRegistry.current.resolveService('microsoftApi'),
        TranslateService.microsoftApi);
  });

  test('unknown tokens fall back to the key-free engine', () {
    expect(getTranslateService('nope'), TranslateService.microsoftFree);
    expect(TranslateRegistry.current.resolveService('nope'), isNull);
  });

  test('every enum value has a provider', () {
    for (final service in TranslateService.values) {
      expect(service.provider, isNotNull, reason: service.name);
    }
  });

  test('picker orders are stable and filtered, not registration order', () {
    expect(TranslateService.readAnyValues, [
      TranslateService.microsoftFree,
      TranslateService.baiduApi,
      TranslateService.microsoftApi,
      TranslateService.ai,
      TranslateService.deepl,
    ]);
    expect(TranslateService.webValues, [
      TranslateService.googleWeb,
      TranslateService.bingWeb,
      TranslateService.baiduWeb,
      TranslateService.youdaoWeb,
    ]);
  });

  test('webview providers cannot translate a whole book', () {
    for (final service in TranslateService.values) {
      final entry = TranslateRegistry.current.registry.byId(service.name)!;
      expect(entry.supportsFullText, !service.isWebView, reason: service.name);
    }
  });

  test('export order lists built-ins without depending on the picker', () {
    expect(TranslateRegistry.current.exportOrder, [
      'microsoftFree',
      'bingWeb',
      'googleWeb',
      'microsoftApi',
      'googleApi',
      'deepl',
      'baiduApi',
      'baiduWeb',
      'youdaoWeb',
    ]);
  });

  test('a plugin entry cannot take a built-in id', () {
    expect(
      () => TranslateRegistry.current.registry.register(
        TranslateProviderEntry(
          id: 'deepl',
          builder: MicrosoftFreeTranslateProvider.new,
          owner: const PluginOwner('com.example.pack'),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('entries declare the translate domain', () {
    final entry = TranslateRegistry.current.registry.byId('deepl')!;
    expect(entry.domain, RegistryDomain.translate);
    expect(entry.owner, const RegistryOwner.builtIn());
  });
}