import 'reader_content_brightness.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:modu_reader/l10n/modu_strings.dart';
import 'package:modu_reader/service/ocr/document_reflow_store.dart';
import 'package:modu_reader/service/ocr/document_text_geometry.dart';
import 'package:modu_reader/utils/app_motion.dart';
import 'widget_title.dart';
import 'package:flutter/material.dart';
import 'reader_popup.dart';

/// Read-only source verification: never rerun OCR or move a saved annotation.
class DocumentOriginalNote extends StatefulWidget {
  const DocumentOriginalNote(
      {super.key,
      required this.anchor,
      required this.render,
      required this.cancelRender});
  final DocumentReflowAnchor anchor;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>) render;
  final VoidCallback cancelRender;
  @override
  State<DocumentOriginalNote> createState() => _DocumentOriginalNoteState();
}

class _DocumentOriginalNoteState extends State<DocumentOriginalNote> {
  Uint8List? _bytes;
  double _ratio = 1;
  bool _failed = false;
  String t(String zh, String en) => ModuStrings.text(context, zh, en);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final result = await widget.render({
        'page': widget.anchor.page,
        'region': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        'rotation': 0,
        'width': 2048,
        'height': 2048,
        'hideWatermarks': false
      });
      if (!mounted) return;
      final data = result['dataUrl'],
          width = result['width'],
          height = result['height'];
      const prefix = 'data:image/png;base64,';
      if (result['page'] != widget.anchor.page ||
          data is! String ||
          !data.startsWith(prefix) ||
          data.length > 16000000 ||
          width is! num ||
          height is! num ||
          !width.isFinite ||
          !height.isFinite ||
          width <= 0 ||
          height <= 0 ||
          width * height > 2097152) {
        throw const FormatException('Invalid source image');
      }
      final bytes = base64Decode(data.substring(prefix.length));
      setState(() {
        _bytes = bytes;
        _ratio = width / height;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    widget.cancelRender();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        child: ReaderContentBrightness(
            backgroundColor: Theme.of(context).dialogTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            child: SizedBox(
                width: 800,
                height: ReaderPopup.height(context),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                '${t('原书第', 'Original page')} ${widget.anchor.page + 1}',
                                style: readerSubmenuTitleStyle(context))),
                        IconButton(
                            tooltip: t('关闭', 'Close'),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close))
                      ]),
                      const SizedBox(height: 8),
                      Expanded(
                          child: _failed
                              ? Center(
                                  child: TextButton.icon(
                                      onPressed: _load,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(t('原图加载失败，重试',
                                          'Could not load source image. Retry'))))
                              : _bytes == null
                                  ? const Center(
                                      child: EinkStaticIndicator(
                                          child: CircularProgressIndicator()))
                                  : LayoutBuilder(
                                      builder: (context, constraints) {
                                      final width = math.min(
                                          constraints.maxWidth,
                                          constraints.maxHeight * _ratio);
                                      return InteractiveViewer(
                                          maxScale: 8,
                                          child: Center(
                                              child: SizedBox(
                                                  width: width,
                                                  height: width / _ratio,
                                                  child: Stack(
                                                      fit: StackFit.expand,
                                                      children: [
                                                        Image.memory(_bytes!,
                                                            fit: BoxFit.fill,
                                                            errorBuilder: (_,
                                                                    error,
                                                                    stack) =>
                                                                Center(
                                                                    child: Text(t(
                                                                        '无法显示原图',
                                                                        'Cannot display source image')))),
                                                        IgnorePointer(
                                                            child: CustomPaint(
                                                                key: const ValueKey(
                                                                    'original-note-regions'),
                                                                painter: DocumentOriginalNotePainter(
                                                                    widget
                                                                        .anchor
                                                                        .rects,
                                                                    Theme.of(
                                                                            context)
                                                                        .colorScheme
                                                                        .primary))),
                                                      ]))));
                                    })),
                    ])))),
      );
}

class DocumentOriginalNotePainter extends CustomPainter {
  const DocumentOriginalNotePainter(this.rects, this.color);
  final List<DocumentImageRect> rects;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final fill = Paint()..color = color.withValues(alpha: .12);
    for (final r in rects) {
      final rect = Rect.fromLTWH(r.x * size.width, r.y * size.height,
          r.width * size.width, r.height * size.height);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, stroke);
    }
  }

  @override
  bool shouldRepaint(DocumentOriginalNotePainter oldDelegate) =>
      oldDelegate.rects != rects || oldDelegate.color != color;
}
