import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/css_visual_style.dart';

const customCssProfileCount = 32;

class CustomCssProfile {
  const CustomCssProfile(
      {this.name = '',
      this.css = '',
      this.pattern = '',
      this.scope = 'all',
      this.visual});
  final String name;
  final String css;
  final String pattern;
  final String scope;
  final CssVisualStyle? visual;
  String get compiledCss => compileCss();
  String compileCss({String fontOrigin = ''}) => [
        visual?.css(
                scope: scope, highlight: isHighlight, fontOrigin: fontOrigin) ??
            '',
        css
      ].where((s) => s.trim().isNotEmpty).join('\n\n');
  bool get isHighlight => pattern.isNotEmpty;
  bool get isEmpty =>
      name.isEmpty &&
      css.isEmpty &&
      pattern.isEmpty &&
      (visual?.values.isEmpty ?? true);

  Map<String, String> toJson() => {
        'name': name,
        'css': css,
        'pattern': pattern,
        'scope': scope,
        if (visual != null) 'visual': visual!.encode()
      };

  factory CustomCssProfile.fromJson(Object? value) {
    if (value is! Map) return const CustomCssProfile();
    return CustomCssProfile(
      name: value['name'] is String ? value['name'] as String : '',
      css: value['css'] is String ? value['css'] as String : '',
      visual: value['visual'] is String
          ? CssVisualStyle.decode(value['visual'] as String)
          : null,
      pattern: value['pattern'] is String ? value['pattern'] as String : '',
      scope: const ['all', 'title', 'body'].contains(value['scope'])
          ? value['scope'] as String
          : 'all',
    );
  }
}

// Templates are copied into a free slot, never automatically enabled.
const _legacyCssTemplates = <CustomCssProfile>[
  CustomCssProfile(
      name: '横排小说 · 段落',
      css:
          'p { text-indent: 2em !important; margin-block: 0.6em !important; }'),
  CustomCssProfile(
      name: '竖排古籍 · 间距',
      css:
          'p { line-height: 1.8 !important; letter-spacing: 0.08em !important; }\n/* 请同时在阅读设置中选择竖排 */'),
  CustomCssProfile(
      name: '精排 · 图片自适应',
      css: 'img, svg { max-inline-size: 100%; object-fit: contain; }'),
  CustomCssProfile(
      name: '标题 · 居中', css: 'h1, h2, h3 { text-align: center !important; }'),
  CustomCssProfile(
      name: '长文 · 舒适间距',
      css:
          'p { line-height: 1.8 !important; margin-block: 0.8em !important; }'),
  CustomCssProfile(
      name: '英文 · 段落',
      css:
          'p:lang(en) { text-indent: 0 !important; hyphens: auto; overflow-wrap: break-word; }'),
  CustomCssProfile(
      name: '诗词 · 保留换行',
      css:
          '.poem, .poetry, .verse { white-space: pre-line !important; text-align: center !important; text-indent: 0 !important; }\n/* 按书内实际类名修改选择器，不将全部正文视为诗词 */'),
  CustomCssProfile(
      name: '表格 · 自动换行',
      css:
          'table { max-inline-size: 100% !important; table-layout: fixed; }\nth, td { overflow-wrap: anywhere; }'),
  CustomCssProfile(
      name: '对白 · 变色',
      pattern: '“[^”\\n]+”|「[^」\\n]+」|『[^』\\n]+』',
      scope: 'body',
      css: 'color: #c0392b;'),
  CustomCssProfile(
      name: '对白 · 波浪线',
      pattern: '“[^”\\n]+”|「[^」\\n]+」|『[^』\\n]+』',
      scope: 'body',
      css:
          'text-decoration-line: underline;\ntext-decoration-style: wavy;\ntext-decoration-color: #c0392b;'),
  CustomCssProfile(
      name: '关键词 · 高亮',
      pattern: '关键词',
      css: 'background-color: #ffe082;\ncolor: #212121;'),
  CustomCssProfile(
      name: '日期 · 高亮',
      pattern: r'\d{4}年(?:\d{1,2}月)?(?:\d{1,2}日)?',
      css: 'background-color: #c8e6c9;\ncolor: #1b5e20;'),
  CustomCssProfile(
      name: '标题 · 下划线',
      pattern: '.+',
      scope: 'title',
      css: 'text-decoration-line: underline;\ntext-decoration-style: solid;'),
];

// Existing saved CSS is never parsed or rewritten. Only new built-in templates
// use structured controls, with custom code retained for specialist selectors.
final customCssTemplates = [
  for (var i = 0; i < _legacyCssTemplates.length; i++)
    CustomCssProfile(
      name: _legacyCssTemplates[i].name,
      pattern: _legacyCssTemplates[i].pattern,
      scope: i < 2 || i == 4
          ? 'body'
          : i == 3
              ? 'title'
              : _legacyCssTemplates[i].scope,
      css: const [2, 5, 6, 7].contains(i) ? _legacyCssTemplates[i].css : '',
      visual: CssVisualStyle(switch (i) {
        0 => {'indent': 2.0, 'paragraphGap': 0.6},
        1 => {'lineHeight': 1.8, 'spacing': 0.08},
        3 => {'align': 'center'},
        4 => {'lineHeight': 1.8, 'paragraphGap': 0.8},
        8 => {'color': '#c0392b'},
        9 => {'decoration': 'wavy', 'decorationColor': '#c0392b'},
        10 => {'background': '#ffe082', 'color': '#212121'},
        11 => {'background': '#c8e6c9', 'color': '#1b5e20'},
        12 => {'decoration': 'solid'},
        _ => const <String, Object>{},
      }),
    ),
];

class CustomCssSelection {
  const CustomCssSelection(
      {required this.index, required this.enabled, this.indices});
  final int index;
  final bool enabled;
  final List<int>? indices;
  List<int> get activeIndices => indices ?? [index];
  Map<String, Object> toJson() =>
      {'index': index, 'enabled': enabled, 'indices': activeIndices};
}

// Local-only mapping: do not transfer numeric database IDs to another device.
// Creation time prevents a reused ID from inheriting an unrelated book's CSS;
// changing the title or replacing the file does not lose this preference.
String customCssBookKey(Book book) =>
    '${book.id}:${book.createTime.toUtc().microsecondsSinceEpoch}';
