import 'dart:io';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:file_picker/file_picker.dart';

Future<void> importFont() async {
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['ttf', 'otf'],
    allowMultiple: true,
  );

  if (result == null) {
    return;
  }

  List<PlatformFile> files = result.files;
  for (var file in files) {
    final fontDir = getFontDir();
    try {
      await fontDir.create(recursive: true);
      final source = file.path;
      if (source == null) {
        throw const FileSystemException('Font file unavailable');
      }
      // Do not refresh the list or report success while a large font is copying.
      await File(source).copy('${fontDir.path}/${file.name}');
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        AnxToast.show(L10n.of(context).commonSuccess);
      }
    } on FileSystemException {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        AnxToast.show(L10n.of(context).commonFailed);
      }
    }
  }
}
