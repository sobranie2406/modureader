class DocumentEnhancement {
  const DocumentEnhancement(
      {this.ink = 0,
      this.contrast = 0,
      this.darken = 0,
      this.whiten = 0,
      this.sharpen = 0,
      this.watermark = 0});
  final double ink, contrast, darken, whiten, sharpen, watermark;
  static const limits = <String, (double, double)>{
    'ink': (0, 15),
    'contrast': (-100, 100),
    'darken': (0, 100),
    'whiten': (0, 200),
    'sharpen': (0, 100),
    'watermark': (0, 100),
  };
  Map<String, double> toJson() => {
        'ink': ink,
        'contrast': contrast,
        'darken': darken,
        'whiten': whiten,
        'sharpen': sharpen,
        'watermark': watermark
      };
  bool get enabled => toJson().values.any((v) => v != 0);
  factory DocumentEnhancement.fromJson(dynamic value) {
    if (value == null) return const DocumentEnhancement();
    if (value is! Map) throw const FormatException('Invalid enhancement');
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
        sharpen: fields['sharpen']!,
        watermark: fields['watermark']!);
  }
  DocumentEnhancement withValue(String key, double value) {
    if (!limits.containsKey(key)) throw ArgumentError.value(key);
    return DocumentEnhancement.fromJson({...toJson(), key: value});
  }
}
