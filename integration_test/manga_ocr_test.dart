import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:modu_reader/service/ocr/local_ocr_service.dart';
import 'package:modu_reader/service/ocr/manga_page.dart';
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
      if (model == OcrModels.manga) {
        final bubbles = mangaPageBubbles(result);
        expect(bubbles.map((b) => b['original']), ['こんにちは', 'ありがとう']);
        expect(bubbles.map((b) => b['tapToReveal']), [false, false]);
        if (Platform.isMacOS) await _verifyBubbleOverlay(bubbles);
      }
      expect(
          result.regions.first.rect.x, greaterThan(result.regions.last.rect.x));
    }, skip: directory.isEmpty || fixtures.isEmpty);
  }
}

Future<void> _verifyBubbleOverlay(List<Map<String, dynamic>> bubbles) async {
  final ready = Completer<InAppWebViewController>();
  final view = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
          data:
              '<meta name="viewport" content="width=device-width"><body></body>'),
      onLoadStop: (c, _) {
        if (!ready.isCompleted) ready.complete(c);
      });
  try {
    await view.run();
    final controller = await ready.future.timeout(const Duration(seconds: 15));
    final script =
        await rootBundle.loadString('assets/foliate-js/src/manga-bubbles.js');
    final result = await controller.callAsyncJavaScript(arguments: {
      'bubbles': [
        for (final b in bubbles)
          {...b, 'translation': b['original'] == 'こんにちは' ? '你好' : '谢谢'}
      ]
    }, functionBody: '''
      ${script.replaceAll('export function', 'function')}
      const frame = document.createElement('iframe');
      frame.style.cssText = 'width:640px;height:800px;border:0;transform-origin:0 0';
      document.body.append(frame);
      const doc = frame.contentDocument;
      let shadow;
      const proto = frame.contentWindow.Element.prototype;
      const attach = proto.attachShadow;
      proto.attachShadow = function(options) {shadow = attach.call(this, options); return shadow};
      let pageTaps = 0;
      doc.addEventListener('click', () => pageTaps++);
      const host = drawMangaBubbles(doc, bubbles);
      const btn = shadow.querySelector('button');
      const [x,y,w,h] = bubbles[0].rect;
      const r = btn.getBoundingClientRect();
      const aligned = Math.abs(r.x-x*640)<1 && Math.abs(r.y-y*800)<1 && Math.abs(r.width-w*640)<1;
      const fits = btn.textContent === '你好' && btn.clientHeight >= btn.scrollHeight && btn.clientWidth >= btn.scrollWidth;
      btn.click();
      const original = btn.textContent === '' && [...shadow.querySelectorAll('span')][0].hidden;
      btn.click();
      frame.style.transform = 'translate(-30px,-40px) scale(1.5)';
      return {aligned, fits, original, restored:btn.textContent === '你好', pageTaps,
        anchored:host.ownerDocument === frame.contentDocument && btn.getBoundingClientRect().x === r.x};
    ''');
    expect(result?.error, isNull);
    expect(result?.value, {
      'aligned': true,
      'fits': true,
      'original': true,
      'restored': true,
      'pageTaps': 0,
      'anchored': true
    });
  } finally {
    await view.dispose();
  }
}
