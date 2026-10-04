/// Gate the new original-page menu, independent of saved layout preferences.
enum DocumentReadingMode {
  standard,
  pdf,
  imageEpub;

  // Keep the legacy enum/storage identifier for existing EPUB preferences.
  // These decoded HTML containers now share the same scanned-image reader.
  static bool supportsImageBook(String path) =>
      RegExp(r'\.(epub|mobi|azw3|fb2)$', caseSensitive: false).hasMatch(path);

  bool get hasDocumentMenu => this != standard;

  String get storageValue => switch (this) {
        standard => 'standard',
        pdf => 'pdf',
        imageEpub => 'image-epub',
      };

  static DocumentReadingMode fromDetection(String path, Object? detection) {
    final file = path.toLowerCase();
    if (file.endsWith('.pdf') && detection == 'pdf') return pdf;
    if (supportsImageBook(file) && detection == 'image-epub') return imageEpub;
    return standard;
  }
}
