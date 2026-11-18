import 'dart:async';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/models/book.dart';
import 'package:modu_reader/service/knowledge/book_embedding_preferences.dart';
import 'package:modu_reader/service/knowledge/local_embedding_models.dart';
import 'package:modu_reader/service/knowledge/onnx_embedding_provider.dart';

abstract class EmbeddingProvider {
  const EmbeddingProvider();

  String get modelId;

  String get mode;

  int? get configuredDimension;

  /// Validate local prerequisites without making a network request.
  Future<void> ensureReady() async {}

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

/// Equal dimensions alone do not make vectors from different models compatible.
bool matchesEmbeddingIndex(
  EmbeddingProvider provider, {
  required String? mode,
  required String? modelId,
  required int? dimensions,
}) =>
    modelId != null &&
    modelId == provider.modelId &&
    mode == provider.mode &&
    (dimensions == null ||
        provider.configuredDimension == null ||
        dimensions == provider.configuredDimension);

class EmbeddingProviderFactory {
  const EmbeddingProviderFactory._();

  static void requireEnabled() {
    if (!Prefs().vectorModelEnabled) {
      throw StateError('向量模型未启用，请前往「设置 → 离线本地模型设置 → 向量模型」开启后再向量化');
    }
  }

  /// Bookshelf vectorization must not silently become a lexical-only index.
  /// Nullable providers remain supported for ordinary keyword retrieval.
  static LocalOnnxEmbeddingProvider requireForBook(Book book) {
    requireEnabled();
    if (!LocalOnnxEmbeddingProvider.isSupported) {
      throw StateError(LocalOnnxEmbeddingProvider.unsupportedMessage);
    }
    return fromBook(book)!;
  }

  /// Read-only preflight: no inference, model download, or shared-engine
  /// release (another queued book may currently be using that engine).
  static Future<void> validateForBook(Book book) async {
    final provider = requireForBook(book);
    try {
      if (!await provider.store.isDownloaded(provider.model)) {
        throw StateError(
          '本地模型 ${provider.model.name} 尚未下载或文件损坏，请前往「设置 → 离线本地模型设置 → 向量模型」下载后重试',
        );
      }
      // The user may turn the switch off during an asynchronous file check.
      requireEnabled();
    } finally {
      provider.close();
    }
  }

  static LocalOnnxEmbeddingProvider? fromBook(Book book) {
    if (!Prefs().vectorModelEnabled ||
        !LocalOnnxEmbeddingProvider.isSupported) {
      return null;
    }
    final choice = BookEmbeddingPreferences.choiceFor(book);
    if (choice == null) return fromPrefs();
    if (!BookEmbeddingPreferences.isValid(choice)) {
      throw StateError('本书的向量模型不可用，请在书籍菜单中重新选择');
    }
    return LocalOnnxEmbeddingProvider(
      model: LocalEmbeddingModels.byId(choice.substring('local:'.length)),
    );
  }

  static LocalOnnxEmbeddingProvider? fromPrefs() {
    final prefs = Prefs();
    if (!prefs.vectorModelEnabled || !LocalOnnxEmbeddingProvider.isSupported) {
      return null;
    }
    return LocalOnnxEmbeddingProvider(
      model: LocalEmbeddingModels.byId(prefs.vectorLocalModelId),
    );
  }
}
