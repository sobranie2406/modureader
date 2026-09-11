import 'dart:convert';

import 'package:flutter/services.dart';

/// Small, bundled catalogue only. Model weights are downloaded explicitly.
class EmbeddingModelManifest {
  EmbeddingModelManifest({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  Future<Map<String, dynamic>>? _manifest;
  static const assetPath = 'assets/models/embeddings/manifest.json';

  Future<List<EmbeddingModelFile>> files(String id) async {
    final manifest = await (_manifest ??= () async {
      return Map<String, dynamic>.from(
        jsonDecode(await _bundle.loadString(assetPath)) as Map,
      );
    }());
    final models = manifest['models'] as List;
    final model = models.cast<Map>().singleWhere((item) => item['id'] == id);
    final repository = model['repository'] as String;
    final revision = model['revision'] as String;
    if (!RegExp(r'^[\w-]+/[\w.-]+$').hasMatch(repository) ||
        !RegExp(r'^[a-f0-9]{40}$').hasMatch(revision)) {
      throw const FormatException('Invalid pinned model source');
    }
    final files = (model['files'] as List).cast<Map>().map((item) {
      final name = item['name'] as String;
      final remotePath = item['path'] as String;
      final size = item['size'] as int;
      final hash = item['sha256'] as String;
      final expectedPath = switch (name) {
        'model_quantized.onnx' => 'onnx/model_quantized.onnx',
        'tokenizer.json' => 'tokenizer.json',
        _ => throw const FormatException('Invalid model filename'),
      };
      if (remotePath != expectedPath ||
          size <= 0 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        throw const FormatException('Invalid model integrity metadata');
      }
      return EmbeddingModelFile(
        name: name,
        size: size,
        sha256: hash,
        uri: Uri.parse(
            'https://huggingface.co/$repository/resolve/$revision/$remotePath'),
      );
    }).toList(growable: false);
    if (files.length != 2 ||
        files.map((file) => file.name).toSet().length != 2) {
      throw const FormatException('Incomplete model manifest');
    }
    return files;
  }
}

class EmbeddingModelFile {
  const EmbeddingModelFile(
      {required this.name,
      required this.size,
      required this.sha256,
      required this.uri});
  final String name;
  final int size;
  final String sha256;
  final Uri uri;
}
