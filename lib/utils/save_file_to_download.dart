import 'dart:io';
import 'package:modu_reader/utils/platform_utils.dart';

import 'package:modu_reader/utils/get_path/get_download_path.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:modu_reader/utils/harmony_file_export.dart';
import 'package:path_provider/path_provider.dart';

Future<String?> saveFileToDownload(
    {Uint8List? bytes,
    String? sourceFilePath,
    required String fileName,
    String? mimeType,
    @visibleForTesting AnxPlatformEnum? platform}) async {
  switch (platform ?? AnxPlatform.type) {
    case AnxPlatformEnum.android:
      // The plugin's byte-data branch uses Java's default temp directory,
      // which is not writable on every Android device. Use app-owned cache.
      if (bytes != null) {
        final staging =
            await (await getTemporaryDirectory()).createTemp('modu-export-');
        try {
          final file = File('${staging.path}/export');
          await file.writeAsBytes(bytes, flush: true);
          return await FlutterFileDialog.saveFile(
            params: SaveFileDialogParams(
              sourceFilePath: file.path,
              fileName: fileName,
              mimeTypesFilter: [mimeType ?? 'application/zip'],
            ),
          );
        } finally {
          await staging.delete(recursive: true);
        }
      }
      return FlutterFileDialog.saveFile(
          params: SaveFileDialogParams(
        sourceFilePath: sourceFilePath,
        fileName: fileName,
        mimeTypesFilter: [mimeType ?? 'application/zip'],
      ));
    case AnxPlatformEnum.ios:
      SaveFileDialogParams params = SaveFileDialogParams(
        sourceFilePath: sourceFilePath,
        data: bytes,
        mimeTypesFilter: [mimeType ?? 'application/zip'],
        fileName: fileName,
      );
      final filePath = await FlutterFileDialog.saveFile(params: params);
      return filePath;
    case AnxPlatformEnum.ohos:
      return saveHarmonyFile(
          bytes: bytes, sourceFilePath: sourceFilePath, fileName: fileName);
    case AnxPlatformEnum.macos:
    case AnxPlatformEnum.linux:
      String? outputFile = await FilePicker.platform.saveFile(
        fileName: fileName,
      );
      bytes ??= await File(sourceFilePath!).readAsBytes();
      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        return outputFile;
      }
      return outputFile;
    case AnxPlatformEnum.windows:
      final fileSavePath = '${await getDownloadPath()}/$fileName';
      final file = File(fileSavePath);

      if (!await file.exists()) {
        await file.create(recursive: true);
      }

      bytes ??= await File(sourceFilePath!).readAsBytes();
      await file.writeAsBytes(bytes);
      return fileSavePath;
  }
}
