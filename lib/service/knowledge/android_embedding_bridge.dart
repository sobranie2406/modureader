import 'dart:typed_data';
import 'package:flutter/services.dart';

class AndroidEmbeddingBridge {
  const AndroidEmbeddingBridge();
  static const channel = MethodChannel('com.modu.reader/local_embedding');

  Future<void> load(String path) =>
      channel.invokeMethod<void>('load', {'path': path});
  Future<void> close() => channel.invokeMethod<void>('close');

  Future<List<double>> embed(List<int> ids, int dimensions) async {
    final result = await channel.invokeMethod<Object>('embed', {
      'ids': Int64List.fromList(ids),
      'dimensions': dimensions,
    });
    if (result is! List || result.length != dimensions) {
      throw const FormatException('Android 返回的向量维度无效');
    }
    final values = result
        .map((value) => (value as num).toDouble())
        .toList(growable: false);
    if (values.any((value) => !value.isFinite)) {
      throw const FormatException('Android 返回的向量包含非有限值');
    }
    return values;
  }
}
