/// Coordinates are fractions of the uncropped source page, not screen pixels.
class DocumentImageRect {
  const DocumentImageRect(this.x, this.y, this.width, this.height);
  final double x, y, width, height;
  bool get valid =>
      [x, y, width, height].every((v) => v.isFinite) &&
      x >= 0 &&
      y >= 0 &&
      width > 0 &&
      height > 0 &&
      x + width <= 1.000001 &&
      y + height <= 1.000001;
  List<double> toJson() => [x, y, width, height];
  static DocumentImageRect? decode(dynamic value) {
    if (value is! List || value.length != 4 || value.any((v) => v is! num)) {
      return null;
    }
    final r = DocumentImageRect(
        (value[0] as num).toDouble(),
        (value[1] as num).toDouble(),
        (value[2] as num).toDouble(),
        (value[3] as num).toDouble());
    return r.valid ? r : null;
  }

  DocumentImageRect within(DocumentImageRect crop) => DocumentImageRect(
      crop.x + x * crop.width,
      crop.y + y * crop.height,
      width * crop.width,
      height * crop.height);
}

class DocumentTextRegion {
  const DocumentTextRegion(this.start, this.end, this.rect,
      {this.bubble, this.tapToReveal = false});
  final int start, end;
  final DocumentImageRect rect;
  final DocumentImageRect? bubble;
  final bool tapToReveal;
  Map<String, Object> toJson() => {
        'start': start,
        'end': end,
        'rect': rect.toJson(),
        if (bubble != null) 'bubble': bubble!.toJson(),
        if (tapToReveal) 'tapToReveal': true
      };
  static DocumentTextRegion? decode(dynamic value, int length) {
    if (value is! Map) {
      return null;
    }
    final start = value['start'], end = value['end'];
    // WKWebView may return integral JavaScript offsets as doubles.
    if (start is! num ||
        end is! num ||
        !start.isFinite ||
        !end.isFinite ||
        start < 0 ||
        end <= start ||
        end > length ||
        start != start.toInt() ||
        end != end.toInt()) {
      return null;
    }
    final rect = DocumentImageRect.decode(value['rect']);
    if (rect == null) return null;
    return DocumentTextRegion(start.toInt(), end.toInt(), rect,
        bubble: DocumentImageRect.decode(value['bubble']),
        tapToReveal: value['tapToReveal'] == true);
  }
}

class DocumentTextResult {
  DocumentTextResult(this.text, [List<DocumentTextRegion> regions = const []])
      : regions = List.unmodifiable(regions) {
    if (text.length > 1000000 ||
        regions.length > 4096 ||
        regions.any((r) =>
            r.start < 0 ||
            r.end <= r.start ||
            r.end > text.length ||
            !r.rect.valid ||
            r.bubble?.valid == false)) {
      throw const FormatException('Invalid document text geometry');
    }
  }
  final String text;
  final List<DocumentTextRegion> regions;
  Map<String, Object> toJson() =>
      {'text': text, 'regions': regions.map((r) => r.toJson()).toList()};
  factory DocumentTextResult.decode(Map value) {
    final text = value['text'];
    final regions = value['regions'] ?? const [];
    if (text is! String || regions is! List || regions.length > 4096) {
      throw const FormatException('Invalid document text result');
    }
    return DocumentTextResult(
        text,
        regions.map((r) {
          final region = DocumentTextRegion.decode(r, text.length);
          if (region == null) {
            throw const FormatException('Invalid source region');
          }
          return region;
        }).toList());
  }
  DocumentTextResult within(DocumentImageRect crop) => DocumentTextResult(
      text,
      regions
          .map((r) => DocumentTextRegion(r.start, r.end, r.rect.within(crop),
              bubble: r.bubble?.within(crop), tapToReveal: r.tapToReveal))
          .toList());
}
