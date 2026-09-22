import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/book_player/reader_font_response.dart';
import 'package:anx_reader/utils/font_parser.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';

enum FontTarget { body, english }

Future<void> importFont({
  void Function(FontModel)? onApplied,
  FontTarget target = FontTarget.body,
}) async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['ttf', 'otf'],
    allowMultiple: true,
  );

  if (result == null) {
    return;
  }

  final imported = await importFontFiles(result.files,
      directory: getFontDir(),
      serverPort: Server().port,
      onApplied: onApplied,
      target: target);
  final context = navigatorKey.currentContext;
  if (context != null && context.mounted) {
    final l10n = L10n.of(context);
    if (imported.font != null) {
      AnxToast.show(l10n.fontImportedAndApplied(imported.font!.label));
    }
    if (imported.failed > 0) {
      AnxToast.show(l10n.fontImportFailedCount(imported.failed));
    }
  }
}

class FontImportResult {
  const FontImportResult({required this.font, required this.failed});
  final FontModel? font;
  final int failed;
}

/// Apply only the last successfully imported file, after its complete copy and
/// preference write. A cancelled picker never calls this function.
Future<FontImportResult> importFontFiles(
  Iterable<PlatformFile> files, {
  required Directory directory,
  required int serverPort,
  void Function(FontModel)? onApplied,
  FontTarget target = FontTarget.body,
}) async {
  FontModel? selected;
  var failed = 0;
  for (var file in files) {
    Directory? staging;
    try {
      final source = file.path;
      if (source == null ||
          file.name.contains('/') ||
          file.name.contains('\\') ||
          !RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(file.name)) {
        throw const FileSystemException('Font file unavailable');
      }
      await directory.create(recursive: true);
      staging = await directory.createTemp('.font-import-');
      final copied = await File(source).copy('${staging.path}/${file.name}');
      final label = getFontNameFromFile(copied);
      if (label == 'Invalid font file') {
        throw const FormatException('Invalid font file');
      }
      // A new family for changed bytes avoids reusing a previously loaded face
      // when the user replaces a font under the same filename.
      final hash = await sha256.bind(copied.openRead()).first;
      await copied.rename('${directory.path}/${file.name}');
      selected = FontModel(
          label: label,
          name: 'importedFont_$hash',
          path: readerFontUrl(file.name, serverPort));
    } on FileSystemException {
      failed++;
    } on FormatException {
      failed++;
    } on RangeError {
      failed++;
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
  if (selected != null) {
    final prefs = Prefs();
    final key = target == FontTarget.english ? 'englishFont' : 'font';
    if (await prefs.prefs.setString(key, selected.toJson())) {
      prefs.notifyExternalChange();
      onApplied?.call(selected);
    } else {
      return FontImportResult(font: null, failed: failed + 1);
    }
  }
  return FontImportResult(font: selected, failed: failed);
}
