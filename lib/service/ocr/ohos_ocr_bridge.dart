import 'dart:typed_data';

import 'package:flutter/services.dart';

class OhosOcrBridge {
  const OhosOcrBridge({this.timeout = const Duration(seconds: 30)});
  static const channel = MethodChannel('modu/ohos_ocr');
  final Duration timeout;

  Future<void> load(String path) =>
      channel.invokeMethod<void>('load', {'path': path}).timeout(timeout);

  Future<Map<String, Object?>> run(
      String name, Float32List data, List<int> shape) async {
    final result = await channel.invokeMapMethod<String, Object?>(
        'run', {'name': name, 'data': data, 'shape': shape}).timeout(timeout);
    if (result == null) throw const FormatException('Missing OCR output');
    return result;
  }

  Future<void> close() => channel.invokeMethod<void>('close').timeout(timeout);
}
