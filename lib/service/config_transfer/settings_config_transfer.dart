import 'package:anx_reader/models/ai_provider.dart';

class WebdavTransferResult {
  const WebdavTransferResult({
    required this.syncInfo,
    this.enabled,
    this.autoSync,
    this.wifiOnly,
    this.notifyOnComplete,
  });

  final Map<String, dynamic> syncInfo;
  final bool? enabled;
  final bool? autoSync;
  final bool? wifiOnly;
  final bool? notifyOnComplete;
}

class WebdavConfigTransfer {
  const WebdavConfigTransfer._();

  static Map<String, dynamic> createPayload({
    required Map<String, dynamic> syncInfo,
    required bool enabled,
    required bool autoSync,
    required bool wifiOnly,
    required bool notifyOnComplete,
  }) {
    final config = <String, dynamic>{
      'type': 'webdav',
      'url': syncInfo['url']?.toString() ?? '',
      'username': syncInfo['username']?.toString() ?? '',
      'autoSync': autoSync,
      'wifiOnly': wifiOnly,
      'notifyOnComplete': notifyOnComplete,
    };
    for (final key in const ['remoteRoot', 'allowInsecure']) {
      if (syncInfo.containsKey(key)) config[key] = syncInfo[key];
    }
    return <String, dynamic>{
      'backendType': 'webdav',
      'config': config,
      'password': syncInfo['password']?.toString() ?? '',
      'enabled': enabled,
    };
  }

  /// Accepts both Modu's payload and the object produced by ReadAny's sync
  /// ConfigTransfer component.
  static WebdavTransferResult parse(Map<String, dynamic> data) {
    final backendType = data['backendType'];
    if (backendType != null && backendType != 'webdav') {
      throw const FormatException('该代码不是 WebDAV 配置');
    }
    final rawConfig = data['config'];
    final config = rawConfig is Map
        ? Map<String, dynamic>.from(rawConfig)
        : Map<String, dynamic>.from(data);
    final type = config['type'];
    if (type != null && type != 'webdav') {
      throw const FormatException('该代码不是 WebDAV 配置');
    }
    final url = config['url'];
    if (url is! String) {
      throw const FormatException('WebDAV 配置缺少服务器地址');
    }
    final result = <String, dynamic>{
      ...config,
      'url': url.trim(),
      'username': config['username']?.toString() ?? '',
      'password':
          data['password']?.toString() ?? config['password']?.toString() ?? '',
    };
    return WebdavTransferResult(
      syncInfo: result,
      enabled: data['enabled'] is bool ? data['enabled'] as bool : null,
      autoSync: _readBool(config, data, 'autoSync'),
      wifiOnly: _readBool(config, data, 'wifiOnly'),
      notifyOnComplete: _readBool(config, data, 'notifyOnComplete'),
    );
  }

  static bool? _readBool(
    Map<String, dynamic> config,
    Map<String, dynamic> data,
    String key,
  ) {
    final value = config[key] ?? data[key];
    return value is bool ? value : null;
  }
}

class AiTransferResult {
  const AiTransferResult({
    required this.providers,
    required this.selectedProviderId,
    required this.temperature,
    required this.maxTokens,
    required this.contextTurns,
    this.rpm,
    this.translationProviderId,
  });

  final List<AiProvider> providers;
  final String selectedProviderId;
  final double temperature;
  final int maxTokens;
  final int contextTurns;
  final int? rpm;
  final String? translationProviderId;
}

class AiConfigTransfer {
  const AiConfigTransfer._();

  static Map<String, dynamic> createPayload({
    required List<AiProvider> providers,
    required String selectedProviderId,
    required double temperature,
    required int maxTokens,
    required int contextTurns,
    required int rpm,
    required String translationProviderId,
  }) {
    AiProvider? active;
    for (final provider in providers) {
      if (provider.id == selectedProviderId) active = provider;
    }
    active ??= providers.isEmpty ? null : providers.first;

    return <String, dynamic>{
      // These fields intentionally match ReadAny's AIConfig schema.
      'endpoints': providers
          .map(
            (provider) => <String, dynamic>{
              'id': provider.id,
              'name': provider.title,
              'provider': _toReadAnyProvider(provider.protocol),
              'apiKey': provider.currentApiKey ?? '',
              'baseUrl': provider.url,
              'models': provider.model.isEmpty ? <String>[] : [provider.model],
              'modelsFetched': provider.model.isNotEmpty,
            },
          )
          .toList(),
      'activeEndpointId': active?.id ?? '',
      'activeModel': active?.model ?? '',
      'temperature': active?.temperature ?? temperature,
      'maxTokens': active?.maxTokens ?? maxTokens,
      'slidingWindowSize': active?.contextTurns ?? contextTurns,
      // Modu-only fields retain multiple keys and per-provider options.
      'moduProviders': providers.map((provider) => provider.toJson()).toList(),
      'rpm': rpm,
      'translationProviderId': translationProviderId,
    };
  }

  /// Accepts native Modu data or ReadAny's AIConfig object.
  static AiTransferResult parse(Map<String, dynamic> data) {
    final temperature =
        _readDouble(data['temperature'], 0.7).clamp(0.0, 1.0).toDouble();
    final maxTokens =
        _readInt(data['maxTokens'], 8192).clamp(1024, 32768).toInt();
    final contextTurns =
        _readInt(data['slidingWindowSize'], 8).clamp(2, 30).toInt();
    final moduProviders = _parseModuProviders(
      data['moduProviders'],
      temperature: temperature,
      maxTokens: maxTokens,
      contextTurns: contextTurns,
    );
    final providers = moduProviders == null || moduProviders.isEmpty
        ? _parseReadAnyEndpoints(
            data['endpoints'],
            data['activeEndpointId'],
            data['activeModel'],
            temperature: temperature,
            maxTokens: maxTokens,
            contextTurns: contextTurns,
          )
        : moduProviders;
    if (providers.isEmpty) {
      throw const FormatException('AI 配置中没有有效的服务商');
    }

    var selected = data['activeEndpointId']?.toString() ?? '';
    if (!providers.any((provider) => provider.id == selected)) {
      selected = providers.first.id;
    }

    final rpm = data['rpm'] == null ? null : _readInt(data['rpm'], 0);

    return AiTransferResult(
      providers: providers,
      selectedProviderId: selected,
      temperature: temperature,
      maxTokens: maxTokens,
      contextTurns: contextTurns,
      rpm: rpm,
      translationProviderId: data['translationProviderId']?.toString(),
    );
  }

  static List<AiProvider>? _parseModuProviders(
    Object? raw, {
    required double temperature,
    required int maxTokens,
    required int contextTurns,
  }) {
    if (raw is! List) return null;
    try {
      return raw.whereType<Map>().map((item) {
        final provider = AiProvider.fromJson(Map<String, dynamic>.from(item));
        return provider.copyWith(
          temperature:
              (provider.temperature ?? temperature).clamp(0.0, 1.0).toDouble(),
          maxTokens:
              (provider.maxTokens ?? maxTokens).clamp(1024, 32768).toInt(),
          contextTurns:
              (provider.contextTurns ?? contextTurns).clamp(2, 30).toInt(),
        );
      }).toList();
    } catch (_) {
      throw const FormatException('默读 AI 服务商配置无效');
    }
  }

  static List<AiProvider> _parseReadAnyEndpoints(
    Object? raw,
    Object? activeEndpointId,
    Object? activeModel, {
    required double temperature,
    required int maxTokens,
    required int contextTurns,
  }) {
    if (raw is! List) {
      throw const FormatException('AI 配置缺少 endpoints');
    }
    final now = DateTime.now();
    final providers = <AiProvider>[];
    for (final item in raw.whereType<Map>()) {
      final endpoint = Map<String, dynamic>.from(item);
      final id = endpoint['id']?.toString().trim() ?? '';
      final title = endpoint['name']?.toString().trim() ?? '';
      final rawUrl = endpoint['baseUrl']?.toString().trim() ?? '';
      if (id.isEmpty || title.isEmpty || rawUrl.isEmpty) continue;
      final url = _normalizeReadAnyBaseUrl(rawUrl);
      final apiKey = endpoint['apiKey']?.toString() ?? '';
      final models = endpoint['models'] is List
          ? (endpoint['models'] as List)
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList()
          : <String>[];
      final isActive = id == activeEndpointId?.toString();
      final model = _selectReadAnyModel(
        url: url,
        models: models,
        isActive: isActive,
        activeModel: activeModel?.toString() ?? '',
      );
      providers.add(
        AiProvider(
          id: id,
          title: title,
          url: url,
          protocol: _fromReadAnyProvider(
            endpoint['provider']?.toString(),
            url: url,
          ),
          enabled: true,
          isBuiltin: false,
          apiKeys: apiKey.isEmpty
              ? const []
              : [
                  AiApiKey(
                    id: '$id-imported-key',
                    key: apiKey,
                    createdAt: now,
                  ),
                ],
          model: model,
          temperature: temperature,
          maxTokens: maxTokens,
          contextTurns: contextTurns,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return providers;
  }

  static String _normalizeReadAnyBaseUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return rawUrl;
    final host = uri.host.toLowerCase();
    if (host == 'api.minimaxi.com' &&
        (uri.pathSegments.isEmpty ||
            (uri.pathSegments.length == 1 &&
                uri.pathSegments.single.toLowerCase() == 'anthropic'))) {
      // MiniMax supports both protocols, but its Anthropic-compatible stream
      // currently contains nullable fields rejected by our strict Dart SDK.
      // The official OpenAI-compatible endpoint works with the same API key.
      return uri.replace(path: '/v1').toString();
    }
    if (uri.pathSegments.isNotEmpty) return rawUrl;
    const versionedHosts = {
      'api.deepseek.com',
      'api.siliconflow.cn',
      'api.moonshot.cn',
    };
    if (!versionedHosts.contains(host)) return rawUrl;
    return uri.replace(path: '/v1').toString();
  }

  static String _selectReadAnyModel({
    required String url,
    required List<String> models,
    required bool isActive,
    required String activeModel,
  }) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    final selectedModel = activeModel.trim();
    if (host == 'api.moonshot.cn') {
      // Kimi's live catalog now exposes kimi-k2.6 for this endpoint. Prefer it
      // over stale ReadAny exports that still reference kimi-k2.5.
      return 'kimi-k2.6';
    }
    if (host == 'api.qnaigc.com') {
      // The legacy deepseek-r1 entry is still listed but its inference backend
      // currently returns 502. This model was verified against the same API.
      return 'deepseek/deepseek-v4-flash';
    }
    if (isActive &&
        selectedModel.isNotEmpty &&
        _isLikelyChatModel(selectedModel)) {
      return selectedModel;
    }
    if (host == 'api.minimaxi.com' && models.isEmpty) {
      return 'MiniMax-M2.7';
    }
    if (host == 'api.siliconflow.cn') {
      // Qwen/QwQ-32B was removed from SiliconFlow's live model catalog.
      // Prefer the current general-purpose chat model verified by the API.
      return 'Qwen/Qwen3.5-27B';
    }
    if (models.isEmpty) return '';
    return models.firstWhere(_isLikelyChatModel, orElse: () => models.first);
  }

  static bool _isLikelyChatModel(String model) {
    final value = model.toLowerCase();
    const nonChatMarkers = [
      'embedding',
      'rerank',
      'bge-',
      '/bge',
      'whisper',
      'stable-diffusion',
      'flux.',
      'clip-',
      'text-to-image',
      'speech',
    ];
    return !nonChatMarkers.any(value.contains);
  }

  static String _toReadAnyProvider(AiProtocol protocol) {
    return switch (protocol) {
      AiProtocol.claude => 'anthropic',
      AiProtocol.gemini => 'google',
      AiProtocol.openai => 'openai',
    };
  }

  static AiProtocol _fromReadAnyProvider(String? provider, {String? url}) {
    if (Uri.tryParse(url ?? '')?.host.toLowerCase() == 'api.minimaxi.com') {
      return AiProtocol.openai;
    }
    return switch (provider) {
      'anthropic' => AiProtocol.claude,
      'google' => AiProtocol.gemini,
      _ => AiProtocol.openai,
    };
  }

  static double _readDouble(Object? value, double fallback) {
    return value is num ? value.toDouble() : fallback;
  }

  static int _readInt(Object? value, int fallback) {
    return value is num ? value.round() : fallback;
  }
}
