import 'package:anx_reader/models/document_enhancement.dart';
import 'package:anx_reader/models/document_display_options.dart';

class PdfReadingView {
  const PdfReadingView(
      {this.zoom = 1,
      this.fit = 'screen',
      this.rotation = 0,
      this.mode = 'single',
      this.display = const DocumentDisplayOptions(),
      this.enhancement = const DocumentEnhancement()});
  final DocumentEnhancement enhancement;
  final DocumentDisplayOptions display;
  final double zoom;
  final String fit;
  final int rotation;
  final String mode;

  factory PdfReadingView.fromJson(dynamic json) {
    if (json is! Map) throw const FormatException('Invalid PDF view');
    final zoom = json['zoom'];
    final fit = json['fit'];
    final rotation = json['rotation'];
    final mode = json['mode'] ?? 'single';
    if (zoom is! num ||
        !zoom.isFinite ||
        zoom < 1 ||
        zoom > 15 ||
        !['screen', 'width'].contains(fit) ||
        rotation is! int ||
        ![0, 90, 180, 270].contains(rotation) ||
        !['single', 'scroll'].contains(mode)) {
      throw const FormatException('Invalid PDF view');
    }
    return PdfReadingView(
        zoom: zoom.toDouble(),
        fit: fit,
        rotation: rotation,
        mode: mode,
        display: DocumentDisplayOptions.fromJson(json['display']),
        enhancement: DocumentEnhancement.fromJson(json['enhancement']));
  }

  PdfReadingView copyWith(
          {double? zoom,
          String? fit,
          int? rotation,
          String? mode,
          DocumentDisplayOptions? display,
          DocumentEnhancement? enhancement}) =>
      PdfReadingView(
          zoom: zoom ?? this.zoom,
          fit: fit ?? this.fit,
          rotation: rotation ?? this.rotation,
          mode: mode ?? this.mode,
          display: display ?? this.display,
          enhancement: enhancement ?? this.enhancement);

  Map<String, dynamic> toJson() => {
        'zoom': zoom,
        'fit': fit,
        'rotation': rotation,
        'mode': mode,
        'display': display.toJson(),
        if (enhancement.enabled || enhancement.paperMode != 'preserve')
          'enhancement': enhancement.toJson()
      };
}
