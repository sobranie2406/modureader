import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/ai_reasoning_effort.dart';
import 'package:anx_reader/enums/lang_list.dart';
import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:anx_reader/service/ai/langchain_registry.dart';
import 'package:anx_reader/service/ai/reasoning_control_client.dart';
import 'package:anx_reader/service/config_transfer/settings_config_transfer.dart';
import 'package:anx_reader/service/translate/ai.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langchain_core/prompts.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _openAiEvents() => 'data: ${jsonEncode({
          'id': 'fixture',
          'object': 'chat.completion.chunk',
          'created': 1,
          'model': 'gpt-5.1',
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': '译文'},
              'finish_reason': 'stop',
            }
          ],
        })}\n\ndata: [DONE]\n\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  test('explicit off survives JSON, preferences and legacy config', () {
    const provider = AiProvider(
      id: 'fixture',
      title: 'Fixture',
      url: 'https://example.test/v1',
      protocol: AiProtocol.openai,
      reasoningEffort: AiReasoningEffort.none,
    );
    expect(provider.toJson()['reasoningEffort'], 'none');
    Prefs().saveAiProviders([provider]);
    final restored = AiProvider.fromJson(
        Map<String, dynamic>.from(Prefs().getAiProviders().single));
    expect(restored.reasoningEffort, AiReasoningEffort.none);
    final payload = AiConfigTransfer.createPayload(
      providers: [provider],
      selectedProviderId: provider.id,
      temperature: 0.4,
      maxTokens: 4096,
      contextTurns: 4,
      rpm: 0,
      translationProviderId: provider.id,
    );
    expect(
        AiConfigTransfer.parse(jsonDecode(jsonEncode(payload)))
            .providers
            .single
            .reasoningEffort,
        AiReasoningEffort.none);
    final old = provider.toJson()..remove('reasoningEffort');
    expect(AiProvider.fromJson(old).reasoningEffort, AiReasoningEffort.auto);
    expect(AiReasoningEffort.fromCode('unknown'), AiReasoningEffort.auto);
    final config =
        LangchainAiConfig.fromPrefs('fixture', {'reasoning_effort': 'none'});
    expect(config.reasoningEffort, AiReasoningEffort.none);
    expect(
        mergeConfigs(config.copyWith(reasoningEffort: AiReasoningEffort.high),
                config)
            .reasoningEffort,
        AiReasoningEffort.none);
  });

  final cases = [
    ('api.openai.com', 'gpt-5.1', 'reasoning_effort', 'none'),
    ('proxy.example.test', 'custom', 'reasoning_effort', 'none'),
    ('api.deepseek.com', 'deepseek-v4-flash', 'thinking', {'type': 'disabled'}),
    ('open.bigmodel.cn', 'glm-5', 'thinking', {'type': 'disabled'}),
    ('api.z.ai', 'glm-5', 'thinking', {'type': 'disabled'}),
    ('proxy.example.test', 'deepseek-chat', 'thinking', {'type': 'disabled'}),
    ('dashscope.aliyuncs.com', 'qwen-plus', 'enable_thinking', false),
    ('dashscope.aliyuncs.com', 'deepseek-r1', 'enable_thinking', false),
    ('proxy.example.test', 'Qwen/Qwen3-32B', 'enable_thinking', false),
    ('openrouter.ai', 'qwen/qwen3-32b', 'reasoning', {'enabled': false}),
  ];
  for (final (host, model, field, value) in cases) {
    test('off body for $host / $model replaces conflicting controls', () {
      final original = <String, dynamic>{
        'messages': [
          {'role': 'user', 'content': '测试'}
        ],
        'temperature': 0.4,
        'max_tokens': 512,
        'stream': true,
        'reasoning_effort': 'high',
        'reasoning': {'enabled': true},
        'thinking': {'type': 'enabled'},
        'enable_thinking': true,
      };
      final body = disableReasoning(original,
          protocol: AiProtocol.openai, host: host, model: model);
      expect(body[field], value);
      for (final other in [
        'reasoning_effort',
        'reasoning',
        'thinking',
        'enable_thinking'
      ]) {
        if (other != field) expect(body.containsKey(other), isFalse);
      }
      expect(body['messages'], original['messages']);
      expect(body['temperature'], 0.4);
      expect(body['max_tokens'], 512);
      expect(body['stream'], isTrue);
      expect(original['reasoning_effort'], 'high');
    });
  }

  test('Gemini Flash off preserves generation options without mutating source',
      () {
    final original = <String, dynamic>{
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 512,
        'thinkingConfig': {'thinkingBudget': 1024},
      }
    };
    for (final model in ['gemini-2.5-flash', 'gemini-2.5-flash-lite']) {
      final body = disableReasoning(original,
          protocol: AiProtocol.gemini,
          host: 'generativelanguage.googleapis.com',
          model: model);
      expect(body['generationConfig'], {
        'temperature': 0.4,
        'maxOutputTokens': 512,
        'thinkingConfig': {'thinkingBudget': 0},
      });
    }
    expect((original['generationConfig'] as Map)['thinkingConfig'],
        {'thinkingBudget': 1024});
  });

  for (final model in ['gemini-2.5-pro', 'gemini-3-pro-preview', 'unknown']) {
    test('$model cannot silently treat minimal reasoning as off', () {
      expect(
          () => disableReasoning({},
              protocol: AiProtocol.gemini, host: 'example.test', model: model),
          throwsUnsupportedError);
    });
  }

  for (final effort in AiReasoningEffort.values) {
    test('real OpenAI SDK stream serializes ${effort.code}', () async {
      late Map<String, dynamic> body;
      final model = LangchainAiRegistry(null,
              clientFactory: () => MockClient((request) async {
                    body = jsonDecode(utf8.decode(request.bodyBytes))
                        as Map<String, dynamic>;
                    expect(
                        request.headers['authorization'], 'Bearer fixture-key');
                    expect(request.headers['x-fixture'], 'preserved');
                    return http.Response(_openAiEvents(), 200, headers: {
                      'content-type': 'text/event-stream; charset=utf-8'
                    });
                  }))
          .resolveByProtocol(
              AiProtocol.openai,
              LangchainAiConfig(
                identifier: 'fixture',
                model: 'gpt-5.1',
                apiKey: 'fixture-key',
                temperature: 0.4,
                maxTokens: 512,
                reasoningEffort: effort,
                headers: {'x-fixture': 'preserved'},
              ))
          .model;
      addTearDown(model.close);
      final chunks = await model.stream(PromptValue.string('待翻译文字')).toList();
      expect(chunks.single.output.content, '译文');
      expect(body['reasoning_effort'],
          effort == AiReasoningEffort.auto ? null : effort.code);
      expect(body['temperature'], 0.4);
      expect(body['max_completion_tokens'], 512);
      expect(body['stream'], true);
      expect(jsonEncode(body['messages']), contains('待翻译文字'));
    });
  }

  for (final protocol in [AiProtocol.claude, AiProtocol.gemini]) {
    test('real ${protocol.code} SDK serializes explicit off', () async {
      late Map<String, dynamic> body;
      final isClaude = protocol == AiProtocol.claude;
      final model = LangchainAiRegistry(null,
              clientFactory: () => MockClient((request) async {
                    body = jsonDecode(utf8.decode(request.bodyBytes))
                        as Map<String, dynamic>;
                    return http.Response(
                        jsonEncode(isClaude
                            ? {
                                'id': 'fixture',
                                'type': 'message',
                                'role': 'assistant',
                                'model': 'claude-sonnet-4-6',
                                'content': [
                                  {'type': 'text', 'text': '译文'}
                                ],
                                'stop_reason': 'end_turn',
                                'usage': {
                                  'input_tokens': 5,
                                  'output_tokens': 2
                                },
                              }
                            : {
                                'candidates': [
                                  {
                                    'index': 0,
                                    'content': {
                                      'role': 'model',
                                      'parts': [
                                        {'text': '译文'}
                                      ]
                                    },
                                    'finishReason': 'STOP'
                                  }
                                ],
                                'usageMetadata': {
                                  'promptTokenCount': 5,
                                  'candidatesTokenCount': 2,
                                  'totalTokenCount': 7
                                },
                              }),
                        200,
                        headers: {
                          'content-type': 'application/json; charset=utf-8'
                        });
                  }))
          .resolveByProtocol(
              protocol,
              LangchainAiConfig(
                identifier: 'fixture',
                model: isClaude ? 'claude-sonnet-4-6' : 'gemini-2.5-flash',
                apiKey: 'fixture-key',
                maxTokens: 512,
                maxOutputTokens: 512,
                reasoningEffort: AiReasoningEffort.none,
              ))
          .model;
      addTearDown(model.close);
      final result = await model.invoke(PromptValue.string('待翻译文字'));
      expect(result.output.content, '译文');
      if (isClaude) {
        expect(body['thinking'], {'type': 'disabled'});
      } else {
        expect(
            body['generationConfig']['thinkingConfig'], {'thinkingBudget': 0});
        expect(body['generationConfig']['maxOutputTokens'], 512);
      }
    });
  }

  test('non-generation requests pass through untouched and close delegates',
      () async {
    final inner = _RecordingClient();
    final client = ReasoningControlClient(
        inner: inner, protocol: AiProtocol.openai, model: 'gpt-5.1');
    for (final request in [
      http.Request('GET', Uri.parse('https://example.test/v1/models')),
      http.Request('POST', Uri.parse('https://example.test/v1/embeddings'))
        ..body = 'unchanged',
    ]) {
      await client.send(request);
      expect(identical(inner.last, request), isTrue);
    }
    client.close();
    expect(inner.closed, isTrue);
  });

  test(
      'full-text translation uses its selected provider off setting, not chat default',
      () async {
    final oldOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = oldOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <Map<String, dynamic>>[];
    server.listen((request) async {
      requests.add(jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write(_openAiEvents());
      await request.response.close();
    });
    final translationProvider = AiProvider(
      id: 'translator-fixture',
      title: 'Translator fixture',
      url: 'http://127.0.0.1:${server.port}/v1/chat/completions',
      protocol: AiProtocol.openai,
      model: 'gpt-5.1',
      reasoningEffort: AiReasoningEffort.none,
      temperature: 0.3,
      maxTokens: 2048,
      apiKeys: [AiApiKey(id: 'fixture', key: 'fixture-key')],
    );
    Prefs().saveAiProviders([
      translationProvider.copyWith(
          id: 'chat-fixture', reasoningEffort: AiReasoningEffort.high),
      translationProvider,
    ]);
    Prefs().selectedAiService = 'chat-fixture';
    Prefs().translationAiService = translationProvider.id;
    final result = await AiTranslateProvider()
        .translateStream('Synthetic book text.', LangListEnum.english,
            LangListEnum.simplifiedChinese,
            isFullText: true)
        .toList()
        .timeout(const Duration(seconds: 10));
    expect(result.last, '译文');
    expect(requests, hasLength(1));
    expect(requests.single['reasoning_effort'], 'none');
    expect(requests.single['temperature'], 0.3);
    expect(requests.single['max_completion_tokens'], 2048);
    expect(jsonEncode(requests.single['messages']),
        contains('Synthetic book text.'));
  });
}

class _RecordingClient extends http.BaseClient {
  http.BaseRequest? last;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    last = request;
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }

  @override
  void close() => closed = true;
}
