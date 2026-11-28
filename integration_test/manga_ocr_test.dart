import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:modu_reader/service/ocr/local_ocr_service.dart';
import 'package:modu_reader/service/ocr/ocr_model_store.dart';
import 'package:modu_reader/service/ocr/ocr_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const fixtures = String.fromEnvironment('MODU_OCR_FIXTURES');
  for (final (model, directory, png, expected) in [
    (
      OcrModels.manga,
      const String.fromEnvironment('MODU_MANGA_PACK'),
      'manga_bubbles',
      'こんにちは\nありがとう'
    ),
    (
      OcrModels.v6Small,
      const String.fromEnvironment('MODU_PP_PACK'),
      'vertical_japanese',
      '今日は晴れです\n明日は雨です'
    ),
  ]) {
    testWidgets('reads $png in Japanese column order', (_) async {
      final store =
          OcrModelStore(directory: Directory(directory), model: model);
      addTearDown(store.close);
      final result = await LocalOcrService().recognizeWithRegions(
          await File('$fixtures/$png.png').readAsBytes(),
          store,
          OcrCancellation(),
          vertical: true);
      expect(result.text, expected);
      expect(result.regions, hasLength(2));
      expect(
          result.regions.first.rect.x, greaterThan(result.regions.last.rect.x));
    }, skip: directory.isEmpty || fixtures.isEmpty);
  }
}
