import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class OhosEmbeddingBridge {
  const OhosEmbeddingBridge();
  static const channel = MethodChannel('modu/ohos_embedding');

  Future<bool> isAvailable() async {
    try {
      return await channel
              .invokeMethod<Object>('isAvailable')
              .timeout(const Duration(seconds: 2)) ==
          true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  Future<void> load(String path) =>
      channel.invokeMethod<void>('load', {'modelPath': path});

  Future<void> close() => channel.invokeMethod<void>('close');

  Future<List<double>> embed(List<int> ids, int dimensions) async {
    final result = await channel.invokeMethod<Object>('embed', {
      'ids': Int64List.fromList(ids),
      'dimensions': dimensions,
    });
    if (result is! List ||
        result.length != dimensions ||
        result.any((value) => value is! num || !value.isFinite)) {
      throw const FormatException('鸿蒙返回的向量维度或数值无效');
    }
    return result is Float64List
        ? result
        : Float64List.fromList(result
            .map((value) => (value as num).toDouble())
            .toList(growable: false));
  }
}
