import 'dart:io';
import 'package:modu_reader/service/book_import_source.dart';
import 'package:modu_reader/l10n/modu_strings.dart';

import 'package:modu_reader/config/shared_preference_provider.dart';
import 'package:modu_reader/l10n/generated/L10n.dart';
import 'package:modu_reader/main.dart';
import 'package:modu_reader/models/font_model.dart';
import 'package:modu_reader/service/book_player/book_player_server.dart';
import 'package:modu_reader/service/book_player/reader_font_response.dart';
import 'package:modu_reader/utils/font_parser.dart';
import 'package:modu_reader/utils/get_path/get_base_path.dart';
import 'package:modu_reader/utils/toast/common.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';

enum FontTarget { body, english }

Future<List<PlatformFile>> discoverFontFiles(Directory directory) async {
  final files = <PlatformFile>[];
  await for (final entry
      in directory.list(recursive: true, followLinks: false)) {
    if (entry is File &&
        RegExp(r'\.(ttf|otf)$', caseSensitive: false).hasMatch(entry.path)) {
      files.add(PlatformFile(
          name: entry.uri.pathSegments.last,
          path: entry.path,
          size: await entry.length()));
    }
  }
  files.sort((a, b) => a.path!.compareTo(b.path!));
  return files;
}

Future<void> importFont({
  void Function(FontModel)? onApplied,
  FontTarget target = FontTarget.body,
  bool folder = false,
}) async {
  final mobileFolder = folder && (Platform.isAndroid || Platform.isIOS);
  try {
    List<PlatformFile> files;
    if (mobileFolder) {
      final entries = await MobileBookFolder.pick(extensions: ['ttf', 'otf']);
      if (entries == null) return;
      final staged = await MobileBookFolder.stage(entries);
      files = [
        for (final file in staged)
          PlatformFile(
              name: file.uri.pathSegments.last,
              path: file.path,
              size: await file.length())
      ];
    } else if (folder) {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) return;
      files = await discoverFontFiles(Directory(path));
    } else {
      final result = await FilePicker.platform.pickFiles(
        type: Platform.isAndroid || Platform.isIOS
            ? FileType.any
            : FileType.custom,
        allowedExtensions:
            Platform.isAndroid || Platform.isIOS ? null : ['ttf', 'otf'],
        allowMultiple: true,
      );
      if (result == null) return;
      files = result.files;
    }
    if (files.isEmpty) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        AnxToast.show(ModuStrings.text(
            context, '没有找到 TTF 或 OTF 字体文件。', 'No TTF or OTF fonts found.'));
      }
      return;
    }
    final imported = await importFontFiles(files,
        directory: getFontDir(),
        serverPort: Server().port,
        onApplied: onApplied,
        target: target,
        applySingle: !folder);
    final context = navigatorKey.currentContext;
    if (context != null && context.mounted) {
      final l10n = L10n.of(context);
      if (imported.applied) {
        AnxToast.show(l10n.fontImportedAndApplied(imported.font!.label));
      } else if (imported.imported > 0) {
        AnxToast.show(ModuStrings.format(
            context, '已导入 {count} 个字体', 'Imported {count} fonts',
            values: {'count': imported.imported}));
      }
      if (imported.failed > 0) {
        AnxToast.show(l10n.fontImportFailedCount(imported.failed));
      }
    }
  } finally {
    if (mobileFolder) await MobileBookFolder.release();
  }
}

class FontImportResult {
  const FontImportResult(
      {required this.font,
      required this.failed,
      this.imported = 0,
      this.applied = false});
  final FontModel? font;
  final int failed;
  final int imported;
  final bool applied;
}

/// Only a single-file selection changes the current reading font.
Future<FontImportResult> importFontFiles(
  Iterable<PlatformFile> files, {
  required Directory directory,
  required int serverPort,
  void Function(FontModel)? onApplied,
  FontTarget target = FontTarget.body,
  bool applySingle = true,
}) async {
  files = files.toList();
  var imported = 0;
  var applied = false;
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
      imported++;
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
  if (selected != null && applySingle && files.length == 1) {
    final prefs = Prefs();
    final key = target == FontTarget.english ? 'englishFont' : 'font';
    if (await prefs.prefs.setString(key, selected.toJson())) {
      prefs.notifyExternalChange();
      applied = true;
      onApplied?.call(selected);
    } else {
      return FontImportResult(
          font: null, failed: failed + 1, imported: imported);
    }
  }
  return FontImportResult(
      font: selected, failed: failed, imported: imported, applied: applied);
}
