import 'dart:convert';

import 'package:anx_reader/models/ai_provider.dart';
import 'package:anx_reader/service/ai/langchain_ai_config.dart';
import 'package:anx_reader/service/ai/ai_model_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('AI model catalog requests', () {
    test('uses the temperature required by current Kimi models', () {
      expect(normalizeAiTemperatureForModel('kimi-k2.5', 0.7), 1.0);
      expect(normalizeAiTemperatureForModel('kimi-k2.6', 0.7), 1.0);
      expect(normalizeAiTemperatureForModel('kimi-k3', 0.7), 1.0);
      expect(normalizeAiTemperatureForModel('gpt-4o-mini', 0.7), 0.7);
    });

    test('derives OpenAI-compatible models URL from a chat endpoint', () {
      final request = buildAiModelsRequest(
        url: 'https://openrouter.ai/api/v1/chat/completions',
        apiKey: 'secret',
        protocol: AiProtocol.openai,
      );

      expect(request.uri.toString(), 'https://openrouter.ai/api/v1/models');
      expect(request.headers['Authorization'], 'Bearer secret');
    });

    test('uses Anthropic model endpoint and required headers', () {
      final request = buildAiModelsRequest(
        url: 'https://api.anthropic.com/v1/messages',
        apiKey: 'secret',
        protocol: AiProtocol.claude,
      );

      expect(request.uri.toString(), 'https://api.anthropic.com/v1/models');
      expect(request.headers['x-api-key'], 'secret');
      expect(request.headers['anthropic-version'], '2023-06-01');
      expect(request.headers, isNot(contains('Authorization')));
    });

    test('uses Gemini v1beta model endpoint and Google API key header', () {
      final request = buildAiModelsRequest(
        url: 'https://generativelanguage.googleapis.com',
        apiKey: 'secret',
        protocol: AiProtocol.gemini,
      );

      expect(
        request.uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models',
      );
      expect(request.headers['x-goog-api-key'], 'secret');
    });

    test('parses OpenAI and Gemini response shapes', () async {
      final responses = <String>[
        jsonEncode({
          'data': [
            {'id': 'model-b'},
            {'id': 'model-a'},
          ],
        }),
        jsonEncode({
          'models': [
            {'name': 'models/gemini-2.5-flash'},
          ],
        }),
      ];
      final client = MockClient(
        (_) async => http.Response(responses.removeAt(0), 200),
      );

      expect(
        await fetchAiModels(
          url: 'https://api.openai.com/v1/chat/completions',
          apiKey: 'secret',
          protocol: AiProtocol.openai,
          client: client,
        ),
        ['model-a', 'model-b'],
      );
      expect(
        await fetchAiModels(
          url: 'https://generativelanguage.googleapis.com',
          apiKey: 'secret',
          protocol: AiProtocol.gemini,
          client: client,
        ),
        ['gemini-2.5-flash'],
      );
    });

    test('rejects invalid provider URLs before making a request', () {
      expect(
        () => buildAiModelsRequest(
          url: 'api.example.com/v1',
          apiKey: 'secret',
          protocol: AiProtocol.openai,
        ),
        throwsFormatException,
      );
    });
  });
}
