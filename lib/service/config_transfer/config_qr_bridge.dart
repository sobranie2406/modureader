import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class ConfigQrBridge {
  const ConfigQrBridge._();

  static const _channel = MethodChannel('com.modu.reader/config_transfer');

  static bool get isSupported => Platform.isMacOS;

  static Future<Uint8List?> generate(String text) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<Uint8List>('generateQrCode', {'text': text});
  }

  static Future<String?> decodeImage(String path) async {
    if (!isSupported) return null;
    return _channel.invokeMethod<String>('decodeQrCode', {'path': path});
  }
}
