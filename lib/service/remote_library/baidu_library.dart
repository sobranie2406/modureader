import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/service/remote_library/baidu_auth.dart';
import 'package:anx_reader/service/remote_library/webdav_library.dart';
import 'package:dio/dio.dart';

class BaiduEntry extends LibraryEntry {
  const BaiduEntry(super.uri, super.name, super.isDirectory, super.size,
      {required this.fileId, super.createdAt, super.modifiedAt});
  final int fileId;
}

class BaiduLibrary extends RemoteLibrary {
  BaiduLibrary(this.auth, {Dio? client})
      : _dio = client ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 15),
                followRedirects: false));
  final BaiduAuth auth;
  final Dio _dio;
  @override
  final root = Uri.parse('https://pan.baidu.com/');

  @override
  bool contains(Uri uri) =>
      uri.origin == root.origin &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.pathSegments.every((part) =>
          part != '.' &&
          part != '..' &&
          !part.contains('/') &&
          !part.contains(RegExp(r'[\\\x00-\x1f\x7f]')));

  Future<Map<String, dynamic>> _api(
      String path, Map<String, String> query, CancelToken? cancel) async {
    final access = await auth.accessToken();
    if (cancel?.isCancelled == true) throw cancel!.cancelError!;
    final result = await boundedJson(
        _dio,
        Uri.https('pan.baidu.com', path, {...query, 'access_token': access}),
        cancel);
    final code = result['errno'];
    if (code != 0) {
      if (code == -6 || code == 110 || code == 111) {
        throw const RemoteLibraryException('百度授权已失效，请在远程书库设置中重新连接。',
            'Baidu authorization expired. Reconnect in Remote library settings.');
      }
      throw RemoteLibraryException(
          '百度网盘请求失败（错误码 $code）。', 'Baidu Netdisk request failed (code $code).');
    }
    return result;
  }

  @override
  Future<List<LibraryEntry>> list(Uri directory,
      {CancelToken? cancelToken}) async {
    if (!contains(directory)) throw const FormatException('Invalid directory');
    final path = directory.path == '/'
        ? '/'
        : Uri.decodeComponent(directory.path).replaceFirst(RegExp(r'/$'), '');
    final entries = <int, LibraryEntry>{};
    for (var start = 0; start < 50000; start += 1000) {
      final result = await _api(
          '/rest/2.0/xpan/file',
          {
            'method': 'list',
            'dir': path,
            'start': '$start',
            'limit': '1000',
            'order': 'name',
            'desc': '0',
          },
          cancelToken);
      final list = result['list'];
      if (list is! List || list.length > 1000) {
        throw const FormatException('Invalid file list');
      }
      final previousCount = entries.length;
      for (final value in list) {
        if (value is! Map) throw const FormatException('Invalid file entry');
        final name = value['server_filename'];
        final remotePath = value['path'];
        final id = value['fs_id'];
        final size = value['size'];
        final isDir = value['isdir'] == 1;
        if (name is! String ||
            name.isEmpty ||
            id is! int ||
            id <= 0 ||
            size is! int ||
            size < 0 ||
            remotePath is! String ||
            name.contains(RegExp(r'[/\\\x00-\x1f\x7f]')) ||
            name == '.' ||
            name == '..' ||
            remotePath != '${path == '/' ? '' : path}/$name') {
          throw const FormatException('Invalid file path');
        }
        final uri = root.replace(
            pathSegments:
                '$remotePath${isDir ? '/' : ''}'.substring(1).split('/'));
        if (!contains(uri)) throw const FormatException('Invalid file path');
        DateTime? date(Object? seconds) => seconds is int &&
                seconds > 0 &&
                seconds < 8640000000000
            ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
            : null;
        entries[id] = BaiduEntry(uri, name, isDir, size,
            fileId: id,
            createdAt: date(value['server_ctime']),
            modifiedAt: date(value['server_mtime']));
      }
      if (list.length < 1000) {
        return entries.values
            .where((entry) => entry.isDirectory || entry.isBook)
            .toList();
      }
      if (entries.length == previousCount) {
        throw const FormatException('Repeated file list');
      }
    }
    throw const LibraryListingException('scanLimit');
  }

  static bool trustedDownload(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasFragment &&
      (!uri.hasPort || uri.port == 443) &&
      ['baidu.com', 'baidupcs.com']
          .any((domain) => uri.host == domain || uri.host.endsWith('.$domain'));

  @override
  Future<void> download(LibraryEntry entry, File target, CancelToken cancel,
      void Function(int, int) onProgress) async {
    if (entry is! BaiduEntry ||
        !contains(entry.uri) ||
        !entry.isBook ||
        (entry.size ?? 0) > WebdavLibrary.maxBookBytes) {
      throw const FormatException('Invalid book');
    }
    final meta = await _api(
        '/rest/2.0/xpan/multimedia',
        {
          'method': 'filemetas',
          'fsids': jsonEncode([entry.fileId]),
          'dlink': '1',
        },
        cancel);
    final files = meta['list'];
    if (files is! List ||
        files.length != 1 ||
        files.first is! Map ||
        files.first['fs_id'] != entry.fileId ||
        files.first['dlink'] is! String) {
      throw const FormatException('Invalid download metadata');
    }
    var uri = Uri.parse(files.first['dlink'] as String);
    if (!trustedDownload(uri)) {
      throw const FormatException('Untrusted download host');
    }
    uri = uri.replace(queryParameters: {
      ...uri.queryParameters,
      'access_token': await auth.accessToken()
    });
    final partial = File('${target.path}.part');
    if (await target.exists() || await partial.exists()) {
      throw StateError('Target exists');
    }
    RandomAccessFile? output;
    try {
      Response<ResponseBody>? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!trustedDownload(uri)) {
          throw const FormatException('Untrusted redirect');
        }
        final current = await _dio.getUri<ResponseBody>(uri,
            cancelToken: cancel,
            options: Options(
                responseType: ResponseType.stream,
                followRedirects: false,
                validateStatus: (s) =>
                    s == 200 || [301, 302, 303, 307, 308].contains(s),
                headers: {
                  'User-Agent': 'pan.baidu.com',
                  'Accept-Encoding': 'identity'
                }));
        if (current.statusCode == 200) {
          response = current;
          break;
        }
        final location = current.headers.value('location');
        await current.data!.stream.listen(null).cancel();
        if (location == null) {
          throw const FormatException('Missing download redirect');
        }
        // Follow the signed URL only; never append the account token to redirects.
        uri = uri.resolve(location);
      }
      if (response == null) throw const FormatException('Too many redirects');
      final type = response.headers.value('content-type') ?? '';
      final total =
          int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
      if (type.contains('text/html') ||
          type.contains('application/json') ||
          total > WebdavLibrary.maxBookBytes) {
        await response.data!.stream.listen(null).cancel();
        throw const FormatException('Invalid download response');
      }
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in response.data!.stream) {
        if (cancel.isCancelled) throw cancel.cancelError!;
        received += chunk.length;
        if (received > WebdavLibrary.maxBookBytes) {
          throw const FormatException('File too large');
        }
        await output.writeFrom(chunk);
        onProgress(received, total);
      }
      if (cancel.isCancelled ||
          received == 0 ||
          (total >= 0 && total != received) ||
          (entry.size != null && entry.size != received)) {
        throw const FormatException('Incomplete download');
      }
      await output.close();
      output = null;
      await partial.rename(target.path);
    } finally {
      await output?.close();
      if (await partial.exists()) await partial.delete();
    }
  }

  @override
  void close() => _dio.close(force: true);
}
