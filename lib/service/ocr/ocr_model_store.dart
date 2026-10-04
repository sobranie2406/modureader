import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'ocr_models.dart';

enum OcrDownloadSource { upstream, gitee }

/// The OCR pack is data, never a bundled asset or executable download.
class OcrModelStore {
  OcrModelStore(
      {this.directory,
      Dio? dio,
      this.model = OcrModels.defaultModel,
      this.downloadSource = OcrDownloadSource.upstream})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
            ));
  final Directory? directory;
  final Dio _dio;
  final OcrModelSpec model;
  OcrDownloadSource downloadSource;
  static bool _downloading = false;
  static final Set<String> _deleting = {};
  static final Map<String, int> _readers = {};

  /// Recognition holds this lease until its worker has released the model.
  Future<T> withModelFiles<T>(Future<T> Function() action) async {
    if (_downloading || _deleting.contains(model.id)) {
      throw StateError('OCR model files are busy');
    }
    _readers[model.id] = (_readers[model.id] ?? 0) + 1;
    try {
      return await action();
    } finally {
      final remaining = _readers[model.id]! - 1;
      if (remaining == 0) {
        _readers.remove(model.id);
      } else {
        _readers[model.id] = remaining;
      }
    }
  }

  Future<bool> hasLocalFiles() async {
    final dir = await root();
    for (final name in model.files.keys) {
      if (await File('${dir.path}/$name').exists() ||
          await File('${dir.path}/$name.part').exists()) {
        return true;
      }
    }
    return false;
  }

  /// Delete only catalogued model files, never the directory or user data.
  Future<void> deleteDownloaded() async {
    if (_downloading ||
        _deleting.contains(model.id) ||
        (_readers[model.id] ?? 0) > 0) {
      throw StateError('OCR model is in use');
    }
    _deleting.add(model.id);
    try {
      final dir = await root();
      final targets = <(String, FileSystemEntityType)>[];
      for (final name in model.files.keys) {
        if (!RegExp(r'^[a-zA-Z0-9_-]+\.onnx$').hasMatch(name)) {
          throw StateError('Invalid OCR model filename');
        }
        for (final suffix in ['', '.part']) {
          final path = '${dir.path}/$name$suffix';
          final type = await FileSystemEntity.type(path, followLinks: false);
          if (type == FileSystemEntityType.directory) {
            throw StateError('Unexpected directory at OCR model path');
          }
          targets.add((path, type));
        }
      }
      for (final (path, type) in targets) {
        if (type == FileSystemEntityType.link) {
          await Link(path).delete();
        } else if (type == FileSystemEntityType.file) {
          await File(path).delete();
        }
      }
    } finally {
      _deleting.remove(model.id);
    }
  }

  void close() => _dio.close(force: true);
  static const version = 'ppocr-v4-mobile-1';
  static const revision = '1cfba2e90fc938db55889873735088de210cc173';
  static const mirrorBase =
      'https://gitee.com/sobranie2406/modu-models/releases/download/ocr-v1';
  String downloadUrl(String file, OcrDownloadSource source) {
    final spec = model.files[file];
    if (spec == null) throw ArgumentError.value(file, 'file');
    return source == OcrDownloadSource.gitee
        ? '$mirrorBase/${model.id}-${model.revision}-${spec.$1.split('/').last}'
        : '${model.upstreamBase}/${model.revision}/${spec.$1}';
  }

  static bool allowedDownloadUri(Uri uri, OcrDownloadSource source) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.port != 443) {
      return false;
    }
    final host = uri.host;
    return source == OcrDownloadSource.gitee
        ? (host == 'gitee.com' &&
                uri.path.startsWith('/sobranie2406/modu-models/')) ||
            (host == 'foruda.gitee.com' && uri.path.startsWith('/attach_file/'))
        : host == 'huggingface.co' ||
            host.endsWith('.huggingface.co') ||
            host == 'hf.co' ||
            host.endsWith('.hf.co') ||
            (host == 'www.modelscope.cn' &&
                uri.path.startsWith('/models/RapidAI/RapidOCR/')) ||
            (host == 'cdn-lfs-cn-1.modelscope.cn' &&
                uri.path.startsWith('/prod/lfs-objects/'));
  }

  int get totalBytes => model.totalBytes;
  Future<Directory> root() async =>
      directory ??
      Directory(
          '${(await getApplicationSupportDirectory()).path}/ocr/${model.id}');
  Future<bool> available() async {
    final dir = await root();
    for (final entry in model.files.entries) {
      final file = File('${dir.path}/${entry.key}');
      if (!await file.exists() || await file.length() != entry.value.$2) {
        return false;
      }
    }
    return true;
  }

  Future<void> verify() async {
    final dir = await root();
    for (final entry in model.files.entries) {
      if (!await validFile(
          '${dir.path}/${entry.key}', entry.value.$2, entry.value.$3)) {
        throw const FormatException('OCR model integrity check failed');
      }
    }
  }

  static Future<bool> validFile(String path, int length, String digest) =>
      Isolate.run(() async {
        final file = File(path);
        return await file.exists() &&
            await file.length() == length &&
            (await sha256.bind(file.openRead()).first).toString() == digest;
      });

  /// UI owns cancellation. No startup, import or reading path calls download.
  Future<void> download(
      CancelToken token, void Function(int, int) progress) async {
    if (_downloading || _deleting.isNotEmpty || (_readers[model.id] ?? 0) > 0) {
      throw StateError('OCR model files are busy');
    }
    _downloading = true;
    try {
      await _downloadFiles(token, progress, downloadSource);
    } finally {
      _downloading = false;
    }
  }

  Future<void> _downloadFiles(CancelToken token,
      void Function(int, int) progress, OcrDownloadSource source) async {
    void check() {
      if (token.isCancelled) throw token.cancelError!;
    }

    final dir = await root();
    await dir.create(recursive: true);
    var done = 0;
    for (final entry in model.files.entries) {
      check();
      final path = '${dir.path}/${entry.key}', spec = entry.value;
      if (!await validFile(path, spec.$2, spec.$3)) {
        final partial = File('$path.part');
        try {
          var uri = Uri.parse(downloadUrl(entry.key, source));
          for (var hop = 0;; hop++) {
            check();
            if (hop > 5 || !allowedDownloadUri(uri, source)) {
              throw const FormatException(
                  'Untrusted OCR model download redirect');
            }
            final response = await _dio.download(uri.toString(), partial.path,
                cancelToken: token,
                options: Options(
                    receiveTimeout: const Duration(minutes: 2),
                    followRedirects: false,
                    validateStatus: (status) =>
                        status == 200 ||
                        [301, 302, 303, 307, 308].contains(status)),
                onReceiveProgress: (n, _) {
              if (n > spec.$2) token.cancel('Oversized OCR model');
              progress(done + n, totalBytes);
            });
            if (response.statusCode == 200) break;
            final location = response.headers.value('location');
            if (location == null) {
              throw const FormatException('Missing OCR model redirect');
            }
            uri = uri.resolve(location);
          }
          check();
          if (!await validFile(partial.path, spec.$2, spec.$3)) {
            throw const FormatException('OCR model integrity check failed');
          }
          check();
          // Only this pack's invalid file can be replaced.
          final old = File(path);
          if (await old.exists()) await old.delete();
          await partial.rename(path);
        } finally {
          if (await partial.exists()) await partial.delete();
        }
      }
      done += spec.$2;
      progress(done, totalBytes);
    }
  }
}
