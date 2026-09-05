import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/ai_services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'ai_providers.g.dart';

@Riverpod(keepAlive: true)
class AiProviders extends _$AiProviders {
  @override
  List<AiProvider> build() {
    final rawProviders = Prefs().getAiProviders();

    // If empty, initialize with built-in providers migrated from old config
    if (rawProviders.isEmpty) {
      return _initializeDefaultProviders();
    }

    // Convert from JSON
    try {
      var providers = rawProviders
          .map((json) => AiProvider.fromJson(json as Map<String, dynamic>))
          .toList();
      var parametersMigrated = false;
      providers = providers.map((provider) {
        final temperature = (provider.temperature ?? Prefs().aiTemperature)
            .clamp(0.0, 1.0)
            .toDouble();
        final maxTokens = (provider.maxTokens ?? Prefs().aiMaxTokens)
            .clamp(1024, 32768)
            .toInt();
        final contextTurns = (provider.contextTurns ?? Prefs().aiContextTurns)
            .clamp(2, 30)
            .toInt();
        if (provider.temperature == temperature &&
            provider.maxTokens == maxTokens &&
            provider.contextTurns == contextTurns) {
          return provider;
        }
        parametersMigrated = true;
        return provider.copyWith(
          temperature: temperature,
          maxTokens: maxTokens,
          contextTurns: contextTurns,
        );
      }).toList();
      if (parametersMigrated) Prefs().saveAiProviders(providers);
      return _reconcileBuiltinProviders(providers);
    } catch (e) {
      // If parsing fails, reinitialize
      return _initializeDefaultProviders();
    }
  }

  /// Initialize default providers from old configuration
  List<AiProvider> _initializeDefaultProviders() {
    final defaultServices = buildDefaultAiServices();
    final providers = defaultServices.map(_providerFromOption).toList();

    // Save to storage
    Prefs().saveAiProviders(providers);
    _ensureValidSelection(providers);

    return providers;
  }

  List<AiProvider> _reconcileBuiltinProviders(List<AiProvider> stored) {
    final providers = stored.toList(growable: true);
    var changed = false;

    for (final option in buildDefaultAiServices()) {
      final index =
          providers.indexWhere((provider) => provider.id == option.identifier);
      if (index < 0) {
        providers.add(_providerFromOption(option));
        changed = true;
        continue;
      }

      final provider = providers[index];
      final migratedModel = _migrateBuiltinModel(provider.id, provider.model);
      final updated = provider.copyWith(
        title: provider.title.trim().isEmpty ? option.title : provider.title,
        logoAsset: provider.logoAsset ?? option.logo,
        url: provider.url.trim().isEmpty ? option.defaultUrl : provider.url,
        protocol: _protocolForIdentifier(option.identifier),
        isBuiltin: true,
        model: migratedModel.isEmpty ? option.defaultModel : migratedModel,
      );
      if (updated != provider) {
        providers[index] = updated;
        changed = true;
      }
    }

    if (changed) Prefs().saveAiProviders(providers);
    _ensureValidSelection(providers);
    return providers;
  }

  AiProvider _providerFromOption(AiServiceOption option) {
    final oldConfig = Prefs().getAiConfig(option.identifier);
    final url = oldConfig['url'] ?? option.defaultUrl;
    final model = _migrateBuiltinModel(
      option.identifier,
      oldConfig['model'] ?? option.defaultModel,
    );
    final apiKey = oldConfig['api_key'] ?? option.defaultApiKey;
    final now = DateTime.now();

    return AiProvider(
      id: option.identifier,
      title: option.title,
      logoAsset: option.logo,
      url: url,
      protocol: _protocolForIdentifier(option.identifier),
      enabled: true,
      isBuiltin: true,
      apiKeys: apiKey.isNotEmpty && apiKey != 'YOUR_API_KEY'
          ? [
              AiApiKey(
                id: const Uuid().v4(),
                key: apiKey,
                enabled: true,
                createdAt: now,
              )
            ]
          : [],
      model: model,
      temperature: Prefs().aiTemperature,
      maxTokens: Prefs().aiMaxTokens,
      contextTurns: Prefs().aiContextTurns,
      keyIndex: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  AiProtocol _protocolForIdentifier(String identifier) {
    return switch (identifier) {
      'claude' => AiProtocol.claude,
      'gemini' => AiProtocol.gemini,
      _ => AiProtocol.openai,
    };
  }

  String _migrateBuiltinModel(String identifier, String model) {
    return switch ((identifier, model.trim())) {
      ('claude', 'claude-3-5-sonnet-20240620') => 'claude-sonnet-4-6',
      ('deepseek', 'deepseek-chat') => 'deepseek-v4-flash',
      ('openrouter', 'gpt-4o-mini') => 'openai/gpt-4o-mini',
      (_, final value) => value,
    };
  }

  void _ensureValidSelection(List<AiProvider> providers) {
    final selectedId = Prefs().selectedAiService;
    final isValid = providers.any(
      (provider) => provider.id == selectedId && provider.enabled,
    );
    if (isValid) return;
    final enabled = providers.where((provider) => provider.enabled).toList();
    final replacement = enabled.isEmpty ? '' : enabled.first.id;
    if (replacement != selectedId) Prefs().selectedAiService = replacement;
  }

  /// Get the currently selected provider
  AiProvider? getSelectedProvider() {
    final selectedId = Prefs().selectedAiService;
    try {
      return state.firstWhere((p) => p.id == selectedId && p.enabled);
    } catch (_) {
      // If not found, return first enabled provider
      final enabled = state.where((p) => p.enabled).toList();
      return enabled.isNotEmpty ? enabled.first : null;
    }
  }

  /// Get a provider by its id, returns null if not found
  AiProvider? getProviderById(String id) {
    try {
      return state.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Set the selected provider
  void setSelectedProvider(String providerId) {
    if (!state
        .any((provider) => provider.id == providerId && provider.enabled)) {
      return;
    }
    Prefs().selectedAiService = providerId;
    ref.notifyListeners();
  }

  /// Add a new custom provider
  void addProvider(AiProvider provider) {
    final now = DateTime.now();
    final newProvider = provider.copyWith(
      id: const Uuid().v4(),
      createdAt: now,
      updatedAt: now,
    );

    state = [...state, newProvider];
    Prefs().saveAiProviders(state);
  }

  /// Update an existing provider
  void updateProvider(AiProvider provider) {
    final now = DateTime.now();
    final updatedProvider = provider.copyWith(updatedAt: now);

    state = [
      for (final p in state)
        if (p.id == provider.id) updatedProvider else p
    ];
    Prefs().saveAiProviders(state);
  }

  /// Delete a provider (only custom providers can be deleted)
  void deleteProvider(String providerId) {
    final provider = state.firstWhere((p) => p.id == providerId);

    if (provider.isBuiltin) {
      throw Exception('Cannot delete built-in provider');
    }

    state = state.where((p) => p.id != providerId).toList();
    Prefs().saveAiProviders(state);

    // If deleted provider was selected, select another
    if (Prefs().selectedAiService == providerId) {
      final enabled = state.where((p) => p.enabled).toList();
      if (enabled.isNotEmpty) {
        setSelectedProvider(enabled.first.id);
      }
    }
  }

  /// Toggle provider enabled state
  void toggleProvider(String providerId, bool enabled) {
    state = [
      for (final p in state)
        if (p.id == providerId) p.copyWith(enabled: enabled) else p
    ];
    Prefs().saveAiProviders(state);
    _ensureValidSelection(state);
  }

  /// Advance the key index for round-robin (called after successful API call)
  void advanceKeyIndex(String providerId) {
    state = [
      for (final p in state)
        if (p.id == providerId)
          p.copyWith(keyIndex: p.keyIndex + 1, updatedAt: DateTime.now())
        else
          p
    ];
    Prefs().saveAiProviders(state);
  }

  /// Add API key to a provider
  void addApiKey(String providerId, String key, {String? label}) {
    final provider = state.firstWhere((p) => p.id == providerId);
    final newKey = AiApiKey(
      id: const Uuid().v4(),
      key: key,
      enabled: true,
      label: label,
      createdAt: DateTime.now(),
    );

    final updatedProvider = provider.copyWith(
      apiKeys: [...provider.apiKeys, newKey],
      updatedAt: DateTime.now(),
    );

    updateProvider(updatedProvider);
  }

  /// Update an API key
  void updateApiKey(String providerId, String keyId,
      {String? key, String? label, bool? enabled}) {
    final provider = state.firstWhere((p) => p.id == providerId);

    final updatedKeys = provider.apiKeys.map((k) {
      if (k.id == keyId) {
        return AiApiKey(
          id: k.id,
          key: key ?? k.key,
          enabled: enabled ?? k.enabled,
          label: label ?? k.label,
          createdAt: k.createdAt,
        );
      }
      return k;
    }).toList();

    final updatedProvider = provider.copyWith(
      apiKeys: updatedKeys,
      updatedAt: DateTime.now(),
    );

    updateProvider(updatedProvider);
  }

  /// Delete an API key
  void deleteApiKey(String providerId, String keyId) {
    final provider = state.firstWhere((p) => p.id == providerId);

    final updatedProvider = provider.copyWith(
      apiKeys: provider.apiKeys.where((k) => k.id != keyId).toList(),
      updatedAt: DateTime.now(),
    );

    updateProvider(updatedProvider);
  }

  /// Refresh providers (reload from storage)
  void refresh() {
    final providers = Prefs().getAiProviders();
    if (providers.isEmpty) {
      state = _initializeDefaultProviders();
      return;
    }
    state = _reconcileBuiltinProviders(
      providers
          .map((json) => AiProvider.fromJson(json as Map<String, dynamic>))
          .toList(),
    );
  }
}
