import 'package:anx_reader/service/dictionary/dictionary_source_registry.dart';
import 'package:anx_reader/service/registry/host_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => DictionarySourceRegistry.useForTesting(null));

  test('built-in online sources keep their historical ids', () {
    final registry = DictionarySourceRegistry.instance;
    expect(registry.onlineSources.map((e) => e.id), [
      'wiktionaryZh',
      'wiktionaryEn',
    ]);
    expect(registry.onlineSources.first.token, 'online:wiktionaryZh');
  });

  test('stored tokens resolve back to their source', () {
    final registry = DictionarySourceRegistry.instance;
    expect(registry.fromToken('online:wiktionaryZh')?.id, 'wiktionaryZh');
    expect(registry.fromToken('online:wiktionaryEn')?.id, 'wiktionaryEn');
    // Not a source this build knows: the caller keeps the token.
    expect(registry.fromToken('online:freeEnglish'), isNull);
    expect(registry.fromToken('online:plugin:com.example.pack:en'), isNull);
    expect(registry.fromToken('local:abc'), isNull);
  });

  test('a registered plugin source resolves its namespaced token', () {
    const plugin = PluginOwner('com.example.pack');
    DictionarySourceRegistry.instance.registry.register(
      const DictionarySourceEntry(
        id: 'com.example.pack:en',
        labelZh: '示例词典',
        labelEn: 'Example dictionary',
        kind: DictionarySourceKind.online,
        license: 'CC-BY-4.0',
        owner: plugin,
      ),
    );
    final resolved = DictionarySourceRegistry.instance
        .fromToken('online:plugin:com.example.pack:en');
    expect(resolved?.id, 'com.example.pack:en');
    expect(resolved?.owner, plugin);
    DictionarySourceRegistry.instance.registry.removeAllOwnedBy(plugin);
    expect(
        DictionarySourceRegistry.instance
            .fromToken('online:plugin:com.example.pack:en'),
        isNull);
  });

  test('built-in sources declare a licence and the dictionary domain', () {
    for (final entry in DictionarySourceRegistry.instance.onlineSources) {
      expect(entry.license, isNotEmpty, reason: entry.id);
      expect(entry.attribution, isNotEmpty, reason: entry.id);
      expect(entry.domain, RegistryDomain.dictionary);
      expect(entry.kind, DictionarySourceKind.online);
    }
  });

  test('a plugin cannot overwrite a built-in source', () {
    expect(
      () => DictionarySourceRegistry.instance.registry.register(
        const DictionarySourceEntry(
          id: 'wiktionaryZh',
          labelZh: 'x',
          labelEn: 'x',
          kind: DictionarySourceKind.online,
          owner: PluginOwner('com.example.pack'),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
