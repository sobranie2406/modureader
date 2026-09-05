class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.modelId,
    required this.apiKey,
    this.enableTools = true,
    this.timeout = const Duration(seconds: 30),
  });

  final String id;
  final String name;
  final String baseUrl;
  final String modelId;
  final String apiKey;
  final bool enableTools;
  final Duration timeout;

  Map<String, Object> toSafeMap() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'modelId': modelId,
        'apiKey': '***',
        'enableTools': enableTools,
        'timeoutSeconds': timeout.inSeconds,
      };
}

class AiChatRequest {
  const AiChatRequest({required this.messages, this.scope = 'library'});

  final List<String> messages;
  final String scope;
}

sealed class AiStreamEvent {
  const AiStreamEvent();
}

class AiTextDelta extends AiStreamEvent {
  const AiTextDelta(this.text);
  final String text;
}

class AiToolCall extends AiStreamEvent {
  const AiToolCall(this.name, this.arguments);
  final String name;
  final Map<String, Object?> arguments;
}

abstract interface class AiProvider {
  AiProviderConfig get config;
  Stream<AiStreamEvent> streamChat(AiChatRequest request);
}
