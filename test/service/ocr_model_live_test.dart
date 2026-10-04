import 'dart:io';
import 'package:anx_reader/service/ocr/ocr_model_store.dart';
import 'package:anx_reader/service/ocr/ocr_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit network opt-in. Model weights never enter the app assets or backup.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all Gitee OCR packs and v5 upstream download anonymously and verify',
      () async {
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    final root = await Directory.systemTemp.createTemp('modu-ocr-mirror-live-');
    try {
      for (final model in OcrModels.all) {
        for (final source in [
          OcrDownloadSource.gitee,
          if (model.id == 'ppocr-v5-mobile-1') OcrDownloadSource.upstream
        ]) {
          final store = OcrModelStore(
              model: model,
              downloadSource: source,
              directory: Directory('${root.path}/${model.id}/${source.name}'));
          try {
            await store.download(CancelToken(), (_, __) {});
            await store.verify();
            expect(await store.available(), isTrue);
            // ignore: avoid_print
            print('OCR_DOWNLOAD_VERIFIED ${model.id} ${source.name}');
          } finally {
            store.close();
          }
        }
      }
    } finally {
      await root.delete(recursive: true);
      HttpOverrides.global = overrides;
    }
  },
      skip: !const bool.fromEnvironment('MODU_VERIFY_OCR_MIRROR'),
      timeout: const Timeout(Duration(minutes: 15)));
}
