import 'dart:io';

import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fontPreviewProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, filename) async {
  if (filename.contains('/') || filename.contains('\\')) return null;
  try {
    final file = File('${getFontDir().path}/$filename');
    final bytes = await file.readAsBytes();
    final family = 'preview_${sha256.convert(bytes)}';
    final loader = FontLoader(family);
    loader.addFont(Future.value(bytes.buffer.asByteData()));
    await loader.load();
    return family;
  } catch (_) {
    return null;
  }
});

Widget fontPreviewBuilder(String? filename, Widget Function(String?) builder) {
  if (filename == null ||
      !RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(filename)) {
    return builder(null);
  }
  return Consumer(
      builder: (context, ref, _) =>
          builder(ref.watch(fontPreviewProvider(filename)).asData?.value));
}

class FontNamePreview extends StatelessWidget {
  const FontNamePreview(this.label, {super.key, this.filename});
  final String label;
  final String? filename;

  @override
  Widget build(BuildContext context) {
    return fontPreviewBuilder(
        filename,
        (family) => Text(label,
            style: family == null ? null : TextStyle(fontFamily: family)));
  }
}
