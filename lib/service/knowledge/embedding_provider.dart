import 'dart:convert';
import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:anx_reader/service/knowledge/onnx_embedding_provider.dart';
import 'package:http/http.dart' as http;

class VectorModelConfig {
  const VectorModelConfig({
    this.name = 'OpenAI Embeddings',
    this.modelId = 'text-embedding-3-small',
    this.endpoint = 'https://api.openai.com/v1/embeddings',
    this.apiKey = '',
    this.description = '',
    this.dimension,
  });

  final String name;
  final String modelId;
  final String endpoint;
  final String apiKey;
  final String description;
  final int? dimension;

  factory VectorModelConfig.fromJson(Map<String, dynamic> json) {
    final rawDimension = json['dimension'];
    return VectorModelConfig(
      name: json['name']?.toString() ?? 'OpenAI Embeddings',
      modelId: json['modelId']?.toString() ?? 'text-embedding-3-small',
      endpoint: json['endpoint']?.toString() ??
          'https://api.openai.com/v1/embeddings',
      apiKey: json['apiKey']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      dimension: rawDimension is int
          ? rawDimension
          : int.tryParse(rawDimension?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'modelId': modelId,
        'endpoint': endpoint,
        'apiKey': apiKey,
        'description': description,
        if (dimension != null) 'dimension': dimension,
      };
}

abstract class EmbeddingProvider {
  const EmbeddingProvider();

  String get modelId;

  String get mode;

  int? get configuredDimension;

  Future<List<List<double>>> embedBatch(List<String> inputs);

  void close() {}

  /// Awaitable teardown used before persistence to avoid model/JSON overlap.
  Future<void> release() async => close();

  Future<List<List<double>>> embedBatchCancellable(List<String> inputs,
      {bool Function()? isCancelled}) async {
    if (isCancelled?.call() ?? false) throw StateError('向量任务已取消');
    final cancelled = Completer<List<List<double>>>();
    final timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (isCancelled?.call() ?? false) {
        if (!cancelled.isCompleted) {
          cancelled.completeError(StateError('向量任务已取消'));
          close();
        }
      }
    });
    try {
      return await Future.any([embedBatch(inputs), cancelled.future]);
    } finally {
      timer.cancel();
    }
  }

  Future<List<double>> embed(String input) async {
    final result = await embedBatch([input]);
    if (result.length != 1) {
      throw const FormatException('Embedding response count mismatch');
    }
    return result.single;
  }
}

class OpenAiCompatibleEmbeddingProvider extends EmbeddingProvider {
  OpenAiCompatibleEmbeddingProvider({
    required this.config,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 45),
  }) : _client = client ?? http.Client();

  final VectorModelConfig config;
  final http.Client _client;
  final Duration requestTimeout;

  @override
  void close() => _client.close();

  @override
  int? get configuredDimension => config.dimension;

  @override
  String get mode => 'remote';

  @override
  String get modelId => config.modelId;

  @override
  Future<List<List<double>>> embedBatch(List<String> inputs) async {
    if (inputs.isEmpty) return const [];
    final endpoint = normalizeEmbeddingEndpoint(config.endpoint);
    if (config.modelId.trim().isEmpty) {
      throw StateError('向量模型 ID 不能为空');
    }
    if (config.apiKey.trim().isEmpty &&
        endpoint.host != 'localhost' &&
        endpoint.host != '127.0.0.1') {
      throw StateError('远程向量模型需要 API 密钥');
    }

    final response = await _client
        .post(
      endpoint,
      headers: {
        'Content-Type': 'application/json',
        if (config.apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${config.apiKey.trim()}',
      },
      body: jsonEncode({
        'model': config.modelId.trim(),
        'input': inputs,
      }),
    )
        .timeout(requestTimeout, onTimeout: () {
      close();
      throw TimeoutException('向量接口响应超时，请检查网络或服务商', requestTimeout);
    });
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        '向量接口请求失败 (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final rows = _embeddingRows(decoded);
    if (rows.length != inputs.length) {
      throw const FormatException('向量接口返回数量与输入数量不一致');
    }
    final vectors = rows.map((row) {
      final raw = row['embedding'];
      if (raw is! List) {
        throw const FormatException('向量接口缺少 embedding 字段');
      }
      return raw.map((value) {
        if (value is! num || !value.isFinite) {
          throw const FormatException('向量包含无效数值');
        }
        return value.toDouble();
      }).toList(growable: false);
    }).toList(growable: false);
    final dimension = vectors.first.length;
    if (dimension == 0 || vectors.any((vector) => vector.length != dimension)) {
      throw const FormatException('向量维度无效或不一致');
    }
    final expected = config.dimension;
    if (expected != null && expected > 0 && expected != dimension) {
      throw FormatException('向量维度不匹配：配置为 $expected，实际为 $dimension');
    }
    return vectors;
  }

  static List<Map<String, dynamic>> _embeddingRows(dynamic decoded) {
    if (decoded is! Map) {
      throw const FormatException('向量接口响应不是 JSON 对象');
    }
    final map = Map<String, dynamic>.from(decoded);
    final data = map['data'];
    if (data is List) {
      final rows = data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      rows.sort((left, right) {
        final a = (left['index'] as num?)?.toInt() ?? 0;
        final b = (right['index'] as num?)?.toInt() ?? 0;
        return a.compareTo(b);
      });
      return rows;
    }

    // Ollama's OpenAI-compatible embedding endpoint returns `embeddings`.
    final embeddings = map['embeddings'];
    if (embeddings is List) {
      return embeddings
          .map((embedding) => <String, dynamic>{'embedding': embedding})
          .toList(growable: false);
    }
    throw const FormatException('向量接口响应缺少 data 或 embeddings');
  }
}

Uri normalizeEmbeddingEndpoint(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    throw const FormatException('API 端点不能为空');
  }
  final parsed = Uri.parse(value);
  if (!parsed.hasScheme || parsed.host.isEmpty) {
    throw const FormatException('API 端点格式无效');
  }
  final path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.endsWith('/embeddings') || path.endsWith('/embed')) {
    return parsed.replace(path: path);
  }
  if (path.endsWith('/v1')) {
    return parsed.replace(path: '$path/embeddings');
  }
  return parsed.replace(path: '$path/v1/embeddings');
}

class EmbeddingProviderFactory {
  const EmbeddingProviderFactory._();

  static EmbeddingProvider? fromPrefs() {
    final prefs = Prefs();
    if (!prefs.vectorModelEnabled) return null;
    if (prefs.vectorModelMode == 'remote') {
      return OpenAiCompatibleEmbeddingProvider(
        config: VectorModelConfig.fromJson(prefs.vectorModelConfig),
      );
    }
    return LocalOnnxEmbeddingProvider(
      model: LocalEmbeddingModels.byId(prefs.vectorLocalModelId),
    );
  }
}
