import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class OcrBox {
  const OcrBox(this.x, this.y, this.width, this.height);
  final int x, y, width, height;
}

/// PP-OCR mobile uses BGR, NCHW. Keep preprocessing out of the UI isolate.
Float32List ocrTensor(img.Image image,
    {required bool detection, int? paddedWidth}) {
  final w = paddedWidth ?? image.width, h = image.height;
  final data = Float32List(3 * w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final channels = [p.b.toDouble(), p.g.toDouble(), p.r.toDouble()];
      for (var c = 0; c < 3; c++) {
        data[c * w * h + y * w + x] = detection
            ? (channels[c] / 255 - const [.485, .456, .406][c]) /
                const [.229, .224, .225][c]
            : channels[c] / 127.5 - 1;
      }
    }
  }
  return data;
}

/// Bounded DB probability components for upright printed lines. This is not a
/// semantic table/layout model. Users can crop one column before recognizing.
List<OcrBox> ocrBoxes(
    List<double> values, int w, int h, int originalW, int originalH) {
  if (w <= 0 || h <= 0 || w * h > 1024 * 1024 || values.length != w * h) {
    throw const FormatException('Invalid detection map');
  }
  final seen = Uint8List(w * h), queue = Int32List(w * h), boxes = <OcrBox>[];
  for (var start = 0; start < values.length; start++) {
    if (seen[start] != 0 || values[start] < .3) continue;
    var head = 0,
        tail = 1,
        left = start % w,
        right = left,
        top = start ~/ w,
        bottom = top;
    var score = 0.0;
    queue[0] = start;
    seen[start] = 1;
    while (head < tail) {
      final p = queue[head++], x = p % w, y = p ~/ w;
      score += values[p];
      left = math.min(left, x);
      right = math.max(right, x);
      top = math.min(top, y);
      bottom = math.max(bottom, y);
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx, yy = y + dy;
          if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
          final n = yy * w + xx;
          if (seen[n] == 0 && values[n] >= .3) {
            seen[n] = 1;
            queue[tail++] = n;
          }
        }
      }
    }
    if (tail < 6 || score / tail < .5 || right - left < 2 || bottom - top < 2) {
      continue;
    }
    final pad = (bottom - top + 1) * .55;
    final x = ((left - pad) * originalW / w).floor().clamp(0, originalW - 1);
    final y = ((top - pad) * originalH / h).floor().clamp(0, originalH - 1);
    final r =
        ((right + pad + 1) * originalW / w).ceil().clamp(x + 1, originalW);
    final b =
        ((bottom + pad + 1) * originalH / h).ceil().clamp(y + 1, originalH);
    boxes.add(OcrBox(x, y, r - x, b - y));
    if (boxes.length > 300) {
      throw const FormatException(
          'Too many text regions; select a smaller area');
    }
  }
  // Stable row grouping rather than a non-transitive fuzzy sort comparator.
  boxes.sort((a, b) => a.y.compareTo(b.y));
  final ordered = <OcrBox>[];
  for (var i = 0; i < boxes.length;) {
    final first = boxes[i], row = <OcrBox>[first];
    i++;
    while (i < boxes.length &&
        boxes[i].y - first.y < math.min(first.height, boxes[i].height) * .4) {
      row.add(boxes[i++]);
    }
    row.sort((a, b) => a.x.compareTo(b.x));
    ordered.addAll(row);
  }
  return ordered;
}

String decodeOcrCtc(List<double> data, List<int> shape, List<String> alphabet) {
  if (shape.length != 3 ||
      shape[0] != 1 ||
      shape[2] != alphabet.length ||
      data.length != shape[1] * shape[2]) {
    throw const FormatException('OCR vocabulary mismatch');
  }
  final out = StringBuffer();
  var previous = -1;
  for (var t = 0; t < shape[1]; t++) {
    var best = 0;
    for (var c = 1; c < shape[2]; c++) {
      if (data[t * shape[2] + c] > data[t * shape[2] + best]) best = c;
    }
    if (best != 0 && best != previous && data[t * shape[2] + best] >= .3) {
      out.write(alphabet[best]);
    }
    previous = best;
  }
  return out.toString().trim();
}

typedef OcrRun = Future<(List<double>, List<int>)> Function(
    String, Float32List, List<int>);

Future<String> recognizeOcrImage(
    Uint8List bytes, List<String> alphabet, OcrRun run,
    {required bool Function() cancelled,
    void Function(int, int)? progress}) async {
  void check() {
    if (cancelled()) throw StateError('OCR cancelled');
  }

  check();
  // Reject decompression bombs before allocating a decoded pixel buffer.
  final header = img.PngDecoder().startDecode(bytes);
  if (header == null ||
      header.width <= 0 ||
      header.height <= 0 ||
      header.width * header.height > 2097152) {
    throw const FormatException('Invalid OCR image dimensions');
  }
  final image = img.decodePng(bytes);
  if (image == null || image.width * image.height > 2097152) {
    throw const FormatException('Invalid OCR image');
  }
  final scale = math.min(1.0, 960 / math.max(image.width, image.height));
  final w = math.max(32, (image.width * scale / 32).round() * 32);
  final h = math.max(32, (image.height * scale / 32).round() * 32);
  final input = img.copyResize(image,
      width: w, height: h, interpolation: img.Interpolation.linear);
  final det = await run('det', ocrTensor(input, detection: true), [1, 3, h, w]);
  check();
  if (det.$2.length != 4 || det.$2[0] != 1 || det.$2[1] != 1) {
    throw const FormatException('Invalid OCR detector');
  }
  final boxes =
      ocrBoxes(det.$1, det.$2[3], det.$2[2], image.width, image.height);
  final lines = <String>[];
  for (var i = 0; i < boxes.length; i++) {
    check();
    final b = boxes[i];
    final crop =
        img.copyCrop(image, x: b.x, y: b.y, width: b.width, height: b.height);
    // v5 has a larger alphabet. Bound CTC output before allocating/bridging it.
    final maxWidth = math.min(1536, (5000000 ~/ alphabet.length) * 4);
    final width = (48 * b.width / b.height).ceil().clamp(8, maxWidth);
    final line = img.copyResize(crop,
        width: width, height: 48, interpolation: img.Interpolation.linear);
    final padded = math.max(320, width);
    final rec = await run(
        'rec',
        ocrTensor(line, detection: false, paddedWidth: padded),
        [1, 3, 48, padded]);
    check();
    final text = decodeOcrCtc(rec.$1, rec.$2, alphabet);
    if (text.isNotEmpty) lines.add(text);
    progress?.call(i + 1, boxes.length);
    await Future<void>.delayed(Duration.zero);
  }
  check();
  return lines.join('\n');
}
