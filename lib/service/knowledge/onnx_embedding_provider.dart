import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anx_reader/service/knowledge/embedding_provider.dart';
import 'package:anx_reader/service/knowledge/android_embedding_bridge.dart';
import 'package:anx_reader/service/knowledge/local_embedding_models.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:hf_tokenizers/hf_tokenizers.dart';

class LocalOnnxEmbeddingProvider extends EmbeddingProvider {
  LocalOnnxEmbeddingProvider({
    required this.model,
    LocalEmbeddingModelStore? store,
    LocalOnnxEmbeddingEngine? engine,
  })  : store = store ?? LocalEmbeddingModelStore(),
        _engine = engine ?? LocalOnnxEmbeddingEngine.instance;

  final LocalEmbeddingModel model;
  final LocalEmbeddingModelStore store;
  final LocalOnnxEmbeddingEngine _engine;

  @override
  int get configuredDimension => model.dimensions;

  @override
  String get mode => 'builtin';

  @override
  String get modelId => model.id;

  @override
  Future<void> release() => _engine.release();

  @override
  Future<List<List<double>>> embedBatch(List<String> inputs) =>
      embedBatchCancellable(inputs);

  @override
  Future<List<List<double>>> embedBatchCancellable(List<String> inputs,
      {bool Function()? isCancelled}) async {
    if (inputs.isEmpty) return const [];
    if (!await store.isDownloaded(model)) {
      throw StateError('本地模型 ${model.name} 尚未下载，请先在设置中下载');
    }
    return _engine.generate(model, inputs, store, isCancelled: isCancelled);
  }
}

class LocalOnnxEmbeddingEngine {
  LocalOnnxEmbeddingEngine._();

  static final LocalOnnxEmbeddingEngine instance = LocalOnnxEmbeddingEngine._();

  String? _activeModelId;
  OrtSession? _session;
  Tokenizer? _tokenizer;
  final _android = const AndroidEmbeddingBridge();
  Timer? _idleRelease;
  Future<void> _tail = Future<void>.value();

  Future<List<List<double>>> generate(
    LocalEmbeddingModel model,
    List<String> inputs,
    LocalEmbeddingModelStore store, {
    bool Function()? isCancelled,
  }) {
    return _exclusive(() async {
      _idleRelease?.cancel();
      try {
        if (isCancelled?.call() ?? false) throw StateError('向量任务已取消');
        await _load(model, store);
        final vectors = <List<double>>[];
        for (final input in inputs) {
          // Native inference finishes first; never abandon an entire batch on
          // the shared session after reporting that the queue has stopped.
          if (isCancelled?.call() ?? false) throw StateError('向量任务已取消');
          vectors.add(await _generateOne(model, input));
        }
        return vectors;
      } catch (_) {
        // Preserve the inference/cancellation error if teardown also fails.
        try {
          await _closeActiveModel();
        } catch (_) {}
        rethrow;
      } finally {
        // A finished/cancelled book must not keep model weights resident while
        // the user reads. Cleanup shares the inference lock, never races a run.
        if (Platform.isAndroid) {
          _idleRelease = Timer(const Duration(seconds: 15), () {
            // Engine teardown can remove the channel while this timer fires.
            unawaited(release().catchError((Object _) {}));
          });
        }
      }
    });
  }

  Future<void> release() => _exclusive(_closeActiveModel);

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  Future<void> _load(
    LocalEmbeddingModel model,
    LocalEmbeddingModelStore store,
  ) async {
    if (_activeModelId == model.id &&
        (Platform.isAndroid || _session != null) &&
        _tokenizer != null) {
      return;
    }
    await _closeActiveModel();
    await store.ensureAvailable(model);
    final onnx = await store.modelFile(model);
    final tokenizer = await store.tokenizerFile(model);
    final loadedTokenizer = Tokenizer.fromFile(tokenizer.path);
    try {
      if (Platform.isAndroid) {
        await _android.load(onnx.path);
        _tokenizer = loadedTokenizer;
        _activeModelId = model.id;
        return;
      }
      final loadedSession = await OnnxRuntime().createSession(
        onnx.path,
        options: OrtSessionOptions(
          providers: const [OrtProvider.CPU],
          intraOpNumThreads: 2,
          interOpNumThreads: 1,
        ),
      );
      _tokenizer = loadedTokenizer;
      _session = loadedSession;
      _activeModelId = model.id;
    } catch (_) {
      loadedTokenizer.close();
      rethrow;
    }
  }

  Future<List<double>> _generateOne(
    LocalEmbeddingModel model,
    String text,
  ) async {
    final tokenizer = _tokenizer!;
    final truncated = tokenizer.truncateToTokens(text, 512);
    final tokenIds = boundEmbeddingTokens(tokenizer.encode(truncated));
    if (tokenIds.isEmpty) {
      throw const FormatException('Tokenizer 没有生成任何 token');
    }
    if (Platform.isAndroid) {
      return _android.embed(tokenIds, model.dimensions);
    }
    final session = _session!;
    final shape = [1, tokenIds.length];
    final mask = Int64List.fromList(List<int>.filled(tokenIds.length, 1));
    final zeros = Int64List(tokenIds.length);
    final tensors = <String, OrtValue>{};
    Map<String, OrtValue> outputs = const {};
    try {
      tensors['input_ids'] = await OrtValue.fromList(
        Int64List.fromList(tokenIds),
        shape,
      );
      if (session.inputNames.contains('attention_mask')) {
        tensors['attention_mask'] = await OrtValue.fromList(mask, shape);
      }
      if (session.inputNames.contains('token_type_ids')) {
        tensors['token_type_ids'] = await OrtValue.fromList(zeros, shape);
      }
      outputs = await session.run(tensors);
      final output = outputs['sentence_embedding'] ??
          outputs['last_hidden_state'] ??
          (session.outputNames.isEmpty
              ? null
              : outputs[session.outputNames.first]);
      if (output == null) {
        throw const FormatException('ONNX 模型没有返回可用的向量输出');
      }
      final flattened = (await output.asFlattenedList())
          .map((value) => (value as num).toDouble())
          .toList(growable: false);
      final vector = poolAndNormalizeEmbedding(
        flattened,
        output.shape,
        mask,
      );
      if (vector.length != model.dimensions) {
        throw FormatException(
          '${model.name} 向量维度错误：预期 ${model.dimensions}，实际 ${vector.length}',
        );
      }
      return vector;
    } finally {
      for (final value in outputs.values) {
        await value.dispose();
      }
      for (final value in tensors.values) {
        await value.dispose();
      }
    }
  }

  Future<void> _closeActiveModel() async {
    _idleRelease?.cancel();
    _tokenizer?.close();
    _tokenizer = null;
    await _session?.close();
    _session = null;
    _activeModelId = null;
    if (Platform.isAndroid) await _android.close();
  }
}

// Re-tokenizing a prefix can change boundary tokenization. Enforce the actual
// tensor bound too, preserving the trailing separator for BERT/E5 tokenizers.
List<int> boundEmbeddingTokens(List<int> ids) =>
    ids.length <= 512 ? ids : [...ids.take(511), ids.last];

List<double> poolAndNormalizeEmbedding(
  List<double> values,
  List<int> shape,
  List<int> attentionMask,
) {
  late final List<double> pooled;
  if (shape.length == 3 && shape.first == 1) {
    final sequenceLength = shape[1];
    final dimensions = shape[2];
    if (sequenceLength != attentionMask.length ||
        values.length != sequenceLength * dimensions) {
      throw const FormatException('ONNX 隐藏状态形状无效');
    }
    pooled = List<double>.filled(dimensions, 0);
    var activeTokens = 0;
    for (var token = 0; token < sequenceLength; token++) {
      if (attentionMask[token] == 0) continue;
      activeTokens++;
      final offset = token * dimensions;
      for (var dimension = 0; dimension < dimensions; dimension++) {
        pooled[dimension] += values[offset + dimension];
      }
    }
    if (activeTokens == 0) {
      throw const FormatException('attention mask 不包含有效 token');
    }
    for (var index = 0; index < pooled.length; index++) {
      pooled[index] /= activeTokens;
    }
  } else if (shape.length == 2 && shape.first == 1) {
    if (values.length != shape[1]) {
      throw const FormatException('ONNX 句向量形状无效');
    }
    pooled = List<double>.from(values, growable: false);
  } else if (shape.length == 1 && values.length == shape.first) {
    pooled = List<double>.from(values, growable: false);
  } else {
    throw FormatException('不支持的 ONNX 输出形状：$shape');
  }

  final norm = math.sqrt(
    pooled.fold<double>(0, (sum, value) => sum + value * value),
  );
  if (norm == 0 || !norm.isFinite) {
    throw const FormatException('ONNX 模型返回了零向量或非有限向量');
  }
  return pooled.map((value) => value / norm).toList(growable: false);
}
