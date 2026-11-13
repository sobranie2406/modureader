import 'package:modu_reader/service/config_transfer/tts_config_transfer.dart';
import 'package:modu_reader/service/registry/host_registry.dart';
import 'package:modu_reader/service/tts/edge_tts_backend.dart';
import 'package:modu_reader/service/tts/tts_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => TtsRegistry.useForTesting(null));

  test('every built-in id is registered in a stable order', () {
    expect(TtsRegistry.instance.services.map((s) => s.name), [
      'system',
      'edge',
      'dashscope',
      'xiaomi',
      'openai',
    ]);
    expect(TtsRegistry.instance.services, hasLength(TtsService.values.length));
  });

  test('retired aliyun and azure resolve to system', () {
    for (final retired in TtsRegistry.retiredAliases) {
      expect(getTtsService(retired), TtsService.system, reason: retired);
    }
    expect(getTtsService('edge'), TtsService.edge);
    expect(getTtsService('nope'), TtsService.system);
  });

  test('every enum value has a provider and a domain', () {
    for (final service in TtsService.values) {
      expect(service.provider, isNotNull, reason: service.name);
      expect(TtsRegistry.instance.registry.byId(service.name)!.domain,
          RegistryDomain.tts);
    }
  });

  test('only online providers own a configuration key', () {
    expect(TtsRegistry.instance.configurableIds,
        ['edge', 'dashscope', 'xiaomi', 'openai']);
    expect(TtsRegistry.instance.registry.byId('system')!.configurable, isFalse);
    expect(TtsService.system.isOnline, isFalse);
    expect(TtsService.edge.isOnline, isTrue);
  });

  test('the transfer snapshot keeps the historical five-provider order', () {
    expect(TtsConfigTransfer.services, ['system', 'edge', 'dashscope', 'xiaomi', 'openai']);
    expect(TtsConfigTransfer.isKnownProvider('edge'), isTrue);
    expect(TtsConfigTransfer.isKnownProvider('elevenlabs'), isFalse);
  });

  test('a plugin entry cannot take a built-in id', () {
    expect(
      () => TtsRegistry.instance.registry.register(
        TtsProviderEntry(
          id: 'edge',
          builder: EdgeTtsProvider.new,
          owner: const PluginOwner('com.example.pack'),
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}