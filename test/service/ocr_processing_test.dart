import 'dart:io';
import 'dart:typed_data';
import 'package:modu_reader/service/ocr/ocr_processing.dart';
import 'package:modu_reader/service/ocr/ocr_model_store.dart';
import 'package:modu_reader/service/ocr/ocr_model_metadata.dart';
import 'package:modu_reader/service/ocr/document_text_reflow.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('official V6 sidecar alphabet includes CTC blank and trailing space',
      () {
    final chars = List.generate(10, (i) => String.fromCharCode(65 + i));
    final config = 'PostProcess:\n  name: CTCLabelDecode\n  character_dict:\n'
        '${chars.map((c) => '  - $c\n').join()}';
    expect(ocrAlphabetFromConfig(config), ['', ...chars, ' ']);
    for (final bad in [
      '',
      'PostProcess: {}',
      config.replaceAll('CTCLabelDecode', 'Other')
    ]) {
      expect(() => ocrAlphabetFromConfig(bad), throwsFormatException);
    }
  });
  test('V6 detector thresholds are opt-in, legacy thresholds remain unchanged',
      () {
    final map = List<double>.filled(32 * 32, 0);
    for (var y = 10; y < 16; y++) {
      for (var x = 5; x < 22; x++) {
        map[y * 32 + x] = .47;
      }
    }
    expect(ocrBoxes(map, 32, 32, 320, 320), isEmpty);
    expect(
        ocrBoxes(map, 32, 32, 320, 320,
            detectionThreshold: .2, boxThreshold: .45),
        hasLength(1));
  });
  test('model metadata reader rejects malformed and missing alphabets', () {
    for (final bytes in [
      <int>[],
      [114, 127],
      [127],
      [128, 128, 128]
    ]) {
      expect(
          () => ocrAlphabet(Uint8List.fromList(bytes)), throwsFormatException);
    }
    final value = 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj'.codeUnits;
    final entry = [10, 9, ...'character'.codeUnits, 18, value.length, ...value];
    expect(ocrAlphabet(Uint8List.fromList([114, entry.length, ...entry])),
        ['', ...'abcdefghij'.split(''), ' ']);
  });
  test('reflow joins physical wraps without changing paragraph boundaries', () {
    expect(reflowDocumentText('中文行尾\n接续内容。\n同段。'), '中文行尾接续内容。同段。');
    expect(reflowDocumentText('中文行尾\n接续内容。\n\n新段。'), '中文行尾接续内容。\n\n新段。');
    expect(reflowDocumentText('First sentence.\nStill the same paragraph.'),
        'First sentence. Still the same paragraph.');
    expect(reflowDocumentText('A wrapped\nEnglish line.\n\nNext.'),
        'A wrapped English line.\n\nNext.');
    expect(reflowDocumentText('inter-\nnational'), 'international');
  });
  test('CTC removes duplicate classes but preserves blank-separated repeats',
      () {
    final classes = [1, 1, 0, 1, 2, 0];
    final values = <double>[
      for (final c in classes) ...[
        for (var i = 0; i < 3; i++) i == c ? .95 : .01
      ]
    ];
    expect(decodeOcrCtc(values, [1, 6, 3], ['', '中', '文']), '中中文');
    expect(() => decodeOcrCtc(values, [1, 6, 4], ['', '中', '文']),
        throwsFormatException);
  });
  test('recognition preprocessing is BGR and pads with normalized zero', () {
    final im = img.Image(width: 1, height: 1)..setPixelRgb(0, 0, 255, 127.5, 0);
    final values = ocrTensor(im, detection: false, paddedWidth: 2);
    expect(values[0], -1);
    expect(values[4], 1);
    expect([values[1], values[3], values[5]], [0, 0, 0]);
  });
  test('detector components are bounded and ordered from top to bottom', () {
    final values = List<double>.filled(40 * 40, 0);
    for (final y in [5, 25]) {
      for (var dy = 0; dy < 4; dy++) {
        for (var x = 5; x < 30; x++) {
          values[(y + dy) * 40 + x] = .9;
        }
      }
    }
    final boxes = ocrBoxes(values, 40, 40, 400, 400);
    expect(boxes.length, 2);
    expect(boxes.first.y, lessThan(boxes.last.y));
    for (final b in boxes) {
      expect(b.x, greaterThanOrEqualTo(0));
      expect(b.x + b.width, lessThanOrEqualTo(400));
    }
    expect(() => ocrBoxes([], 40, 40, 400, 400), throwsFormatException);
  });
  test('cancellation never runs the detector', () async {
    var runs = 0;
    await expectLater(
        recognizeOcrImage(Uint8List(0), [''], (name, data, shape) async {
          runs++;
          return (<double>[], <int>[]);
        }, cancelled: () => true),
        throwsStateError);
    expect(runs, 0);
  });
  test('OCR associates each recognized line with its original detector box',
      () async {
    final bytes =
        Uint8List.fromList(img.encodePng(img.Image(width: 400, height: 400)));
    final probabilities = List<double>.filled(40 * 40, 0);
    for (final y in [5, 25]) {
      for (var dy = 0; dy < 4; dy++) {
        for (var x = 5; x < 30; x++) {
          probabilities[(y + dy) * 40 + x] = .9;
        }
      }
    }
    Future<(List<double>, List<int>)> run(
            String name, List<double> data, List<int> shape) async =>
        name == 'det'
            ? (probabilities, [1, 1, 40, 40])
            : ([.01, .99], [1, 1, 2]);
    final result = await recognizeOcrImageWithRegions(bytes, ['', '朱'], run,
        cancelled: () => false);
    expect(result.text, '朱\n朱');
    final boxes = ocrBoxes(probabilities, 40, 40, 400, 400);
    for (var i = 0; i < boxes.length; i++) {
      final region = result.regions[i], box = boxes[i];
      expect([region.start, region.end], [i * 2, i * 2 + 1]);
      expect(region.rect.toJson(),
          [box.x / 400, box.y / 400, box.width / 400, box.height / 400]);
    }
    expect(
        await recognizeOcrImage(bytes, ['', '朱'], run, cancelled: () => false),
        result.text);
  });
  test('model checksum rejects same-size corrupted downloads', () async {
    final dir = await Directory.systemTemp.createTemp('modu-ocr-test-');
    try {
      final file = File('${dir.path}/model');
      await file.writeAsBytes([1, 2, 3]);
      final digest = sha256.convert([1, 2, 3]).toString();
      expect(await OcrModelStore.validFile(file.path, 3, digest), true);
      await file.writeAsBytes([3, 2, 1]);
      expect(await OcrModelStore.validFile(file.path, 3, digest), false);
      expect(await OcrModelStore(directory: dir).available(), false);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
