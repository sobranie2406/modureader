import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// Lazily materialize app assets for native APIs. Never contacts the network.
class BundledEmbeddingAssets {
  BundledEmbeddingAssets({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;
  static const assetRoot = 'assets/models/embeddings';
  final AssetBundle _bundle;
  Future<Map<String, dynamic>>? _manifest;
  static final Map<String, Future<void>> _pending = {};

  Future<Map<String, dynamic>> _loadManifest() => _manifest ??= () async {
        try {
          return Map<String, dynamic>.from(
              jsonDecode(await _bundle.loadString('$assetRoot/manifest.json'))
                  as Map);
        } on FlutterError {
          return <String, dynamic>{};
        }
      }();

  Future<Map<String, dynamic>?> _model(String id) async {
    final models = (await _loadManifest())['models'];
    if (models is! List) return null;
    for (final model in models) {
      if (model is Map && model['id'] == id) {
        return Map<String, dynamic>.from(model);
      }
    }
    return null;
  }

  Future<bool> contains(String id) async => await _model(id) != null;

  Future<void> materialize(String id, Directory destination) async {
    final key = '${destination.absolute.path}:$id';
    final pending = _pending[key];
    if (pending != null) return pending;
    final operation = _materialize(id, destination);
    _pending[key] = operation;
    try {
      await operation;
    } finally {
      _pending.remove(key);
    }
  }

  Future<void> _materialize(String id, Directory destination) async {
    final model = await _model(id);
    if (model == null) throw StateError('安装包缺少本地模型 $id');
    await destination.create(recursive: true);
    for (final item in model['files'] as List) {
      final name = item['name'] as String;
      if (path.basename(name) != name ||
          !const ['model_quantized.onnx', 'tokenizer.json'].contains(name)) {
        throw const FormatException('Invalid bundled model filename');
      }
      final expectedHash = item['sha256'] as String;
      final expectedSize = item['size'] as int;
      final file = File(path.join(destination.path, name));
      if (await file.exists() &&
          await file.length() == expectedSize &&
          (await sha256.bind(file.openRead()).first).toString() ==
              expectedHash) {
        continue;
      }
      final data = await _bundle.load('$assetRoot/$id/$name');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.length != expectedSize ||
          sha256.convert(bytes).toString() != expectedHash) {
        throw StateError('内嵌模型 $id 文件校验失败，请重新安装完整安装包');
      }
      final temporary = File('${file.path}.bundled.part');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
  }
}
