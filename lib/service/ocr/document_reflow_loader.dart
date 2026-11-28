import 'dart:convert';
import 'dart:typed_data';
import 'document_reflow_store.dart';
import 'document_text_geometry.dart';
import 'local_ocr_service.dart';
import 'ocr_model_store.dart';

class ReflowModelUnavailable implements Exception {}

/// Both foreground reading and idle prefetch use the same page text and geometry.
Future<DocumentReflowPage> loadDocumentReflowPage({
  required Map<String, dynamic> info,
  required DocumentReflowStore store,
  required OcrModelStore model,
  required OcrCancellation cancel,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>) extract,
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>) render,
  required Future<DocumentTextResult> Function(
          Uint8List, OcrCancellation, void Function(int, int))
      recognize,
  void Function(int, int)? progress,
  DocumentReflowAnchor? anchor,
  bool forceOcr = false,
  bool refresh = false,
  bool vertical = false,
}) async {
  cancel.check();
  final rawPage = info['page'], rawTotal = info['total'];
  // WKWebView bridges JavaScript integers as doubles on Apple platforms.
  if (rawPage is! num ||
      rawTotal is! num ||
      !rawPage.isFinite ||
      !rawTotal.isFinite ||
      rawPage != rawPage.toInt() ||
      rawTotal != rawTotal.toInt() ||
      rawPage < 0 ||
      rawPage >= rawTotal ||
      info['imageOnly'] == false) {
    throw const FormatException('Invalid image page');
  }
  final page = rawPage.toInt();
  final profile = model.model.readingProfile(vertical);
  final cached = refresh
      ? null
      : anchor == null
          ? await store.read(page, '')
          : await store.readAnchor(anchor);
  cancel.check();
  if (cached != null &&
      (anchor != null ||
          ((!forceOcr || cached.ocr) && cached.acceptsOcrProfile(profile)))) {
    return cached;
  }
  final rawRegion =
      info['region'] ?? const {'x': 0.0, 'y': 0.0, 'width': 1.0, 'height': 1.0};
  final region = rawRegion is Map
      ? DocumentImageRect.decode([
          for (final key in ['x', 'y', 'width', 'height']) rawRegion[key]
        ])
      : null;
  if (region == null) throw const FormatException('Invalid reflow bounds');
  final request = <String, dynamic>{
    'page': page,
    'region': rawRegion,
    'hideWatermarks': info['hideWatermarks'] == true
  };
  var result = DocumentTextResult('');
  var ocr = false;
  if (!forceOcr) {
    result = DocumentTextResult.decode(await extract(request));
    cancel.check();
  }
  if (result.text.trim().isEmpty) {
    if (!await model.available()) throw ReflowModelUnavailable();
    cancel.check();
    ocr = true;
    final image = await render(
        {...request, 'width': 2048, 'height': 2048, 'rotation': 0});
    cancel.check();
    const prefix = 'data:image/png;base64,';
    final data = image['dataUrl'];
    if (data is! String || !data.startsWith(prefix) || data.length > 16000000) {
      throw const FormatException('Invalid page image');
    }
    result = (await recognize(base64Decode(data.substring(prefix.length)),
            cancel, progress ?? (_, __) {}))
        .within(region);
    cancel.check();
  }
  if (result.text.trim().isEmpty || result.text.length > 1000000) {
    throw const FormatException('No usable text');
  }
  final value = DocumentReflowPage(
      page: page,
      ocr: ocr,
      ocrProfile: ocr ? profile : '',
      rawText: result.text,
      rawRegions: result.regions);
  await store.save(value, '',
      onlyIfAbsent: !refresh, replaceEmbeddedText: forceOcr);
  cancel.check();
  return refresh ? value : (await store.read(page, '') ?? value);
}
