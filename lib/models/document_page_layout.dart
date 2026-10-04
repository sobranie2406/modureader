import 'dart:ui';

/// Normalized against the original upright viewport, before user rotation.
class DocumentPageLayout {
  const DocumentPageLayout(
      {this.crop = const Rect.fromLTWH(0, 0, 1, 1),
      this.preset = 'single',
      this.order = 'row-ltr',
      this.autoCrop = false,
      this.autoMargin = .03});

  final Rect crop;
  final String preset;
  final String order;

  /// The stored crop is only an editor preview when automatic mode is active.
  /// The reader detects each original page independently before splitting it.
  final bool autoCrop;
  final double autoMargin;
  static const grids = <String, (int, int)>{
    'single': (1, 1),
    'horizontal2': (2, 1),
    'vertical2': (1, 2),
    'four': (2, 2),
    'horizontal6': (3, 2),
    'vertical6': (2, 3),
    'nine': (3, 3),
  };
  static const orders = ['row-ltr', 'row-rtl', 'column-ltr', 'column-rtl'];

  void validate() {
    if (![crop.left, crop.top, crop.width, crop.height]
            .every((v) => v.isFinite) ||
        crop.left < 0 ||
        crop.top < 0 ||
        crop.width <= 0 ||
        crop.height <= 0 ||
        crop.right > 1 + 1e-9 ||
        crop.bottom > 1 + 1e-9 ||
        !grids.containsKey(preset) ||
        !orders.contains(order) ||
        !autoMargin.isFinite ||
        autoMargin < 0 ||
        autoMargin > .2) {
      throw const FormatException('Invalid document page layout');
    }
  }

  DocumentPageLayout copyWith(
          {Rect? crop,
          String? preset,
          String? order,
          bool? autoCrop,
          double? autoMargin}) =>
      DocumentPageLayout(
          crop: crop ?? this.crop,
          preset: preset ?? this.preset,
          order: order ?? this.order,
          autoCrop: autoCrop ?? this.autoCrop,
          autoMargin: autoMargin ?? this.autoMargin);

  List<Rect> get regions {
    validate();
    final (columns, rows) = grids[preset]!;
    final cells = <(int, int)>[
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++) (row, column),
    ];
    final direction = order.endsWith('rtl') ? -1 : 1;
    cells.sort((a, b) {
      final row = a.$1.compareTo(b.$1);
      final column = direction * a.$2.compareTo(b.$2);
      return order.startsWith('row')
          ? (row != 0 ? row : column)
          : (column != 0 ? column : row);
    });
    return cells
        .map((cell) => Rect.fromLTWH(
            crop.left + crop.width * cell.$2 / columns,
            crop.top + crop.height * cell.$1 / rows,
            crop.width / columns,
            crop.height / rows))
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    validate();
    return {
      'crop': {
        'x': crop.left,
        'y': crop.top,
        'width': crop.width,
        'height': crop.height
      },
      'preset': preset,
      'order': order,
      if (autoCrop) 'autoCrop': true,
      if (autoCrop || autoMargin != .03) 'autoMargin': autoMargin,
    };
  }

  factory DocumentPageLayout.fromJson(dynamic value) {
    if (value is! Map || value['crop'] is! Map) {
      throw const FormatException('Invalid layout');
    }
    final r = value['crop'] as Map;
    if (!['x', 'y', 'width', 'height'].every((key) => r[key] is num) ||
        value['preset'] is! String ||
        value['order'] is! String ||
        (value.containsKey('autoCrop') && value['autoCrop'] is! bool) ||
        (value.containsKey('autoMargin') && value['autoMargin'] is! num)) {
      throw const FormatException('Invalid layout fields');
    }
    final result = DocumentPageLayout(
        crop: Rect.fromLTWH(
            (r['x'] as num).toDouble(),
            (r['y'] as num).toDouble(),
            (r['width'] as num).toDouble(),
            (r['height'] as num).toDouble()),
        preset: value['preset'],
        order: value['order'],
        autoCrop: value['autoCrop'] == true,
        autoMargin: (value['autoMargin'] as num?)?.toDouble() ?? .03);
    result.validate();
    return result;
  }
}

enum DocumentLayoutScope { current, all, odd, even }

class DocumentLayoutConfig {
  const DocumentLayoutConfig(
      {this.all, this.odd, this.even, this.pages = const {}});
  final DocumentPageLayout? all, odd, even;
  final Map<int, DocumentPageLayout> pages;

  DocumentPageLayout forPage(int page) {
    if (page < 0) throw ArgumentError.value(page);
    return pages[page] ??
        (page.isEven ? odd : even) ??
        all ??
        const DocumentPageLayout();
  }

  /// Applying a scope replaces overrides INSIDE that scope; other pages remain
  /// intact. Thus "all" actually affects all pages, not just unconfigured pages.
  DocumentLayoutConfig apply(
      DocumentLayoutScope scope, int page, DocumentPageLayout layout) {
    layout.validate();
    if (page < 0) throw ArgumentError.value(page);
    final updated = Map<int, DocumentPageLayout>.from(pages);
    switch (scope) {
      case DocumentLayoutScope.all:
        return DocumentLayoutConfig(all: layout);
      case DocumentLayoutScope.current:
        updated[page] = layout;
        return DocumentLayoutConfig(
            all: all, odd: odd, even: even, pages: Map.unmodifiable(updated));
      case DocumentLayoutScope.odd:
      case DocumentLayoutScope.even:
        updated.removeWhere(
            (index, _) => index.isEven == (scope == DocumentLayoutScope.odd));
        return DocumentLayoutConfig(
            all: all,
            odd: scope == DocumentLayoutScope.odd ? layout : odd,
            even: scope == DocumentLayoutScope.even ? layout : even,
            pages: Map.unmodifiable(updated));
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        if (all != null) 'all': all!.toJson(),
        if (odd != null) 'odd': odd!.toJson(),
        if (even != null) 'even': even!.toJson(),
        'pages': {
          for (final entry in pages.entries)
            '${entry.key}': entry.value.toJson()
        }
      };

  factory DocumentLayoutConfig.fromJson(dynamic value) {
    if (value is! Map || value['version'] != 1 || value['pages'] is! Map) {
      throw const FormatException('Unsupported document layout');
    }
    final pages = <int, DocumentPageLayout>{};
    for (final entry in (value['pages'] as Map).entries) {
      final index = int.tryParse(entry.key.toString());
      if (index == null || index < 0) {
        throw const FormatException('Invalid original page');
      }
      pages[index] = DocumentPageLayout.fromJson(entry.value);
    }
    DocumentPageLayout? read(String key) =>
        value[key] == null ? null : DocumentPageLayout.fromJson(value[key]);
    return DocumentLayoutConfig(
        all: read('all'),
        odd: read('odd'),
        even: read('even'),
        pages: Map.unmodifiable(pages));
  }
}

/// Additional clockwise rotation; PDF's intrinsic rotation is already applied.
Rect rotateDocumentRegion(Rect rect, int rotation) => switch (rotation % 360) {
      90 => Rect.fromLTWH(1 - rect.bottom, rect.left, rect.height, rect.width),
      180 =>
        Rect.fromLTWH(1 - rect.right, 1 - rect.bottom, rect.width, rect.height),
      270 => Rect.fromLTWH(rect.top, 1 - rect.right, rect.height, rect.width),
      0 => rect,
      _ => throw ArgumentError.value(rotation),
    };
