import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:xml/xml.dart';

enum MindmapExportFormat {
  png('PNG', 'png', 'image/png'),
  svg('SVG', 'svg', 'image/svg+xml'),
  markdown('Markdown', 'md', 'text/markdown'),
  freeMind('FreeMind', 'mm', 'application/x-freemind'),
  json('JSON', 'json', 'application/json');

  const MindmapExportFormat(this.label, this.extension, this.mimeType);
  final String label;
  final String extension;
  final String mimeType;
}

class MindmapExportNode {
  MindmapExportNode(this.id, this.label, this.children);
  final String id;
  final String label;
  final List<MindmapExportNode> children;

  Map<String, Object> toJson() => {
        'id': id,
        'label': label,
        'children': children.map((n) => n.toJson()).toList(),
      };
}

/// Exports the full data tree, never a screenshot of the zoomed viewport.
class MindmapExportDocument {
  MindmapExportDocument._(this.title, this.root);
  final String title;
  final MindmapExportNode root;

  factory MindmapExportDocument.fromJson(Map<String, dynamic> data) {
    var count = 0;
    var characters = 0;
    MindmapExportNode read(Object? value, int depth) {
      if (value is! Map || depth > 64 || ++count > 2000) {
        throw const FormatException('Invalid or oversized mindmap');
      }
      final label = value['label'];
      final children = value['children'] ?? const [];
      if (label is! String || children is! List || label.length > 20000) {
        throw const FormatException('Invalid mindmap node');
      }
      characters += label.length;
      if (characters > 500000) throw const FormatException('Mindmap too large');
      // AI IDs may be duplicated or missing; export stable unique tree IDs.
      final id = 'node$count';
      return MindmapExportNode(
          id, label, children.map((child) => read(child, depth + 1)).toList());
    }

    final root = read(data['root'], 0);
    return MindmapExportDocument._(
        data['title']?.toString() ?? root.label, root);
  }

  String fileName(MindmapExportFormat format, {DateTime? now}) {
    final safe = title
        .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    final short = String.fromCharCodes(safe.runes.take(60));
    // Unique names avoid silently replacing an earlier Windows download.
    return 'Modu-${short.isEmpty ? 'mindmap' : short}-${(now ?? DateTime.now()).microsecondsSinceEpoch}.${format.extension}';
  }

  Future<Uint8List> export(MindmapExportFormat format) async {
    switch (format) {
      case MindmapExportFormat.json:
        return _bytes(const JsonEncoder.withIndent('  ').convert({
          'title': title,
          'root': root.toJson(),
        }));
      case MindmapExportFormat.markdown:
        final out = StringBuffer();
        void visit(MindmapExportNode node, int depth) {
          final label = node.label
              .replaceAll(RegExp(r'[\r\n]+'), ' ')
              .replaceAllMapped(
                  RegExp(r'[\\`*_{}\[\]<>#]'), (m) => '\\${m[0]}');
          out.writeln('${'  ' * depth}- $label');
          for (final child in node.children) {
            visit(child, depth + 1);
          }
        }
        visit(root, 0);
        return _bytes(out.toString());
      case MindmapExportFormat.freeMind:
        // FreeMind XML: https://freemind.sourceforge.io/wiki/index.php/File_format
        final xml = XmlBuilder()
          ..processing('xml', 'version="1.0" encoding="UTF-8"');
        void visit(MindmapExportNode node) {
          xml.element('node',
              attributes: {'ID': node.id, 'TEXT': _xmlText(node.label)},
              nest: () {
            for (final child in node.children) {
              visit(child);
            }
          });
        }
        xml.element('map',
            attributes: {'version': '1.0.1'}, nest: () => visit(root));
        return _bytes(xml.buildDocument().toXmlString(pretty: true));
      case MindmapExportFormat.svg:
      case MindmapExportFormat.png:
        final layout = _MindmapLayout(root);
        try {
          return format == MindmapExportFormat.svg
              ? _bytes(layout.svg(title))
              : await layout.png();
        } finally {
          layout.dispose();
        }
    }
  }
}

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));
String _xmlText(String value) =>
    value.replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]'), '');

class _LayoutNode {
  _LayoutNode(this.data, this.painter, this.children);
  final MindmapExportNode data;
  final TextPainter painter;
  final List<_LayoutNode> children;
  double x = 0, y = 0, subtree = 0;
  double get height => painter.height + 24;
  Rect get rect => Rect.fromLTWH(x, y, 244, height);
}

class _MindmapLayout {
  _MindmapLayout(MindmapExportNode root) {
    _LayoutNode measure(MindmapExportNode node) {
      final painter = TextPainter(
        text: TextSpan(
            text: node.label.isEmpty ? ' ' : node.label,
            style: const TextStyle(fontSize: 16, color: Color(0xff28241f))),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 220);
      final children = node.children.map(measure).toList();
      final item = _LayoutNode(node, painter, children);
      item.subtree = math.max(
          item.height,
          children.fold<double>(0, (sum, n) => sum + n.subtree) +
              math.max(0, children.length - 1) * 20);
      nodes.add(item);
      return item;
    }

    final measured = measure(root);
    void place(_LayoutNode node, int depth, double top) {
      node.x = 24 + depth * 300.0;
      node.y = top + (node.subtree - node.height) / 2;
      width = math.max(width, node.x + 268);
      var childTop = top;
      for (final child in node.children) {
        place(child, depth + 1, childTop);
        edges.add((node, child));
        childTop += child.subtree + 20;
      }
    }

    place(measured, 0, 24);
    height = measured.subtree + 48;
  }
  final nodes = <_LayoutNode>[];
  final edges = <(_LayoutNode, _LayoutNode)>[];
  double width = 0, height = 0;

  String _path(_LayoutNode from, _LayoutNode to) {
    final x = from.rect.right, y = from.rect.center.dy;
    return 'M $x $y C ${x + 28} $y ${to.x - 28} ${to.rect.center.dy} ${to.x} ${to.rect.center.dy}';
  }

  String svg(String title) {
    final xml = XmlBuilder();
    xml.element('svg', namespaces: {
      'http://www.w3.org/2000/svg': ''
    }, attributes: {
      'width': '$width',
      'height': '$height',
      'viewBox': '0 0 $width $height',
    }, nest: () {
      xml.element('title', nest: _xmlText(title));
      xml.element('rect',
          attributes: {'width': '100%', 'height': '100%', 'fill': '#ffffff'});
      for (final (from, to) in edges) {
        xml.element('path', attributes: {
          'd': _path(from, to),
          'fill': 'none',
          'stroke': '#938269',
          'stroke-width': '2'
        });
      }
      for (final node in nodes) {
        xml.element('rect', attributes: {
          'x': '${node.x}',
          'y': '${node.y}',
          'width': '244',
          'height': '${node.height}',
          'rx': '10',
          'fill': '#f1e7d6',
          'stroke': '#b4a082'
        });
        for (final line in node.painter.computeLineMetrics()) {
          final pos = node.painter
              .getPositionForOffset(Offset(0, line.baseline - line.ascent / 2));
          final range = node.painter.getLineBoundary(pos);
          final label = node.painter.text!
              .toPlainText()
              .substring(range.start, range.end)
              .replaceAll(RegExp(r'[\r\n]'), '');
          xml.element('text',
              attributes: {
                'x': '${node.x + 12}',
                'y': '${node.y + 12 + line.baseline}',
                'font-size': '16',
                'font-family': 'sans-serif',
                'fill': '#28241f',
                'xml:space': 'preserve',
              },
              nest: _xmlText(label));
        }
      }
    });
    return xml.buildDocument().toXmlString();
  }

  Future<Uint8List> png() async {
    // Bound raster memory independently of graph size. SVG retains full scale.
    final scale = math.min(
        2.0,
        math.min(8192 / math.max(width, height),
            math.sqrt(16000000 / (width * height))));
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height),
        Paint()..color = const Color(0xffffffff));
    for (final (from, to) in edges) {
      final x = from.rect.right, y = from.rect.center.dy;
      canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..cubicTo(x + 28, y, to.x - 28, to.rect.center.dy, to.x,
                to.rect.center.dy),
          Paint()
            ..color = const Color(0xff938269)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    for (final node in nodes) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(node.rect, const Radius.circular(10)),
          Paint()..color = const Color(0xfff1e7d6));
      node.painter.paint(canvas, Offset(node.x + 12, node.y + 12));
    }
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(math.max(1, (width * scale).ceil()),
          math.max(1, (height * scale).ceil()));
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) throw StateError('PNG encoding failed');
        return bytes.buffer
            .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  void dispose() {
    for (final node in nodes) {
      node.painter.dispose();
    }
  }
}
