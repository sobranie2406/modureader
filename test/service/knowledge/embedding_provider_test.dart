import 'dart:convert';

import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('embedding endpoint normalization', () {
    test('accepts API root, v1 base, and full endpoint', () {
      expect(
        normalizeEmbeddingEndpoint('https://example.com').toString(),
        'https://example.com/v1/embeddings',
      );
      expect(
        normalizeEmbeddingEndpoint('https://example.com/v1').toString(),
        'https://example.com/v1/embeddings',
      );
      expect(
        normalizeEmbeddingEndpoint(
          'https://example.com/custom/embeddings',
        ).toString(),
        'https://example.com/custom/embeddings',
      );
    });
  });

  test('remote provider orders OpenAI embeddings by index', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://example.com/v1/embeddings');
      expect(request.headers['authorization'], 'Bearer secret');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'embedding-model');
      expect(body['input'], ['first', 'second']);
      return http.Response(
        jsonEncode({
          'data': [
            {
              'index': 1,
              'embedding': [0.0, 1.0],
            },
            {
              'index': 0,
              'embedding': [1.0, 0.0],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final provider = OpenAiCompatibleEmbeddingProvider(
      config: const VectorModelConfig(
        endpoint: 'https://example.com',
        apiKey: 'secret',
        modelId: 'embedding-model',
        dimension: 2,
      ),
      client: client,
    );

    expect(
      await provider.embedBatch(['first', 'second']),
      [
        [1.0, 0.0],
        [0.0, 1.0],
      ],
    );
  });

  test('remote provider accepts Ollama embeddings response', () async {
    final provider = OpenAiCompatibleEmbeddingProvider(
      config: const VectorModelConfig(
        endpoint: 'http://localhost:11434/api/embed',
        modelId: 'nomic-embed-text',
      ),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'embeddings': [
                [0.1, 0.2, 0.3],
              ],
            }),
            200,
          )),
    );

    expect(await provider.embed('hello'), [0.1, 0.2, 0.3]);
  });
}
