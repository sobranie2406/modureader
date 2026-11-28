import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

import 'document_text_geometry.dart';
import 'ocr_processing.dart';

List<OcrBox> mangaTextBoxes(List<int> labels, List<double> scores,
    List<double> coords, int width, int height,
    {required bool vertical, Map<OcrBox, OcrBox>? bubbles}) {
  if (labels.length != scores.length ||
      coords.length != 4 * labels.length ||
      labels.length > 300) {
    throw const FormatException('Invalid bubble detections');
  }
  final candidates = <({int label, double score, OcrBox box})>[];
  for (var i = 0; i < labels.length; i++) {
    if (scores[i] < .4 ||
        !scores[i].isFinite ||
        labels[i] < 0 ||
        labels[i] > 2) {
      continue;
    }
    final pos = i * 4;
    final x = coords[pos].floor().clamp(0, width),
        y = coords[pos + 1].floor().clamp(0, height);
    final r = coords[pos + 2].ceil().clamp(0, width),
        b = coords[pos + 3].ceil().clamp(0, height);
    if (r > x && b > y) {
      candidates.add((
        label: labels[i],
        score: scores[i],
        box: OcrBox(x, y, r - x, b - y)
      ));
    }
  }
  // Prefer detected lettering. Use an enclosing bubble only when it has no lettering box.
  candidates.sort((a, b) {
    if ((a.label == 0) != (b.label == 0)) return a.label == 0 ? 1 : -1;
    return b.score.compareTo(a.score);
  });
  final kept = <OcrBox>[];
  for (final c in candidates) {
    final a = c.box;
    final duplicate = kept.any((b) {
      final w = math.max(
          0, math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x));
      final h = math.max(
          0, math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y));
      final overlap = w * h;
      return overlap >
              .5 * (a.width * a.height + b.width * b.height - overlap) ||
          (c.label == 0 && overlap >= .9 * b.width * b.height);
    });
    if (duplicate) continue;
    kept.add(a);
    // A balloon without detected lettering is still readable on tap. Painting
    // its entire detection rectangle would erase the outline and nearby art.
    if (bubbles != null && c.label == 1) {
      OcrBox? enclosing;
      for (final outer in candidates.where((item) => item.label == 0)) {
        final b = outer.box;
        final w = math.max(
            0, math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x));
        final h = math.max(
            0, math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y));
        if (w * h >= .9 * a.width * a.height &&
            (enclosing == null ||
                b.width * b.height < enclosing.width * enclosing.height)) {
          enclosing = b;
        }
      }
      bubbles[a] = enclosing ?? a;
    }
  }
  if (vertical) return orderVerticalOcrBoxes(kept);
  return kept
    ..sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
}

Future<OrtValue> _pixels(img.Image image, int size, {required bool detector}) {
  final resized = img.copyResize(image,
      width: size, height: size, interpolation: img.Interpolation.linear);
  return OrtValue.fromList(
      ocrTensor(resized, detection: detector, rgb: true), [1, 3, size, size]);
}

Future<DocumentTextResult> recognizeManga(
    img.Image image,
    List<String> vocab,
    Map<String, OrtSession> sessions,
    void Function() check,
    void Function(int, int) progress,
    {required bool vertical}) async {
  final inputs = <String, OrtValue>{};
  Map<String, OrtValue> output = {};
  late List<OcrBox> boxes;
  final bubbles = <OcrBox, OcrBox>{};
  try {
    inputs['images'] = await _pixels(image, 640, detector: true);
    inputs['orig_target_sizes'] = await OrtValue.fromList(
        Int64List.fromList([image.width, image.height]), [1, 2]);
    check();
    output = await sessions['det']!.run(inputs);
    boxes = mangaTextBoxes(
        (await output['labels']!.asFlattenedList()).cast<int>(),
        (await output['scores']!.asFlattenedList()).cast<double>(),
        (await output['boxes']!.asFlattenedList()).cast<double>(),
        image.width,
        image.height,
        vertical: vertical,
        bubbles: bubbles);
  } finally {
    for (final tensor in [...inputs.values, ...output.values]) {
      await tensor.dispose();
    }
  }
  return recognizeOcrBoxes(image, boxes, (box) async {
    final pad = math.min(8, math.min(box.width, box.height) ~/ 8);
    final x = math.max(0, box.x - pad), y = math.max(0, box.y - pad);
    final crop = img.copyCrop(image,
        x: x,
        y: y,
        width: math.min(image.width, box.x + box.width + pad) - x,
        height: math.min(image.height, box.y + box.height + pad) - y);
    final pixels = await _pixels(crop, 224, detector: false);
    Map<String, OrtValue> hidden = {};
    try {
      hidden = await sessions['encoder']!.run({'pixel_values': pixels});
      final ids = [2]; // [CLS]
      final text = StringBuffer();
      while (ids.length <= 300) {
        check();
        final inputIds =
            await OrtValue.fromList(Int64List.fromList(ids), [1, ids.length]);
        Map<String, OrtValue> out = {};
        try {
          out = await sessions['decoder']!.run({
            'input_ids': inputIds,
            'encoder_hidden_states': hidden['last_hidden_state']!
          });
          final logits = out['logits']!;
          if (logits.shape.length != 3 ||
              logits.shape.last != vocab.length ||
              logits.shape[1] != ids.length) {
            throw const FormatException('Invalid manga vocabulary');
          }
          final values = (await logits.asFlattenedList()).cast<double>();
          final offset = values.length - vocab.length;
          var best = 0;
          for (var i = 1; i < vocab.length; i++) {
            if (values[offset + i] > values[offset + best]) best = i;
          }
          if (best == 3) break; // [SEP]
          ids.add(best);
          if (best > 4) {
            final token = vocab[best];
            text.write(token.startsWith('##') ? token.substring(2) : token);
          }
        } finally {
          await inputIds.dispose();
          for (final tensor in out.values) {
            await tensor.dispose();
          }
        }
      }
      return text.toString().trim();
    } finally {
      await pixels.dispose();
      for (final tensor in hidden.values) {
        await tensor.dispose();
      }
    }
  }, check, progress, bubbles: bubbles);
}
