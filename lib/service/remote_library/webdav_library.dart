import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/book_formats.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

class LibraryConnection {
  const LibraryConnection(
      {required this.url,
      this.username = '',
      this.password = '',
      this.allowHttp = false});
  final String url, username, password;
  final bool allowHttp;

  Uri get root {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme == 'http' && !allowHttp)) {
      throw const FormatException('Invalid WebDAV URL');
    }
    final result =
        uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
    if (!_safeSegments(result))
      throw const FormatException('Invalid root path');
    return result;
  }
}

/// Local preferences; shared only through opt-in encrypted sync/backups.
class LibraryConnectionStore {
  static const key = 'remoteLibraryConnection';
  static Future<LibraryConnection?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return null;
    try {
      return decode(raw);
    } catch (_) {
      return null;
    }
  }

  static LibraryConnection? decode(String raw) {
    if (raw.isEmpty)
      return null; // Explicit clear marker, distinct from a new device.
    final map = jsonDecode(raw) as Map;
    if (map['allowHttp'] != null && map['allowHttp'] is! bool) {
      throw const FormatException('Invalid library connection');
    }
    final value = LibraryConnection(
      url: map['url'] as String,
      username: map['username'] as String? ?? '',
      password: map['password'] as String? ?? '',
      allowHttp: map['allowHttp'] == true,
    );
    value.root;
    return value;
  }

  static Future<void> save(LibraryConnection value) async {
    value.root;
    final ok = await (await SharedPreferences.getInstance()).setString(
        key,
        jsonEncode({
          'url': value.url.trim(),
          'username': value.username,
          'password': value.password,
          'allowHttp': value.allowHttp
        }));
    if (!ok) throw StateError('Cannot save connection');
  }

  static Future<void> clear() async {
    // Keep a credential-free deletion marker so encrypted sync can propagate
    // an explicit clear, but a fresh device cannot erase a configured server.
    final ok = await (await SharedPreferences.getInstance()).setString(key, '');
    if (!ok) throw StateError('Cannot clear connection');
  }
}

bool _safeSegments(Uri uri) {
  try {
    return uri.pathSegments.every((s) =>
        s != '..' &&
        s != '.' &&
        !s.contains('/') &&
        !s.contains('\\') &&
        !s.contains(RegExp(r'[\x00-\x1f\x7f]')));
  } on FormatException {
    return false;
  }
}

class LibraryListingException extends FormatException {
  const LibraryListingException(this.reason) : super(reason);
  final String reason;
}

List<LibraryEntry> _parseLibraryBytes((Uint8List, Uri, Uri) input) {
  final client = WebdavLibrary(LibraryConnection(
      url: input.$2.toString(), allowHttp: input.$2.scheme == 'http'));
  try {
    return client.parseListing(utf8.decode(input.$1), input.$3);
  } on LibraryListingException {
    rethrow;
  } on FormatException {
    throw const LibraryListingException('invalid');
  } finally {
    client.close();
  }
}

class LibraryEntry {
  const LibraryEntry(this.uri, this.name, this.isDirectory, this.size,
      {this.createdAt, this.modifiedAt});
  final Uri uri;
  final String name;
  final bool isDirectory;
  final int? size;
  final DateTime? createdAt, modifiedAt;
  bool get isBook =>
      !isDirectory &&
      allowBookExtensions.contains(name.split('.').last.toLowerCase());
}

class WebdavLibrary {
  WebdavLibrary(LibraryConnection connection)
      : root = connection.root,
        _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          sendTimeout: const Duration(seconds: 15),
          followRedirects: false,
          headers: {
            'Accept-Encoding': 'identity',
            if (connection.username.isNotEmpty)
              'Authorization':
                  'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.password}'))}',
          },
        ));
  final Uri root;
  final Dio _dio;
  static const maxBookBytes = 512 * 1024 * 1024;
  static const maxListingBytes = 32 * 1024 * 1024;

  bool contains(Uri uri) =>
      uri.scheme == root.scheme &&
      uri.origin == root.origin &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      _safeSegments(uri) &&
      uri.path.startsWith(root.path);

  void _check(Uri uri) {
    if (!contains(uri))
      throw const FormatException('Outside configured library');
  }

  Future<List<LibraryEntry>> list(Uri directory,
      {CancelToken? cancelToken}) async {
    _check(directory);
    final response = await _dio.requestUri<ResponseBody>(directory,
        data: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop>'
            '<d:resourcetype/><d:getcontentlength/>'
            '<d:creationdate/><d:getlastmodified/></d:prop></d:propfind>',
        options: Options(
            method: 'PROPFIND',
            responseType: ResponseType.stream,
            headers: {
              'Depth': '1',
              'Content-Type': 'application/xml; charset=utf-8'
            },
            validateStatus: (code) => code == 207),
        cancelToken: cancelToken);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.data!.stream) {
      if (bytes.length + chunk.length > maxListingBytes) {
        throw const LibraryListingException('tooLarge');
      }
      bytes.add(chunk);
    }
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    // Decode and parse large XML listings off the UI isolate.
    final entries =
        await compute(_parseLibraryBytes, (bytes.takeBytes(), root, directory));
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    return entries;
  }

  List<LibraryEntry> parseListing(String source, Uri directory) {
    _check(directory);
    if (source.length > maxListingBytes) {
      throw const LibraryListingException('tooLarge');
    }
    if (source.contains('<!DOCTYPE')) {
      throw const LibraryListingException('invalid');
    }
    final document = XmlDocument.parse(source);
    final top = document.rootElement;
    if (top.name.local != 'multistatus' || top.namespaceUri != 'DAV:') {
      throw const FormatException('Not a WebDAV response');
    }
    Iterable<XmlElement> children(XmlElement e, String name) => e.childElements
        .where((c) => c.name.local == name && c.namespaceUri == 'DAV:');
    final entries = <String, LibraryEntry>{};
    for (final response in children(top, 'response')) {
      final href = children(response, 'href').firstOrNull?.innerText;
      if (href == null) continue;
      final raw = Uri.tryParse(href.trim());
      if (raw == null || !_safeSegments(raw)) continue;
      var uri = directory.resolveUri(raw);
      if (!contains(uri)) continue;
      final props = children(response, 'propstat')
          .where((p) => RegExp(r'\s200(?:\s|$)')
              .hasMatch(children(p, 'status').firstOrNull?.innerText ?? ''))
          .expand((p) => children(p, 'prop'))
          .toList();
      if (props.isEmpty) continue;
      final directoryType = props
          .expand((p) => children(p, 'resourcetype'))
          .any((t) => children(t, 'collection').isNotEmpty);
      if (directoryType && !uri.path.endsWith('/'))
        uri = uri.replace(path: '${uri.path}/');
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final parent = directory.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.length != parent.length + 1 ||
          !uri.path.startsWith(directory.path)) continue;
      final size = int.tryParse(props
              .expand((p) => children(p, 'getcontentlength'))
              .firstOrNull
              ?.innerText ??
          '');
      entries[uri.toString()] = LibraryEntry(uri, segments.last, directoryType,
          size != null && size >= 0 ? size : null,
          createdAt:
              _propertyDate(props.expand((p) => children(p, 'creationdate'))),
          modifiedAt: _propertyDate(
              props.expand((p) => children(p, 'getlastmodified'))));
    }
    return entries.values.toList()
      ..sort((a, b) => a.isDirectory != b.isDirectory
          ? (a.isDirectory ? -1 : 1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Sequential Depth-1 requests keep directory imports read-only and bounded.
  Future<List<LibraryEntry>> discoverBooks(Uri directory,
      {required CancelToken cancelToken}) async {
    _check(directory);
    final pending = <(Uri, int)>[(directory, 0)];
    final visited = <Uri>{};
    final books = <Uri, LibraryEntry>{};
    while (pending.isNotEmpty) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final (current, depth) = pending.removeLast();
      if (!visited.add(current)) continue;
      if (depth > 32 || visited.length > 10000) {
        throw const LibraryListingException('scanLimit');
      }
      for (final entry in await list(current, cancelToken: cancelToken)) {
        if (cancelToken.isCancelled) throw cancelToken.cancelError!;
        if (entry.name.startsWith('.')) continue;
        if (entry.isDirectory) {
          pending.add((entry.uri, depth + 1));
        } else if (entry.isBook) {
          books[entry.uri] = entry;
          if (books.length > 50000) {
            throw const LibraryListingException('scanLimit');
          }
        }
      }
    }
    return books.values.toList()
      ..sort((a, b) => a.uri.path.compareTo(b.uri.path));
  }

  Future<void> download(LibraryEntry entry, File target, CancelToken cancel,
      void Function(int received, int total) onProgress) async {
    _check(entry.uri);
    if (!entry.isBook || (entry.size ?? 0) > maxBookBytes) {
      throw const FormatException('Unsupported file or file too large');
    }
    final partial = File('${target.path}.part');
    if (await target.exists() || await partial.exists()) {
      throw StateError('Download staging file already exists');
    }
    RandomAccessFile? output;
    try {
      final response = await _dio.getUri<ResponseBody>(entry.uri,
          options: Options(
              responseType: ResponseType.stream,
              validateStatus: (code) => code == 200),
          cancelToken: cancel);
      final type = response.headers.value('content-type') ?? '';
      final total =
          int.tryParse(response.headers.value('content-length') ?? '') ?? -1;
      if (type.toLowerCase().contains('text/html') || total > maxBookBytes) {
        await response.data!.stream.listen(null).cancel();
        throw const FormatException('Not a book or file too large');
      }
      output = await partial.open(mode: FileMode.write);
      var received = 0;
      await for (final chunk in response.data!.stream) {
        if (cancel.isCancelled) throw StateError('Cancelled');
        received += chunk.length;
        if (received > maxBookBytes)
          throw const FormatException('File too large');
        await output.writeFrom(chunk);
        onProgress(received, total);
      }
      if (cancel.isCancelled ||
          received == 0 ||
          (total >= 0 && received != total)) {
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

  void close() => _dio.close(force: true);
}

DateTime? _propertyDate(Iterable<XmlElement> properties) {
  for (final property in properties) {
    final value = property.innerText.trim();
    if (value.isEmpty) continue;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toUtc();
    try {
      return HttpDate.parse(value).toUtc();
    } on HttpException {
      // Optional metadata must never make an otherwise valid listing fail.
    }
  }
  return null;
}

String libraryError(Object error, bool zh, {bool listing = false}) {
  if (error is LibraryListingException) {
    if (error.reason == 'tooLarge') {
      return zh
          ? '目录清单超过 32 MiB，请拆分文件夹后重试（不是单本书籍大小限制）。'
          : 'Directory listing exceeds 32 MiB. Split the folder and retry; this is not a book size limit.';
    }
    if (error.reason == 'scanLimit') {
      return zh
          ? '文件夹扫描范围过大，请选择较小的子文件夹导入。'
          : 'Folder scan limit reached. Select a smaller subfolder to import.';
    }
    return zh
        ? '无法解析服务器返回的目录清单，请检查 WebDAV 服务的响应格式。'
        : 'Cannot parse the directory listing returned by the WebDAV server.';
  }
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403)
      return zh
          ? '认证失败或没有读取权限，请检查账号和密码。'
          : 'Authentication failed or access denied.';
    if (status == 404)
      return zh ? '目录或文件不存在，请检查 WebDAV 地址。' : 'Directory or file not found.';
    if (status != null && status >= 300 && status < 400)
      return zh
          ? '服务器要求跳转，请直接填写最终 WebDAV 地址。'
          : 'Redirect refused. Use the final WebDAV URL.';
    return zh
        ? '连接失败，请检查网络、服务器地址和 HTTPS 证书。'
        : 'Connection failed. Check network, URL and HTTPS certificate.';
  }
  if (listing) {
    return zh
        ? '读取目录失败，请检查目录路径及服务器返回的清单格式。'
        : 'Cannot read this folder. Check its path and the server listing format.';
  }
  return zh
      ? '操作失败：请检查地址、文件格式或大小（最大 512 MiB）后重试。'
      : 'Operation failed. Check the URL, file format and size (max 512 MiB).';
}
