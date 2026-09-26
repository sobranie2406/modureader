import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/selection_search.dart';
import 'package:anx_reader/service/config_transfer/global_settings_transfer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('five builtins encode selected text as one query parameter', () {
    const text = '古文 & a+b/#? 百科';
    expect(SelectionSearchEngine.builtins, hasLength(5));
    for (final engine in SelectionSearchEngine.builtins) {
      final url = engine.search(text);
      expect(url.queryParameters.values, contains(text));
      expect(url.fragment, isEmpty);
      expect(url.queryParameters, hasLength(1));
    }
  });

  test('custom path template cannot turn text into URL separators', () {
    const engine = SelectionSearchEngine(
        'custom', 'Wiki', 'https://example.test/wiki/{query}');
    expect(engine.search('a/b?c#d').pathSegments, ['wiki', 'a/b?c#d']);
  });

  test('reject unsafe or ambiguous custom engines', () {
    for (final template in [
      'javascript:alert({query})',
      'file:///books/{query}',
      'intent://{query}',
      'https://{query}.example.test/',
      'https://user:pass@example.test/?q={query}',
      'https://example.test/search',
      'https:///?q={query}',
    ]) {
      expect(() => SelectionSearchEngine('test', 'Test', template).validate(),
          throwsFormatException,
          reason: template);
    }
    for (final url in [
      'modu://settings',
      'intent://open',
      'file:///book',
      'data:text/html,x',
      'javascript:alert(1)'
    ]) {
      expect(SelectionSearchEngine.allowsNavigation(Uri.parse(url)), false);
    }
    expect(
        SelectionSearchEngine.allowsNavigation(
            Uri.parse('https://www.baidu.com/')),
        true);
    expect(SelectionSearchEngine.allowsNavigation(null), false);
  });

  test('settings persist and travel in global links, never AI/TTS-only links',
      () async {
    const config = SelectionSearchConfig(selectedId: 'custom', custom: [
      SelectionSearchEngine(
          'custom', '我的词典', 'https://example.test/?q={query}'),
    ]);
    await Prefs().saveSelectionSearchSettings(config);
    expect(Prefs().selectionSearchSettings.selected.name, '我的词典');
    final file = await GlobalSettingsTransfer.export(Prefs());
    final data =
        await GlobalSettingsTransfer.decode(GlobalSettingsTransfer.link(file));
    expect(data['selectionSearchSettings']['value'], config.encode());
    await Prefs().saveSelectionSearchSettings(const SelectionSearchConfig());
    await GlobalSettingsTransfer.apply(Prefs(), data);
    expect(Prefs().selectionSearchSettings.selectedId, 'custom');
    for (final scope in ['ai', 'tts']) {
      final part = await GlobalSettingsTransfer.decode(
          await GlobalSettingsTransfer.export(Prefs(), scope: scope));
      expect(part.containsKey('selectionSearchSettings'), false);
    }
  });

  test('malformed imported search settings fail before modifying preferences',
      () async {
    final data = await GlobalSettingsTransfer.decode(
        await GlobalSettingsTransfer.export(Prefs()));
    data['selectionSearchSettings'] = {
      'type': 'string',
      'value':
          '{"selectedId":"evil","custom":[{"id":"evil","name":"Bad","template":"javascript:{query}"}]}'
    };
    await expectLater(
        GlobalSettingsTransfer.apply(Prefs(), data), throwsFormatException);
    expect(Prefs().prefs.containsKey('selectionSearchSettings'), false);
    expect(
        () => const SelectionSearchConfig(custom: [
              SelectionSearchEngine(
                  'bing', 'Fake', 'https://example.test/?q={query}')
            ]).encode(),
        throwsFormatException);
  });
}
