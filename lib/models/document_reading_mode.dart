/// Gate the new original-page menu, independent of saved layout preferences.
enum DocumentReadingMode {
  standard,
  pdf,
  imageEpub;

  bool get hasDocumentMenu => this != standard;

  String get storageValue => switch (this) {
        standard => 'standard',
        pdf => 'pdf',
        imageEpub => 'image-epub',
      };

  static DocumentReadingMode fromDetection(String path, Object? detection) {
    final file = path.toLowerCase();
    if (file.endsWith('.pdf') && detection == 'pdf') return pdf;
    if (file.endsWith('.epub') && detection == 'image-epub') return imageEpub;
    return standard;
  }
}
