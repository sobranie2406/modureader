import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

class ConfigQrBridge {
  const ConfigQrBridge._();

  static bool get isSupported =>
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS;

  static Future<Uint8List?> generate(String text) async {
    if (!isSupported) return null;
    return compute(_generate, text);
  }

  static Future<String?> decodeImage(String path) async {
    if (!isSupported) return null;
    try {
      return await compute(_decodeFile, path);
    } catch (_) {
      // Do not expose file paths or decoder internals from a private image.
      throw const FormatException(
          'Cannot read QR image; use a PNG/JPEG image under 12 MiB and 16 megapixels');
    }
  }

  static Uint8List _generate(String text) {
    // One QR cannot hold arbitrary multi-provider configurations. The UI keeps
    // the copyable token available when generation exceeds QR capacity.
    if (text.isEmpty || text.length > 2953) {
      throw const FormatException('Configuration exceeds QR capacity');
    }
    final matrix = Encoder.encode(text, ErrorCorrectionLevel.l).matrix!;
    const scale = 4, border = 4;
    final image = img.Image(
        width: (matrix.width + border * 2) * scale,
        height: (matrix.height + border * 2) * scale,
        numChannels: 3);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) != 1) continue;
        final left = (x + border) * scale, top = (y + border) * scale;
        img.fillRect(image,
            x1: left,
            y1: top,
            x2: left + scale - 1,
            y2: top + scale - 1,
            color: img.ColorRgb8(0, 0, 0));
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  static Future<String?> _decodeFile(String path) async {
    const maxBytes = 12 * 1024 * 1024;
    final file = File(path);
    if (await file.length() > maxBytes) {
      throw const FormatException('QR image exceeds 12 MiB');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('QR image exceeds 12 MiB');
      }
      bytes.add(chunk);
    }
    final data = bytes.takeBytes();
    final decoder = img.findDecoderForData(data);
    final info = decoder?.startDecode(data);
    if (info == null ||
        info.width <= 0 ||
        info.height <= 0 ||
        info.width * info.height > 16 * 1024 * 1024) {
      throw const FormatException('Invalid or oversized QR image');
    }
    var image = decoder!.decodeFrame(0);
    if (image == null) throw const FormatException('Invalid QR image');
    // Bound detector allocations for full-screen screenshots and phone photos.
    if (image.width > 2048 || image.height > 2048) {
      image = img.copyResize(image,
          width: image.width >= image.height ? 2048 : null,
          height: image.height > image.width ? 2048 : null);
    }
    final pixels = Int32List(image.width * image.height);
    for (final pixel in image) {
      pixels[pixel.y * image.width + pixel.x] =
          (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
    }
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    try {
      return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
    } on ReaderException {
      return null;
    }
  }
}
