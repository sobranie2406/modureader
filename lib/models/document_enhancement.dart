class DocumentEnhancement {
  const DocumentEnhancement(
      {this.ink = 0,
      this.contrast = 0,
      this.darken = 0,
      this.whiten = 0,
      this.paperMode = 'preserve',
      this.sharpen = 0,
      this.watermark = 0});
  final double ink, contrast, darken, whiten, sharpen, watermark;
  final String paperMode;
  static const limits = <String, (double, double)>{
    'ink': (0, 15),
    'contrast': (-100, 100),
    'darken': (0, 100),
    'whiten': (0, 200),
    'sharpen': (0, 100),
    'watermark': (0, 100),
  };
  Map<String, double> get values => {
        'ink': ink,
        'contrast': contrast,
        'darken': darken,
        'whiten': whiten,
        'sharpen': sharpen,
        'watermark': watermark
      };
  Map<String, dynamic> toJson() => {
        ...values,
        if (paperMode != 'preserve') 'paperMode': paperMode,
      };
  bool get enabled => values.values.any((v) => v != 0);
  factory DocumentEnhancement.fromJson(dynamic value) {
    if (value == null) return const DocumentEnhancement();
    if (value is! Map) throw const FormatException('Invalid enhancement');
    final mode = value['paperMode'] ?? 'preserve';
    if (!['preserve', 'text'].contains(mode)) {
      throw const FormatException('Invalid paper mode');
    }
    final fields = <String, double>{};
    for (final entry in limits.entries) {
      final v = value[entry.key] ?? 0;
      if (v is! num ||
          !v.isFinite ||
          v < entry.value.$1 ||
          v > entry.value.$2) {
        throw const FormatException('Invalid enhancement value');
      }
      fields[entry.key] = v.toDouble();
    }
    return DocumentEnhancement(
        ink: fields['ink']!,
        contrast: fields['contrast']!,
        darken: fields['darken']!,
        whiten: fields['whiten']!,
        paperMode: mode as String,
        sharpen: fields['sharpen']!,
        watermark: fields['watermark']!);
  }
  DocumentEnhancement withValue(String key, double value) {
    if (!limits.containsKey(key)) throw ArgumentError.value(key);
    return DocumentEnhancement.fromJson({...toJson(), key: value});
  }

  DocumentEnhancement withPaperMode(String mode) =>
      DocumentEnhancement.fromJson({...toJson(), 'paperMode': mode});
}
