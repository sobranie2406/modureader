import 'dart:convert';

import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/reader_font_response.dart';

class FontModel {
  final String label;
  final String name;
  String path;

  FontModel({
    required this.label,
    required this.name,
    required this.path,
  });

  String toJson() {
    return jsonEncode({'label': label, 'name': name, 'path': litePath});
  }

  String get litePath {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path).pathSegments.last;
    }
    // Stored filenames are raw: a literal "%20" must remain literal.
    return path.split('/').last;
  }

  static FontModel fromJson(String fontJson, {int? serverPort}) {
    final Map<String, dynamic> json = jsonDecode(fontJson);
    final name = json['name'] as String;
    final filename = json['path'] as String;
    return FontModel(
      label: json['label'],
      name: name,
      path: name == 'system' || name == 'book'
          ? filename
          : readerFontUrl(filename, serverPort ?? Server().port),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FontModel &&
          runtimeType == other.runtimeType &&
          litePath == other.litePath;

  @override
  int get hashCode => litePath.hashCode;
}
