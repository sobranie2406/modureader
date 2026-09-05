import 'dart:convert';

import 'package:anx_reader/models/ai_provider.dart';
import 'package:http/http.dart' as http;

/// Fetches the list of available model IDs from an OpenAI-compatible /models endpoint.
///
/// Returns a sorted list of model ID strings on success, or throws an exception
/// with a descriptive message on failure.
Future<List<String>> fetchAiModels({
  required String url,
  required String apiKey,
  AiProtocol protocol = AiProtocol.openai,
  Duration timeout = const Duration(seconds: 10),
  http.Client? client,
}) async {
  final request = buildAiModelsRequest(
    url: url,
    apiKey: apiKey,
    protocol: protocol,
  );
  final ownedClient = client == null ? http.Client() : null;
  final activeClient = client ?? ownedClient!;
  late http.Response response;
  try {
    response = await activeClient
        .get(
          request.uri,
          headers: request.headers,
        )
        .timeout(timeout);
  } finally {
    ownedClient?.close();
  }

  if (response.statusCode != 200) {
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  final data = jsonDecode(response.body);
  if (data is! Map) {
    throw const FormatException('模型列表响应格式无效');
  }
  final rawModels = data['data'] ?? data['models'];
  final models = rawModels is List ? rawModels : const <dynamic>[];

  if (models.isEmpty) {
    return [];
  }

  final ids = models
      .map(_readModelId)
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList();
  ids.sort();
  return ids;
}

class AiModelsRequest {
  const AiModelsRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

/// Builds the provider-specific model catalog request without performing I/O.
/// Keeping this separate makes the settings behavior testable without API keys.
AiModelsRequest buildAiModelsRequest({
  required String url,
  required String apiKey,
  required AiProtocol protocol,
}) {
  final endpoint = Uri.tryParse(url.trim());
  if (endpoint == null ||
      !endpoint.hasScheme ||
      endpoint.host.isEmpty ||
      (endpoint.scheme != 'http' && endpoint.scheme != 'https')) {
    throw const FormatException('AI 服务地址无效');
  }

  return switch (protocol) {
    AiProtocol.openai => AiModelsRequest(
        uri: _modelsUri(endpoint, defaultVersion: 'v1'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ),
    AiProtocol.claude => AiModelsRequest(
        uri: _modelsUri(endpoint, defaultVersion: 'v1'),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Accept': 'application/json',
        },
      ),
    AiProtocol.gemini => AiModelsRequest(
        uri: _geminiModelsUri(endpoint),
        headers: {
          'x-goog-api-key': apiKey,
          'Accept': 'application/json',
        },
      ),
  };
}

Uri _modelsUri(Uri endpoint, {required String defaultVersion}) {
  final segments =
      endpoint.pathSegments.where((part) => part.isNotEmpty).toList();
  final endpointMarkers = {
    'chat',
    'completions',
    'responses',
    'messages',
    'models'
  };
  while (segments.isNotEmpty &&
      endpointMarkers.contains(segments.last.toLowerCase())) {
    segments.removeLast();
  }
  if (segments.isEmpty) segments.add(defaultVersion);
  segments.add('models');
  return endpoint.replace(pathSegments: segments, query: null, fragment: null);
}

Uri _geminiModelsUri(Uri endpoint) {
  final segments =
      endpoint.pathSegments.where((part) => part.isNotEmpty).toList();
  final versionIndex = segments.indexWhere(
    (part) => RegExp(r'^v\d+(?:beta\d*)?$').hasMatch(part.toLowerCase()),
  );
  final version = versionIndex >= 0 ? segments[versionIndex] : 'v1beta';
  return endpoint.replace(
    pathSegments: [version, 'models'],
    query: null,
    fragment: null,
  );
}

String? _readModelId(dynamic model) {
  if (model is String) return model;
  if (model is! Map) return null;
  final raw = model['id'] ?? model['name'];
  if (raw == null) return null;
  final id = raw.toString();
  return id.startsWith('models/') ? id.substring('models/'.length) : id;
}
