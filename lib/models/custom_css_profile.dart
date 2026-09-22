import 'package:anx_reader/models/book.dart';

const customCssProfileCount = 8;

class CustomCssProfile {
  const CustomCssProfile({this.name = '', this.css = ''});
  final String name;
  final String css;

  Map<String, String> toJson() => {'name': name, 'css': css};

  factory CustomCssProfile.fromJson(Object? value) {
    if (value is! Map) return const CustomCssProfile();
    return CustomCssProfile(
      name: value['name'] is String ? value['name'] as String : '',
      css: value['css'] is String ? value['css'] as String : '',
    );
  }
}

class CustomCssSelection {
  const CustomCssSelection({required this.index, required this.enabled});
  final int index;
  final bool enabled;
  Map<String, Object> toJson() => {'index': index, 'enabled': enabled};
}

// Local-only mapping: do not transfer numeric database IDs to another device.
// Creation time prevents a reused ID from inheriting an unrelated book's CSS;
// changing the title or replacing the file does not lose this preference.
String customCssBookKey(Book book) =>
    '${book.id}:${book.createTime.toUtc().microsecondsSinceEpoch}';
