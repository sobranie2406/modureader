import 'dart:convert';

import 'package:anx_reader/models/ai_provider.dart';
import 'package:http/http.dart' as http;

/// Explicit opt-out for SDKs which cannot serialize provider thinking fields.
/// Only JSON generation requests are changed; streamed responses are forwarded
/// untouched, so this disables server work rather than hiding reasoning text.
class ReasoningControlClient extends http.BaseClient {
  ReasoningControlClient({
    required this.inner,
    required this.protocol,
    required this.model,
  });

  final http.Client inner;
  final AiProtocol protocol;
  final String model;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    final isGeneration = switch (protocol) {
      AiProtocol.openai => path.endsWith('/chat/completions'),
      AiProtocol.claude => path.endsWith('/messages'),
      AiProtocol.gemini => path.endsWith(':generateContent') ||
          path.endsWith(':streamGenerateContent'),
    };
    if (request.method != 'POST' || !isGeneration) {
      return inner.send(request);
    }
    final body = jsonDecode(utf8.decode(await request.finalize().toBytes()))
        as Map<String, dynamic>;
    final updated = disableReasoning(
      body,
      protocol: protocol,
      host: request.url.host,
      model: model,
    );
    final replacement = http.Request(request.method, request.url)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..headers.addAll(request.headers);
    replacement.headers.remove('content-length');
    replacement.bodyBytes = utf8.encode(jsonEncode(updated));
    return inner.send(replacement);
  }

  @override
  void close() => inner.close();
}

Map<String, dynamic> disableReasoning(
  Map<String, dynamic> original, {
  required AiProtocol protocol,
  required String host,
  required String model,
}) {
  final body = Map<String, dynamic>.from(original);
  final name = model.trim().toLowerCase().split('/').last;
  final hostname = host.toLowerCase();
  bool domain(String value) =>
      hostname == value || hostname.endsWith('.$value');

  if (protocol == AiProtocol.gemini) {
    // Pro and Gemini 3 cannot be truthfully labelled "off" using budget=0.
    // Add new supported families only after checking the provider contract.
    if (!name.startsWith('gemini-2.5-flash')) {
      throw UnsupportedError(
        '此 Gemini 模型未确认支持关闭推理；请选择自动或 Gemini 2.5 Flash / '
        'Off is supported here only for Gemini 2.5 Flash/Flash-Lite.',
      );
    }
    final generation =
        Map<String, dynamic>.from(body['generationConfig'] as Map? ?? {});
    generation['thinkingConfig'] = {'thinkingBudget': 0};
    body['generationConfig'] = generation;
    return body;
  }

  // Never combine mutually conflicting enable/effort/budget controls.
  body.remove('reasoning_effort');
  body.remove('reasoning');
  body.remove('thinking');
  body.remove('enable_thinking');
  if (protocol == AiProtocol.claude) {
    body['thinking'] = {'type': 'disabled'};
  } else if (domain('openrouter.ai')) {
    body['reasoning'] = {'enabled': false};
  } else if (domain('aliyuncs.com') || name.startsWith('qwen')) {
    // DashScope uses its own field even when serving a DeepSeek model.
    body['enable_thinking'] = false;
  } else if (domain('deepseek.com') ||
      domain('bigmodel.cn') ||
      domain('z.ai') ||
      name.startsWith('deepseek') ||
      name.startsWith('glm-')) {
    body['thinking'] = {'type': 'disabled'};
  } else {
    // Standard OpenAI-compatible contract; unsupported providers may reject
    // this explicit opt-out. Do not silently retry with reasoning enabled.
    body['reasoning_effort'] = 'none';
  }
  return body;
}
