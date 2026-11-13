import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/service/registry/host_registry.dart';
import 'package:modu_reader/service/tts/edge_tts_backend.dart';
import 'package:modu_reader/service/tts/openai_tts_backend.dart';
import 'package:modu_reader/service/tts/readany_compatible_tts_backend.dart';
import 'package:modu_reader/service/tts/tts_service_provider.dart';
import 'package:flutter/material.dart';

/// TTS service enumeration.
///
/// The enum stays because `name` is the persisted token in 'ttsService' and the
/// suffix of 'onlineTtsConfig_' / 'ttsVoiceModel_'. The provider table itself
/// lives in [TtsRegistry]; P2 moved it there without renaming any id.
enum TtsService {
  system,
  edge,
  dashscope,
  xiaomi,
  openai;

  /// Get the provider for this TTS service.
  TtsServiceProvider get provider => TtsRegistry.current.providerFor(name);

  /// Get the display label from the provider.
  String getLabel(BuildContext context) => provider.getLabel(context);

  /// Check if the service is an online TTS provider.
  bool get isOnline => this != TtsService.system;
}

/// Get TTS service from service ID string.
///
/// Retired ids ('aliyun', 'azure') fall back to `system`, matching the value
/// the preference getter already normalises to.
TtsService getTtsService(String serviceId) =>
    TtsRegistry.current.resolveService(serviceId) ?? TtsService.system;

/// One speech provider.
class TtsProviderEntry implements RegistryEntry {
  const TtsProviderEntry({
    required this.id,
    required this.builder,
    this.aliases = const [],
    this.isOnline = true,
    this.configurable = true,
    this.owner = const RegistryOwner.builtIn(),
  });

  @override
  final String id;

  @override
  final List<String> aliases;

  @override
  final RegistryOwner owner;

  @override
  RegistryDomain get domain => RegistryDomain.tts;

  final TtsServiceProvider Function() builder;

  final bool isOnline;

  /// `system` has no 'onlineTtsConfig_...' key.
  final bool configurable;
}

class TtsRegistry {
  TtsRegistry(Iterable<TtsProviderEntry> entries) {
    for (final entry in entries) {
      registry.register(entry);
    }
  }

  static final TtsRegistry instance = TtsRegistry(_builtIn);

  static TtsRegistry _current = instance;

  static TtsRegistry get current => _current;

  static void useForTesting(TtsRegistry? value) => _current = value ?? instance;

  final HostRegistry<TtsProviderEntry> registry =
      HostRegistry<TtsProviderEntry>(RegistryDomain.tts);

  /// Retired provider ids. `Prefs.ttsService` normalises these to 'system'.
  static const Set<String> retiredAliases = {'aliyun', 'azure'};

  TtsService? resolveService(String id) {
    final entry = registry.resolve(id);
    if (entry == null) return null;
    for (final service in TtsService.values) {
      if (service.name == entry.id) return service;
    }
    return null;
  }

  TtsServiceProvider providerFor(String id) {
    final entry = registry.resolve(id);
    if (entry == null) throw StateError('Unknown TTS provider: $id');
    return entry.builder();
  }

  /// Providers in settings, in registration order.
  List<TtsService> get services => [
        for (final entry in registry.all)
          if (entry.owner is BuiltInOwner)
            TtsService.values.firstWhere((service) => service.name == entry.id),
      ];

  /// Providers that own an 'onlineTtsConfig_' key and a voice selection.
  List<String> get configurableIds => [
        for (final entry in registry.all)
          if (entry.owner is BuiltInOwner && entry.configurable) entry.id,
      ];

  /// Fixed order used by settings export so older builds read every key.
  List<String> get exportOrder => configurableIds;

  /// Ids written to a transfer snapshot, always all built-ins in this order.
  static List<String> get transferOrder => const [
        'system',
        'edge',
        'dashscope',
        'xiaomi',
        'openai',
      ];

  static final List<TtsProviderEntry> _builtIn = [
    TtsProviderEntry(
      id: 'system',
      // Retired providers an older installation may still have stored.
      aliases: ['aliyun', 'azure'],
      isOnline: false,
      configurable: false,
      builder: SystemTtsProvider.new,
    ),
    TtsProviderEntry(id: 'edge', builder: EdgeTtsProvider.new),
    TtsProviderEntry(id: 'dashscope', builder: DashScopeTtsProvider.new),
    TtsProviderEntry(id: 'xiaomi', builder: XiaomiMimoTtsProvider.new),
    TtsProviderEntry(id: 'openai', builder: OpenAiTtsProvider.new),
  ];
}

/// System TTS provider (placeholder for service provider pattern).
/// System TTS doesn't need configuration, so it returns empty config items.
class SystemTtsProvider extends TtsServiceProvider {
  @override
  TtsService get service => TtsService.system;

  @override
  String getLabel(BuildContext context) =>
      L10n.of(context).settingsNarrateSystemTts;
}