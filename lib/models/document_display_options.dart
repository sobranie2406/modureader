class DocumentDisplayOptions {
  const DocumentDisplayOptions(
      {this.border = false,
      this.separators = true,
      this.grayscale = false,
      this.hideWatermarks = false,
      this.tapPan = false,
      this.swipe = 'horizontal',
      this.swipeMenu = false,
      this.autoSeconds = 0});
  final bool border, separators, grayscale, hideWatermarks, tapPan, swipeMenu;
  final String swipe;
  final int autoSeconds;
  Map<String, dynamic> toJson() => {
        'border': border,
        'separators': separators,
        'grayscale': grayscale,
        'hideWatermarks': hideWatermarks,
        'tapPan': tapPan,
        'swipe': swipe,
        'swipeMenu': swipe == 'vertical' ? false : swipeMenu,
        'autoSeconds': autoSeconds
      };
  factory DocumentDisplayOptions.fromJson(dynamic value) {
    if (value == null) return const DocumentDisplayOptions();
    if (value is! Map) throw const FormatException('Invalid document display');
    final data = {...const DocumentDisplayOptions().toJson(), ...value};
    if ([
          'border',
          'separators',
          'grayscale',
          'hideWatermarks',
          'tapPan',
          'swipeMenu'
        ].any((key) => data[key] is! bool) ||
        !['horizontal', 'reverse', 'vertical', 'tap'].contains(data['swipe']) ||
        data['autoSeconds'] is! int ||
        data['autoSeconds'] < 0 ||
        data['autoSeconds'] > 600 ||
        (data['autoSeconds'] > 0 && data['autoSeconds'] < 5)) {
      throw const FormatException('Invalid document display');
    }
    return DocumentDisplayOptions(
        border: data['border'],
        separators: data['separators'],
        grayscale: data['grayscale'],
        hideWatermarks: data['hideWatermarks'],
        tapPan: data['tapPan'],
        swipe: data['swipe'],
        swipeMenu: data['swipe'] == 'vertical' ? false : data['swipeMenu'],
        autoSeconds: data['autoSeconds']);
  }
  DocumentDisplayOptions change(String key, Object value) =>
      DocumentDisplayOptions.fromJson({...toJson(), key: value});
}
