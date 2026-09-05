import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

typedef ModelDownloadProgress = void Function(double progress);

class LocalEmbeddingModel {
  const LocalEmbeddingModel({
    required this.id,
    required this.hfModelId,
    required this.name,
    required this.sizeLabel,
    required this.dimensions,
    required this.languages,
    required this.description,
    this.recommended = false,
  });

  final String id;
  final String hfModelId;
  final String name;
  final String sizeLabel;
  final int dimensions;
  final String languages;
  final String description;
  final bool recommended;

  Uri get modelUri => Uri.parse(
        'https://huggingface.co/$hfModelId/resolve/main/onnx/model_quantized.onnx',
      );

  Uri get tokenizerUri => Uri.parse(
        'https://huggingface.co/$hfModelId/resolve/main/tokenizer.json',
      );
}

class LocalEmbeddingModels {
  const LocalEmbeddingModels._();

  static const String defaultModelId = 'all-MiniLM-L6-v2';

  /// The four local embedding models shipped by ReadAny's model catalogue.
  static const List<LocalEmbeddingModel> all = [
    LocalEmbeddingModel(
      id: 'all-MiniLM-L6-v2',
      hfModelId: 'Xenova/all-MiniLM-L6-v2',
      name: 'all-MiniLM-L6-v2',
      sizeLabel: '~23 MB',
      dimensions: 384,
      languages: 'English',
      description: 'Small and fast English sentence embedding model.',
      recommended: true,
    ),
    LocalEmbeddingModel(
      id: 'bge-small-en-v1.5',
      hfModelId: 'Xenova/bge-small-en-v1.5',
      name: 'BGE Small EN v1.5',
      sizeLabel: '~33 MB',
      dimensions: 384,
      languages: 'English',
      description: 'English retrieval model with strong semantic matching.',
    ),
    LocalEmbeddingModel(
      id: 'bge-small-zh-v1.5',
      hfModelId: 'Xenova/bge-small-zh-v1.5',
      name: 'BGE Small ZH v1.5',
      sizeLabel: '~24 MB',
      dimensions: 512,
      languages: '中文',
      description: '针对中文语义检索优化的轻量向量模型。',
    ),
    LocalEmbeddingModel(
      id: 'multilingual-e5-small',
      hfModelId: 'Xenova/multilingual-e5-small',
      name: 'Multilingual E5 Small',
      sizeLabel: '~118 MB',
      dimensions: 384,
      languages: 'Multilingual',
      description: 'Multilingual retrieval for Chinese, English, and more.',
    ),
  ];

  static LocalEmbeddingModel byId(String? id) {
    return all.firstWhere(
      (model) => model.id == id,
      orElse: () => all.first,
    );
  }
}

class LocalEmbeddingModelStore {
  LocalEmbeddingModelStore({
    Directory? rootDirectory,
    http.Client? client,
    this.minimumModelBytes = 1024 * 1024,
    this.minimumTokenizerBytes = 128,
  })  : _rootDirectory = rootDirectory,
        _client = client ?? http.Client();

  final Directory? _rootDirectory;
  final http.Client _client;
  final int minimumModelBytes;
  final int minimumTokenizerBytes;

  Future<Directory> get rootDirectory async {
    if (_rootDirectory != null) return _rootDirectory;
    final appDirectory = await getAnxDocumentDir();
    return Directory(path.join(
      appDirectory.path,
      'models',
      'embeddings',
    ));
  }

  Future<Directory> modelDirectory(LocalEmbeddingModel model) async {
    return Directory(path.join((await rootDirectory).path, model.id));
  }

  Future<File> modelFile(LocalEmbeddingModel model) async {
    return File(path.join(
      (await modelDirectory(model)).path,
      'model_quantized.onnx',
    ));
  }

  Future<File> tokenizerFile(LocalEmbeddingModel model) async {
    return File(path.join(
      (await modelDirectory(model)).path,
      'tokenizer.json',
    ));
  }

  Future<bool> isDownloaded(LocalEmbeddingModel model) async {
    final onnx = await modelFile(model);
    final tokenizer = await tokenizerFile(model);
    if (!await onnx.exists() || !await tokenizer.exists()) return false;
    if (await onnx.length() < minimumModelBytes ||
        await tokenizer.length() < minimumTokenizerBytes) {
      return false;
    }
    try {
      final decoded = jsonDecode(await tokenizer.readAsString());
      return decoded is Map && decoded['model'] is Map;
    } catch (_) {
      return false;
    }
  }

  Future<void> download(
    LocalEmbeddingModel model, {
    ModelDownloadProgress? onProgress,
  }) async {
    final directory = await modelDirectory(model);
    await directory.create(recursive: true);
    final downloads = <({Uri uri, File destination})>[
      (uri: model.modelUri, destination: await modelFile(model)),
      (uri: model.tokenizerUri, destination: await tokenizerFile(model)),
    ];

    try {
      for (var index = 0; index < downloads.length; index++) {
        final item = downloads[index];
        await _downloadFile(
          item.uri,
          item.destination,
          onProgress: (fileProgress) {
            onProgress?.call((index + fileProgress) / downloads.length);
          },
        );
      }
      if (!await isDownloaded(model)) {
        throw const FormatException('下载的模型文件不完整或 tokenizer 无效');
      }
      onProgress?.call(1);
    } catch (_) {
      await _deleteIfExists(File('${(await modelFile(model)).path}.part'));
      await _deleteIfExists(File('${(await tokenizerFile(model)).path}.part'));
      rethrow;
    }
  }

  Future<void> _downloadFile(
    Uri uri,
    File destination, {
    required ModelDownloadProgress onProgress,
  }) async {
    final temporary = File('${destination.path}.part');
    await _deleteIfExists(temporary);
    final response = await _client.send(http.Request('GET', uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '模型下载失败 (${response.statusCode})',
        uri: uri,
      );
    }

    final sink = temporary.openWrite();
    var received = 0;
    try {
      await for (final bytes in response.stream) {
        sink.add(bytes);
        received += bytes.length;
        if (response.contentLength != null && response.contentLength! > 0) {
          onProgress((received / response.contentLength!).clamp(0, 1));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (await temporary.length() == 0) {
      await _deleteIfExists(temporary);
      throw HttpException('模型下载结果为空', uri: uri);
    }
    await _deleteIfExists(destination);
    await temporary.rename(destination.path);
    onProgress(1);
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }

  void close() => _client.close();
}
