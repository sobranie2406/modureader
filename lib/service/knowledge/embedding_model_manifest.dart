import 'dart:convert';

import 'package:flutter/services.dart';

enum EmbeddingDownloadSource { huggingFace, gitee }

/// Mirror assets are immutable per pinned upstream revision. Large files use
/// 64 MiB parts; the assembled file MUST match the original SHA-256.
const embeddingMirrorBase =
    'https://gitee.com/sobranie2406/modu-models/releases/download/models-v1';
const embeddingMirrorPartSize = 64 * 1024 * 1024;

/// Pinned integrity metadata for on-demand model downloads.
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
        mirrorName: '$id-$revision-$name',
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
      required this.uri,
      this.mirrorName});
  final String name;
  final int size;
  final String sha256;
  final Uri uri;
  final String? mirrorName;

  List<({Uri uri, int size})> downloads(EmbeddingDownloadSource source) {
    if (source == EmbeddingDownloadSource.huggingFace) {
      return [(uri: uri, size: size)];
    }
    final name = mirrorName;
    if (name == null || !RegExp(r'^[\w.-]+$').hasMatch(name)) {
      throw const FormatException('模型镜像元数据不完整');
    }
    final count = (size / embeddingMirrorPartSize).ceil();
    return [
      for (var i = 0; i < count; i++)
        (
          uri: Uri.parse(
              '$embeddingMirrorBase/$name${count == 1 ? '' : '.part-${(i + 1).toString().padLeft(2, '0')}'}'),
          size: i == count - 1
              ? size - i * embeddingMirrorPartSize
              : embeddingMirrorPartSize
        ),
    ];
  }
}
