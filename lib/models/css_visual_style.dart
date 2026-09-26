import 'dart:convert';

/// Null/absent values inherit the book style; only enabled modules emit CSS.
class CssVisualStyle {
  const CssVisualStyle([this.values = const {}]);
  final Map<String, Object> values;

  static const ranges = <String, (double, double)>{
    'weight': (100, 900),
    'size': (8, 64),
    'lineHeight': (1, 3),
    'spacing': (-0.1, 0.5),
    'indent': (0, 4),
    'paragraphGap': (0, 3),
    'thickness': (0.5, 6),
    'offset': (-4, 12),
  };
  static const colors = ['color', 'background', 'decorationColor'];
  static const choices = {
    'decoration': ['none', 'solid', 'dashed', 'wavy', 'emphasis', 'svg'],
    'align': ['start', 'center', 'end', 'justify'],
    'font': ['serif', 'sans-serif', 'monospace'],
  };

  CssVisualStyle withValue(String key, Object? value) => CssVisualStyle({
        ...values, // Copy before editing; preset maps may be const.
        if (value != null) key: value,
      }..removeWhere((k, _) => k == key && value == null));

  String encode() => jsonEncode(values);
  static CssVisualStyle decode(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map) throw const FormatException('Invalid visual CSS');
    final result = <String, Object>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (ranges.containsKey(key)) {
        final (min, max) = ranges[key]!;
        if (value is! num || !value.isFinite || value < min || value > max) {
          throw const FormatException('Invalid visual CSS number');
        }
      } else if (colors.contains(key)) {
        if (value is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
          throw const FormatException('Invalid visual CSS color');
        }
      } else if (choices.containsKey(key)) {
        if (!choices[key]!.contains(value)) {
          throw const FormatException('Invalid visual CSS choice');
        }
      } else if (key == 'fontFile') {
        if (value is! String ||
            value.length > 255 ||
            value.contains(RegExp(r'[/\\\x00-\x1f]')) ||
            !RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(value)) {
          throw const FormatException('Invalid visual CSS font');
        }
      } else if (key == 'italic') {
        if (value is! bool) {
          throw const FormatException('Invalid visual CSS flag');
        }
      } else if (key == 'backgroundImage' || key == 'underlineImage') {
        if (value is! String ||
            value.length > 400000 ||
            !RegExp(r'^data:image/(png|jpeg|webp|svg\+xml);base64,[A-Za-z0-9+/=]+$')
                .hasMatch(value)) {
          throw const FormatException('Invalid visual CSS image');
        }
      } else {
        throw const FormatException('Unknown visual CSS option');
      }
      result[key as String] = value as Object;
    }
    return CssVisualStyle(Map.unmodifiable(result));
  }

  String css(
      {required String scope,
      required bool highlight,
      String fontOrigin = ''}) {
    // Validate even direct callers before inserting values into a stylesheet.
    decode(encode());
    final lines = <String>[];
    void add(String property, Object? value, [String unit = '']) {
      if (value != null) {
        lines.add('$property: $value$unit${highlight ? '' : ' !important'};');
      }
    }

    add('color', values['color']);
    add('background-color', values['background']);
    final decoration = values['decoration'];
    if (decoration != null && decoration != 'svg') {
      add('text-decoration-line', decoration == 'none' ? 'none' : 'underline');
      if (decoration != 'none') {
        add('text-decoration-style',
            decoration == 'emphasis' ? 'solid' : decoration);
        add('text-decoration-thickness',
            values['thickness'] ?? (decoration == 'emphasis' ? 4 : 1), 'px');
        add('text-decoration-color', values['decorationColor']);
        if (!highlight) {
          add('text-underline-offset', values['offset'] ?? 2, 'px');
        }
      }
    }
    if (!highlight) {
      final file = values['fontFile'];
      add('font-family',
          file == null ? values['font'] : '"${_fontFamily(file as String)}"');
      add('font-weight', values['weight']);
      add('font-size', values['size'], 'px');
      if (values.containsKey('italic')) {
        add('font-style', values['italic'] == true ? 'italic' : 'normal');
      }
      add('line-height', values['lineHeight']);
      add('letter-spacing', values['spacing'], 'em');
      add('text-indent', values['indent'], 'em');
      add('margin-block', values['paragraphGap'], 'em');
      add('text-align', values['align']);
      if (values['backgroundImage'] != null) {
        add('background-image', 'url("${values['backgroundImage']}")');
        add('background-size', 'cover');
      }
      if (decoration == 'svg' && values['underlineImage'] != null) {
        add('background-image', 'url("${values['underlineImage']}")');
        add('background-repeat', 'repeat-x');
        add('background-position', 'left bottom');
        add('background-size', 'auto ${values['thickness'] ?? 2}px');
        add('padding-bottom', '${values['offset'] ?? 2}px');
      }
    }
    if (lines.isEmpty) return '';
    if (highlight) return lines.join('\n');
    const headings = 'h1, h2, h3, h4, h5, h6, [role="heading"]';
    const body = 'p, li, blockquote, td, th';
    final selector = scope == 'title'
        ? headings
        : scope == 'body'
            ? body
            : '$body, $headings';
    final file = values['fontFile'];
    final face = file == null
        ? ''
        : '@font-face { font-family: "${_fontFamily(file as String)}"; src: url("$fontOrigin/fonts/${Uri.encodeComponent(file)}"); font-display: swap; }\n';
    return '$face$selector {\n  ${lines.join('\n  ')}\n}';
  }

  String _fontFamily(String file) =>
      'moduCssFont${utf8.encode(file).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}
