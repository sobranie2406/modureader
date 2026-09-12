import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// Reads only packaged assets; integrity is checked by LocalEmbeddingModelStore.
class BundledEmbeddingAssets {
  BundledEmbeddingAssets({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle,
        _useFileAssets = bundle == null;

  final AssetBundle _bundle;
  final bool _useFileAssets;
  Future<Set<String>>? _keys;
  static const assetRoot = 'assets/models/embeddings';

  Future<bool> contains(String id) async {
    final keys = await (_keys ??= () async {
      final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
      return manifest.listAssets().toSet();
    }());
    return keys.contains('$assetRoot/$id/model_quantized.onnx') &&
        keys.contains('$assetRoot/$id/tokenizer.json');
  }

  Future<void> copyFile(String id, String name, File destination) async {
    final key = '$assetRoot/$id/$name';
    // Desktop assets are real files. Stream them instead of loading a whole
    // E5 model into the Dart/UI heap before starting native inference.
    if (_useFileAssets &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final executableDirectory = path.dirname(Platform.resolvedExecutable);
      final root = Platform.isMacOS
          ? path.normalize(path.join(executableDirectory,
              '../Frameworks/App.framework/Resources/flutter_assets'))
          : path.join(executableDirectory, 'data', 'flutter_assets');
      final source = File(path.join(root, key));
      if (await source.exists()) {
        final sink = destination.openWrite();
        try {
          await sink.addStream(source.openRead());
          await sink.flush();
        } finally {
          await sink.close();
        }
        return;
      }
    }
    final data = await _bundle.load(key);
    await destination.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true);
  }
}
