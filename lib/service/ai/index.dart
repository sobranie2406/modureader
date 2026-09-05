import 'dart:async';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/providers/ai_providers.dart';
import 'package:anx_reader/service/ai/ai_key_rotator.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:anx_reader/service/ai/langchain_registry.dart';
import 'package:anx_reader/service/ai/langchain_runner.dart';
import 'package:anx_reader/utils/ai_reasoning_parser.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';

// Global request timestamps list for RPM throttling
final List<DateTime> _aiRequestTimestamps = [];

/// Throttle AI requests if RPM limit is configured (sliding 1-minute window).
Future<void> _throttleIfNeeded(CancelableLangchainRunner runner) async {
  final rpm = Prefs().aiRpm;
  if (rpm <= 0) return;
  final now = DateTime.now();
  final windowStart = now.subtract(const Duration(minutes: 1));
  _aiRequestTimestamps.removeWhere((ts) => ts.isBefore(windowStart));
  if (_aiRequestTimestamps.length >= rpm) {
    final oldest = _aiRequestTimestamps.first;
    final waitUntil = oldest.add(const Duration(minutes: 1));
    final waitDuration = waitUntil.difference(DateTime.now());
    if (waitDuration > Duration.zero) {
      await Future.any(
          [Future<void>.delayed(waitDuration), runner.whenCancelled]);
    }
    final newNow = DateTime.now();
    _aiRequestTimestamps.removeWhere(
        (ts) => ts.isBefore(newNow.subtract(const Duration(minutes: 1))));
  }
  _aiRequestTimestamps.add(DateTime.now());
}

Stream<String> aiGenerateStream(
  List<ChatMessage> messages, {
  String? identifier,
  Map<String, String>? config,
  AiProvider? providerOverride,
  bool regenerate = false,
  bool useAgent = false,
  Set<String>? allowedToolIds,
  WidgetRef? ref,
  CancelableLangchainRunner? requestRunner,
}) {
  if (useAgent) {
    assert(ref != null, 'ref must be provided when useAgent is true');
  }
  assert(config == null || providerOverride == null,
      'config and providerOverride cannot both be supplied');
  LangchainAiRegistry registry = LangchainAiRegistry(ref);
  final runner = requestRunner ?? CancelableLangchainRunner();
  StreamSubscription<String>? subscription;
  late StreamController<String> controller;
  controller = StreamController<String>(
    onListen: () {
      subscription = _generateStream(
              runner: runner,
              messages: messages,
              identifier: identifier,
              overrideConfig: config,
              providerOverride: providerOverride,
              regenerate: regenerate,
              useAgent: useAgent,
              allowedToolIds: allowedToolIds,
              registry: registry)
          .listen(controller.add,
              onError: controller.addError, onDone: controller.close);
    },
    onCancel: () async {
      await runner.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}

Stream<String> _generateStream({
  required CancelableLangchainRunner runner,
  required List<ChatMessage> messages,
  String? identifier,
  Map<String, String>? overrideConfig,
  AiProvider? providerOverride,
  required bool regenerate,
  required bool useAgent,
  Set<String>? allowedToolIds,
  required LangchainAiRegistry registry,
}) async* {
  AnxLog.info('aiGenerateStream called identifier: $identifier');
  final sanitizedMessages = _sanitizeMessagesForPrompt(messages);

  LangchainAiConfig config;

  // Connection tests use the unsaved form values, including the selected
  // protocol. Testing must not silently save or enable the provider.
  if (providerOverride != null) {
    try {
      final apiKey = AiKeyRotator.getNextKey(providerOverride);
      if (apiKey == null) {
        yield _notConfiguredMessage();
        return;
      }
      config = LangchainAiConfig.fromProvider(
        providerId: providerOverride.id,
        model: providerOverride.model,
        apiKey: apiKey,
        url: providerOverride.url,
        reasoningEffort: providerOverride.reasoningEffort,
        temperature: _providerTemperature(providerOverride),
        maxTokens: _providerMaxTokens(providerOverride),
      );
      final pipeline = registry.resolveByProtocol(
        providerOverride.protocol,
        config,
        useAgent: useAgent,
        allowedToolIds: allowedToolIds,
      );
      await _throttleIfNeeded(runner);
      yield* _executeStream(
        runner: runner,
        model: pipeline.model,
        pipeline: pipeline,
        sanitizedMessages: _limitConversationHistory(
          sanitizedMessages,
          _providerContextTurns(providerOverride),
        ),
        useAgent: useAgent,
      );
    } catch (error, stack) {
      final mapped = _mapError(error);
      AnxLog.severe('AI provider test error: $mapped\n$stack');
      yield mapped;
    }
    return;
  }

  // Try to use new provider system first if ref is available
  if (registry.ref != null && overrideConfig == null) {
    final configuredProviders = registry.ref!.read(aiProvidersProvider);
    if (configuredProviders.isEmpty) {
      // No current provider data exists, so the legacy migration path below
      // remains available for old installations.
    } else {
      try {
        final notifier = registry.ref!.read(aiProvidersProvider.notifier);
        // If a specific provider id was passed, use it; otherwise use the default
        final AiProvider? provider = identifier != null
            ? notifier.getProviderById(identifier)
            : notifier.getSelectedProvider();
        if (provider != null &&
            provider.enabled &&
            AiKeyRotator.hasValidKey(provider)) {
          final apiKey = AiKeyRotator.getNextKey(provider);
          if (apiKey != null) {
            config = LangchainAiConfig.fromProvider(
              providerId: provider.id,
              model: provider.model,
              apiKey: apiKey,
              url: provider.url,
              reasoningEffort: provider.reasoningEffort,
              temperature: _providerTemperature(provider),
              maxTokens: _providerMaxTokens(provider),
            );

            AnxLog.info(
                'aiGenerateStream (new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

            final pipeline = registry.resolveByProtocol(
                provider.protocol, config,
                useAgent: useAgent, allowedToolIds: allowedToolIds);
            final model = pipeline.model;

            await _throttleIfNeeded(runner);
            var successful = false;
            yield* _executeStream(
              runner: runner,
              model: model,
              pipeline: pipeline,
              sanitizedMessages: _limitConversationHistory(
                sanitizedMessages,
                _providerContextTurns(provider),
              ),
              useAgent: useAgent,
              onFinished: (value) => successful = value,
            );

            // Advance key index for round-robin rotation after successful call
            if (successful) {
              registry.ref!
                  .read(aiProvidersProvider.notifier)
                  .advanceKeyIndex(provider.id);
            }
            return;
          }
        }
        yield _notConfiguredMessage();
        return;
      } catch (e) {
        AnxLog.warning('Failed to use configured AI provider: $e');
        yield _mapError(e);
        return;
      }
    }
  }

  // Try new provider system without ref (reads directly from Prefs storage)
  if (overrideConfig == null) {
    try {
      final rawProviders = Prefs().getAiProviders();
      if (rawProviders.isNotEmpty) {
        final providers = rawProviders
            .map((json) => AiProvider.fromJson(json as Map<String, dynamic>))
            .toList();

        AiProvider? provider;
        if (identifier != null) {
          try {
            provider = providers.firstWhere((p) => p.id == identifier);
          } catch (_) {
            provider = null;
          }
        } else {
          final selectedId = Prefs().selectedAiService;
          try {
            provider = providers.firstWhere((p) => p.id == selectedId);
          } catch (_) {}
          provider ??= providers.where((p) => p.enabled).firstOrNull;
        }

        if (provider != null &&
            provider.enabled &&
            AiKeyRotator.hasValidKey(provider)) {
          final apiKey = AiKeyRotator.getNextKey(provider);
          if (apiKey != null) {
            config = LangchainAiConfig.fromProvider(
              providerId: provider.id,
              model: provider.model,
              apiKey: apiKey,
              url: provider.url,
              reasoningEffort: provider.reasoningEffort,
              temperature: _providerTemperature(provider),
              maxTokens: _providerMaxTokens(provider),
            );

            AnxLog.info(
                'aiGenerateStream (no-ref new): ${provider.id}, model: ${config.model}, baseUrl: ${config.baseUrl}');

            final pipeline = registry.resolveByProtocol(
                provider.protocol, config,
                useAgent: useAgent, allowedToolIds: allowedToolIds);
            final model = pipeline.model;

            await _throttleIfNeeded(runner);
            var successful = false;
            yield* _executeStream(
              runner: runner,
              model: model,
              pipeline: pipeline,
              sanitizedMessages: _limitConversationHistory(
                sanitizedMessages,
                _providerContextTurns(provider),
              ),
              useAgent: useAgent,
              onFinished: (value) => successful = value,
            );

            // Advance key index in persistent storage for round-robin rotation
            if (successful) {
              final updatedProviders = providers.map((p) {
                if (p.id == provider!.id) {
                  return p.copyWith(
                      keyIndex: p.keyIndex + 1, updatedAt: DateTime.now());
                }
                return p;
              }).toList();
              Prefs().saveAiProviders(updatedProviders);
            }
            return;
          }
        }
        yield _notConfiguredMessage();
        return;
      }
    } catch (e) {
      AnxLog.warning('Failed to use configured no-ref AI provider: $e');
      yield _mapError(e);
      return;
    }
  }

  // Fall back to legacy system
  final selectedIdentifier = identifier ?? Prefs().selectedAiService;
  final savedConfig = Prefs().getAiConfig(selectedIdentifier);
  if (savedConfig.isEmpty &&
      (overrideConfig == null || overrideConfig.isEmpty)) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      yield L10n.of(context).aiServiceNotConfigured;
    } else {
      yield 'AI service not configured';
    }
    return;
  }

  config = LangchainAiConfig.fromPrefs(selectedIdentifier, savedConfig);
  if (overrideConfig != null && overrideConfig.isNotEmpty) {
    final override =
        LangchainAiConfig.fromPrefs(selectedIdentifier, overrideConfig);
    config = mergeConfigs(config, override);
  }
  config = config.copyWith(
    temperature: config.temperature ?? Prefs().aiTemperature,
    maxTokens: config.maxTokens ?? Prefs().aiMaxTokens,
    maxOutputTokens: config.maxOutputTokens ?? Prefs().aiMaxTokens,
  );

  AnxLog.info(
      'aiGenerateStream (legacy): $selectedIdentifier, model: ${config.model}, baseUrl: ${config.baseUrl}');

  final pipeline = registry.resolve(
    config,
    useAgent: useAgent,
    allowedToolIds: allowedToolIds,
  );
  final model = pipeline.model;

  await _throttleIfNeeded(runner);
  yield* _executeStream(
    runner: runner,
    model: model,
    pipeline: pipeline,
    sanitizedMessages: _limitConversationHistory(
      sanitizedMessages,
      Prefs().aiContextTurns,
    ),
    useAgent: useAgent,
  );
}

List<ChatMessage> _limitConversationHistory(
  List<ChatMessage> messages,
  int turns,
) {
  final systemMessages = messages.whereType<SystemChatMessage>().toList();
  final conversation = messages
      .where((message) => message is! SystemChatMessage)
      .toList(growable: false);
  final keep = turns.clamp(2, 30) * 2;
  final start = conversation.length > keep ? conversation.length - keep : 0;
  return [
    ...systemMessages,
    ...conversation.skip(start),
  ];
}

double _providerTemperature(AiProvider provider) {
  return (provider.temperature ?? Prefs().aiTemperature)
      .clamp(0.0, 1.0)
      .toDouble();
}

int _providerMaxTokens(AiProvider provider) {
  return (provider.maxTokens ?? Prefs().aiMaxTokens).clamp(1024, 32768).toInt();
}

int _providerContextTurns(AiProvider provider) {
  return (provider.contextTurns ?? Prefs().aiContextTurns).clamp(2, 30).toInt();
}

/// Execute the AI stream with the given model and pipeline
Stream<String> _executeStream({
  required CancelableLangchainRunner runner,
  required BaseChatModel model,
  required LangchainPipeline pipeline,
  required List<ChatMessage> sanitizedMessages,
  required bool useAgent,
  void Function(bool successful)? onFinished,
}) async* {
  var successful = false;
  var modelOwnedByRunner = false;
  try {
    if (runner.isCancelled) return;
    late Stream<String> stream;
    if (useAgent && pipeline.tools.isNotEmpty) {
      final inputMessage = _latestUserMessage(sanitizedMessages);
      if (inputMessage == null) {
        yield 'No user input provided';
        return;
      }

      final tools = pipeline.tools;

      final historyMessages = sanitizedMessages
          .sublist(0, sanitizedMessages.length - 1)
          .toList(growable: false);

      stream = runner.streamAgent(
        model: model,
        tools: tools,
        history: historyMessages,
        input: inputMessage,
        systemMessage: pipeline.systemMessage,
      );
    } else {
      // Disabling every tool must not disable AI chat itself. Keep the agent
      // guidance as a normal system message and fall back to direct chat.
      final directMessages = <ChatMessage>[
        if (useAgent && pipeline.systemMessage != null) pipeline.systemMessage!,
        ...sanitizedMessages,
      ];
      final prompt = PromptValue.chat(directMessages);
      stream = runner.stream(model: model, prompt: prompt);
    }

    modelOwnedByRunner = true;
    var buffer = '';
    await for (final chunk in stream) {
      buffer = chunk;
      yield buffer;
    }
    successful = !runner.isCancelled;
  } catch (error, stack) {
    final mapped = _mapError(error);
    AnxLog.severe('AI error: $mapped\n$stack');
    yield mapped;
  } finally {
    try {
      if (!modelOwnedByRunner) model.close();
    } catch (_) {}
    onFinished?.call(successful);
  }
}

String _notConfiguredMessage() {
  final context = navigatorKey.currentContext;
  return context == null
      ? 'AI service not configured'
      : L10n.of(context).aiServiceNotConfigured;
}

String _mapError(Object error) {
  final base = 'Error: ';

  if (error is TimeoutException) {
    return '${base}Request timed out';
  }

  if (error is SocketException) {
    return '${base}Network error: ${error.message}';
  }

  final message = error.toString().toLowerCase();

  if (message.contains('401') ||
      message.contains('unauthorized') ||
      message.contains('invalid api key')) {
    return '${base}Authentication failed. Please verify API key.';
  }

  if (message.contains('429') || message.contains('rate limit')) {
    return '${base}Rate limit reached. Try again later.';
  }

  if (message.contains('timeout')) {
    return '${base}Request timed out';
  }

  if (message.contains('network') ||
      message.contains('socket') ||
      message.contains('failed host lookup')) {
    return '${base}Network error: ${error.toString()}';
  }

  return '$base${error.toString()}';
}

List<ChatMessage> _sanitizeMessagesForPrompt(List<ChatMessage> messages) {
  return messages.map((message) {
    if (message is AIChatMessage) {
      if (message.reasoningContent.isNotEmpty) {
        return AIChatMessage(
          content: message.content,
          toolCalls: message.toolCalls,
        );
      }
      final plainText = reasoningContentToPlainText(message.content);
      if (plainText == message.content) {
        return message;
      }
      return AIChatMessage(
        content: plainText,
        toolCalls: message.toolCalls,
      );
    }
    return message;
  }).toList(growable: false);
}

String? _latestUserMessage(List<ChatMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    if (message is HumanChatMessage) {
      return message.contentAsString;
    }
  }
  return null;
}
